// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BasePositionVault, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";
import { IStashWrapper } from "contracts/interfaces/external/aura/IStashWrapper.sol";

contract AuraPositionVault is BasePositionVault {
    using Math for uint256;

    /// TYPES ///

    /// @param balancerVault Balancer vault contract
    /// @param balancerPoolId Balancer Pool Id
    /// @param pid Aura Pool Id
    /// @param rewarder Aura Rewarder contract
    /// @param booster Aura Booster contract
    /// @param rewardTokens Aura reward assets
    /// @param underlyingTokens Balancer LP underlying assets
    struct StrategyData {
        IBalancerVault balancerVault;
        bytes32 balancerPoolId;
        uint256 pid;
        IBaseRewardPool rewarder;
        IBooster booster;
        address[] rewardTokens;
        address[] underlyingTokens;
    }

    /// CONSTANTS ///

    address private constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address private constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    /// STORAGE ///

    /// @notice Vault Strategy Data
    StrategyData public strategyData;

    /// @notice Is an underlying token of the BPT
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// CONSTRUCTOR ///

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        uint256 pid_,
        address rewarder_,
        address booster_
    ) BasePositionVault(asset_, centralRegistry_) {
        strategyData.pid = pid_;
        strategyData.booster = IBooster(booster_);

        // query actual aura pool configuration data
        (
            address pidToken,
            ,
            ,
            address balRewards,
            ,
            bool shutdown
        ) = strategyData.booster.poolInfo(strategyData.pid);

        // validate that the pool is still active and that the lp token
        // and rewarder in aura matches what we are configuring for
        require(
            pidToken == asset() && !shutdown && balRewards == rewarder_,
            "AuraPositionVault: improper aura vault config"
        );

        strategyData.rewarder = IBaseRewardPool(rewarder_);
        strategyData.balancerVault = IBalancerVault(
            IBalancerPool(pidToken).getVault()
        );
        strategyData.balancerPoolId = IBalancerPool(pidToken).getPoolId();

        // add BAL as a reward token, then let aura tell you what rewards
        // the vault will receive
        strategyData.rewardTokens.push() = BAL;
        // add AURA as a reward token, since some vaults do not list AURA
        // as a reward token
        strategyData.rewardTokens.push() = AURA;

        uint256 extraRewardsLength = strategyData
            .rewarder
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ++i) {
            address rewardToken = IStashWrapper(
                IRewards(strategyData.rewarder.extraRewards(i)).rewardToken()
            ).baseToken();

            if (rewardToken != AURA) {
                strategyData.rewardTokens.push() = rewardToken;
            }
        }

        // query liquidity pools underlying tokens from the balancer vault
        (address[] memory underlyingTokens, , ) = strategyData
            .balancerVault
            .getPoolTokens(strategyData.balancerPoolId);
        strategyData.underlyingTokens = underlyingTokens;

        uint256 numUnderlyingTokens = strategyData.underlyingTokens.length;
        for (uint256 i; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[strategyData.underlyingTokens[i++]] = true;
            }
        }
    }

    /// EXTERNAL FUNCTIONS ///

    // PERMISSIONED FUNCTIONS

    function reQueryRewardTokens() external onlyDaoPermissions {
        delete strategyData.rewardTokens;

        // add BAL as a reward token, then let aura tell you what rewards
        // the vault will receive
        strategyData.rewardTokens.push() = BAL;
        // add AURA as a reward token, since some vaults do not list AURA
        // as a reward token
        strategyData.rewardTokens.push() = AURA;

        uint256 extraRewardsLength = strategyData
            .rewarder
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ++i) {
            address rewardToken = IStashWrapper(
                IRewards(strategyData.rewarder.extraRewards(i)).rewardToken()
            ).baseToken();

            if (rewardToken != AURA) {
                strategyData.rewardTokens.push() = rewardToken;
            }
        }
    }

    /// PUBLIC FUNCTIONS ///

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards
    /// @dev Only callable by Gelato Network bot
    /// @param data Bytes array for aggregator swap data
    /// @param maxSlippage Maximum allowable slippage on swapping
    /// @return yield The amount of new assets acquired from compounding vault yield
    function harvest(
        bytes memory data,
        uint256 maxSlippage
    )
        public
        override
        onlyHarvestor
        vaultActive
        returns (uint256 yield)
    {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // claim vested rewards
            _vestRewards(_totalAssets + pending);
        }

        // can only harvest once previous reward period is done
        if (vaultData.lastVestClaim >= vaultData.vestingPeriodEnd) {
            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim aura rewards
            sd.rewarder.getReward(address(this), true);

            uint256 valueIn;

            {
                SwapperLib.Swap[] memory swapDataArray = abi.decode(
                    data,
                    (SwapperLib.Swap[])
                );

                // swap assets to one of pool token
                uint256 numRewardTokens = sd.rewardTokens.length;
                address rewardToken;
                uint256 rewardAmount;
                uint256 protocolFee;
                uint256 rewardPrice;

                for (uint256 i; i < numRewardTokens; ++i) {
                    rewardToken = sd.rewardTokens[i];
                    rewardAmount = ERC20(rewardToken).balanceOf(address(this));

                    if (rewardAmount == 0) {
                        continue;
                    }

                    // take protocol fee
                    protocolFee = rewardAmount.mulDivDown(
                        vaultHarvestFee(),
                        1e18
                    );
                    rewardAmount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        rewardToken,
                        centralRegistry.feeAccumulator(),
                        protocolFee
                    );

                    (rewardPrice, ) = getPriceRouter().getPrice(
                        rewardToken,
                        true,
                        true
                    );

                    valueIn += rewardAmount.mulDivDown(
                        rewardPrice,
                        10 ** ERC20(rewardToken).decimals()
                    );

                    // swap from rewardToken to underlying LP token if necessary
                    if (!isUnderlyingToken[rewardToken]) {
                        // swap for 100% slippage
                        // we have slippage check later for global level
                        SwapperLib.swap(
                            swapDataArray[i],
                            centralRegistry.priceRouter(),
                            10000
                        );
                    }
                }
            }

            // prep adding liquidity to balancer
            uint256 valueOut;
            uint256 numUnderlyingTokens = sd.underlyingTokens.length;
            address[] memory assets = new address[](numUnderlyingTokens);
            uint256[] memory maxAmountsIn = new uint256[](numUnderlyingTokens);
            address underlyingToken;
            uint256 assetPrice;

            for (uint256 i; i < numUnderlyingTokens; ++i) {
                underlyingToken = sd.underlyingTokens[i];
                assets[i] = underlyingToken;
                maxAmountsIn[i] = ERC20(underlyingToken).balanceOf(
                    address(this)
                );

                SwapperLib.approveTokenIfNeeded(
                    underlyingToken,
                    address(sd.balancerVault),
                    maxAmountsIn[i]
                );

                (assetPrice, ) = getPriceRouter().getPrice(
                    underlyingToken,
                    true,
                    true
                );

                valueOut += maxAmountsIn[i].mulDivDown(
                    assetPrice,
                    10 ** ERC20(underlyingToken).decimals()
                );
            }

            // check for slippage
            require(
                valueOut > valueIn.mulDivDown(1e18 - maxSlippage, 1e18),
                "AuraPositionVault: bad slippage"
            );

            // deposit assets into balancer
            sd.balancerVault.joinPool(
                sd.balancerPoolId,
                address(this),
                address(this),
                IBalancerVault.JoinPoolRequest(
                    assets,
                    maxAmountsIn,
                    abi.encode(
                        IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                        maxAmountsIn,
                        1
                    ),
                    false // do not use internal balances
                )
            );

            // deposit assets into aura
            yield = ERC20(asset()).balanceOf(address(this));
            _deposit(yield);

            // update vesting info
            vaultData.rewardRate = uint128(
                yield.mulDivDown(rewardOffset, vestPeriod)
            );
            vaultData.vestingPeriodEnd = uint64(block.timestamp + vestPeriod);
            vaultData.lastVestClaim = uint64(block.timestamp);

            emit Harvest(yield);
        }
        // else yield is zero
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Deposits specified amount of assets into Aura booster contract
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(
            asset(),
            address(strategyData.booster),
            assets
        );
        strategyData.booster.deposit(strategyData.pid, assets, true);
    }

    /// @notice Withdraws specified amount of assets from Aura reward pool
    /// @param assets The amount of assets to withdraw
    function _withdraw(uint256 assets) internal override {
        strategyData.rewarder.withdrawAndUnwrap(assets, false);
    }

    /// @notice Gets the balance of assets inside Aura reward pool
    /// @return The current balance of assets
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return strategyData.rewarder.balanceOf(address(this));
    }
}
