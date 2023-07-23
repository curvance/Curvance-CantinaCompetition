// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, IPriceRouter, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";
import { IStashWrapper } from "contracts/interfaces/external/aura/IStashWrapper.sol";

contract AuraPositionVault is BasePositionVault {
    using Math for uint256;

    /// EVENTS ///
    event Harvest(uint256 yield);

    /// STRUCTS ///
    struct StrategyData {
        /// @notice Balancer vault contract
        IBalancerVault balancerVault;
        /// @notice Balancer Pool Id
        bytes32 balancerPoolId;
        /// @notice Aura Pool Id
        uint256 pid;
        /// @notice Aura Rewarder contract
        IBaseRewardPool rewarder;
        /// @notice Aura Booster contract
        IBooster booster;
        /// @notice Aura reward assets
        address[] rewardTokens;
        /// @notice Balancer LP underlying assets
        address[] underlyingTokens;
    }

    /// CONSTANTS ///
    address private constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    /// STORAGE ///

    /// Vault Strategy Data
    StrategyData public strategyData;
    /// @notice Is an underlying token of the BPT
    mapping(address => bool) public isUnderlyingToken;

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        uint256 pid_,
        address rewarder_,
        address booster_
    ) BasePositionVault(asset_, centralRegistry_) {


        strategyData.pid = pid_;
        strategyData.booster = IBooster(booster_);

        /// query actual convex pool configuration data
        (address pidToken, , , address balRewards, , bool shutdown) = strategyData.booster.poolInfo(strategyData.pid);

        /// validate that the pool is still active and that the lp token and rewarder in aura matches what we are configuring for
        require (pidToken == asset() && !shutdown && balRewards == rewarder_, "AuraPositionVault: improper aura vault config");

        strategyData.rewarder = IBaseRewardPool(rewarder_);
        strategyData.balancerVault = IBalancerVault(IBalancerPool(pidToken).getVault());
        strategyData.balancerPoolId = IBalancerPool(pidToken).getPoolId();

        /// add BAL as a reward token, then let aura tell you what rewards the vault will receive
        strategyData.rewardTokens.push() = BAL;
        uint256 extraRewardsLength = strategyData.rewarder.extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ++i) {
            strategyData.rewardTokens.push() = IStashWrapper(IRewards(strategyData.rewarder.extraRewards(i)).rewardToken()).baseToken();
        }

        /// query liquidity pools underlying tokens from the balancer vault
        (address[] memory underlyingTokens, ,) = strategyData.balancerVault.getPoolTokens(strategyData.balancerPoolId);
        strategyData.underlyingTokens = underlyingTokens;
        
        uint256 numUnderlyingTokens = strategyData.underlyingTokens.length;
        for (uint256 i; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[strategyData.underlyingTokens[i++]] = true;
            }
        }
        
    }

    /// PERMISSIONED FUNCTIONS ///
    function setRewardTokens(
        address[] calldata rewardTokens
    ) external onlyDaoPermissions {
        strategyData.rewardTokens = rewardTokens;
    }

    /// REWARD AND HARVESTING LOGIC ///
    /// @notice Harvests and compounds outstanding vault rewards and vests pending rewards
    /// @dev Only callable by Gelato Network bot
    /// @param data Bytes array for aggregator swap data
    /// @param maxSlippage Maximum allowable slippage on swapping
    /// @return yield The amount of new assets acquired from compounding vault yield
    function harvest(
        bytes memory data,
        uint256 maxSlippage
    ) public override onlyHarvestor vaultActive nonReentrant returns (uint256 yield) {

        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // claim vested rewards
            _vestRewards(_totalAssets + pending);
        }

        // can only harvest once previous reward period is done
        if (
            vaultData.lastVestClaim >=
            vaultData.vestingPeriodEnd
        ) {
            
            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim base aura rewards
            sd.rewarder.getReward(address(this), true);

            // claim extra rewards
            uint256 extraRewardsLength = sd.rewarder.extraRewardsLength();
            if (extraRewardsLength > 1) {
                for (uint256 i = 1; i < extraRewardsLength; ++i) {
                    IRewards(sd.rewarder.extraRewards(i)).getReward();
                }
            }

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

                for (uint256 j; j < numRewardTokens; ++j) {
                    rewardToken = sd.rewardTokens[j];
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

                    (rewardPrice, ) = getPriceRouter().getPrice(rewardToken, true, true);

                    valueIn += rewardAmount.mulDivDown(
                        rewardPrice,
                        10 ** ERC20(rewardToken).decimals()
                    );

                    /// swap from rewardToken to underlying LP token if necessary
                    if (!isUnderlyingToken[rewardToken]) {
                        SwapperLib.swap(
                            swapDataArray[j],
                            centralRegistry.priceRouter(),
                            10000 // swap for 100% slippage, we have slippage check later for global level
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

            for (uint256 k; k < numUnderlyingTokens; ++k) {
                underlyingToken = sd.underlyingTokens[k];
                assets[k] = underlyingToken;
                maxAmountsIn[k] = ERC20(underlyingToken).balanceOf(
                    address(this)
                );
                SwapperLib.approveTokenIfNeeded(
                    underlyingToken,
                    address(sd.balancerVault),
                    maxAmountsIn[k]
                );

                (assetPrice, ) = getPriceRouter().getPrice(
                    underlyingToken,
                    true,
                    true
                );

                valueOut += maxAmountsIn[k].mulDivDown(
                    assetPrice,
                    10 ** ERC20(underlyingToken).decimals()
                );
            }

            // check for slippage
            require(valueOut >
                valueIn.mulDivDown(1e18 - maxSlippage, 1e18), "AuraPositionVault: bad slippage");

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
            vaultData.rewardRate = uint128(yield.mulDivDown(rewardOffset, vestPeriod));
            vaultData.vestingPeriodEnd = uint64(block.timestamp + vestPeriod);
            vaultData.lastVestClaim = uint64(block.timestamp);
            emit Harvest(yield);
        } 
        // else yield is zero
    }

    /// INTERNAL POSITION LOGIC ///
    /// @notice Deposits specified amount of assets into Aura booster contract
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(asset(), address(strategyData.booster), assets);
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
