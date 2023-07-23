// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, IPriceRouter, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";

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

    /// STORAGE ///

    /// Vault Strategy Data
    StrategyData public strategyData;
    /// @notice Is an underlying token of the BPT
    mapping(address => bool) public isUnderlyingToken;

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        address balancerVault_,
        bytes32 balancerPoolId_,
        uint256 pid_,
        address rewarder_,
        address booster_,
        address[] memory rewardTokens_,
        address[] memory underlyingTokens_
    ) BasePositionVault(asset_, centralRegistry_) {

        uint256 numUnderlyingTokens = underlyingTokens_.length;

        for (uint256 i; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[underlyingTokens_[i++]] = true;
            }
        }

        strategyData.balancerVault = IBalancerVault(balancerVault_);
        strategyData.balancerPoolId = balancerPoolId_;
        strategyData.pid = pid_;
        strategyData.rewarder = IBaseRewardPool(rewarder_);
        strategyData.booster = IBooster(booster_);
        strategyData.rewardTokens = rewardTokens_;
        strategyData.underlyingTokens = underlyingTokens_;

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
            uint256 rewardTokenCount = 2 + sd.rewarder.extraRewardsLength();
            for (uint256 i = 2; i < rewardTokenCount; ++i) {
                IRewards extraReward = IRewards(sd.rewarder.extraRewards(i - 2));
                extraReward.getReward();
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
