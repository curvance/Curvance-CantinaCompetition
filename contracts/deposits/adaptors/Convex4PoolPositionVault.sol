// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, IPriceRouter, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { ICurveFi } from "contracts/interfaces/external/curve/ICurveFi.sol";
import { ICurveSwaps } from "contracts/interfaces/external/curve/ICurveSwaps.sol";

contract ConvexPositionVault is BasePositionVault {
    using Math for uint256;

    /// EVENTS ///
    event Harvest(uint256 yield);

    /// STRUCTS ///
    struct StrategyData {
        /// @notice Curve Pool Address.
        ICurveFi curvePool;
        /// @notice Convex Pool Id.
        uint256 pid;
        /// @notice Convex Rewarder contract.
        IBaseRewardPool rewarder;
        /// @notice Convex Booster contract.
        IBooster booster;
        /// @notice Convex reward assets.
        address[] rewardTokens;
        /// @notice Curve LP underlying assets.
        address[] underlyingTokens;
    }

    /// STORAGE ///

    /// Vault Strategy Data
    StrategyData public strategyData;

    /// @notice Curve LP underlying assets.
    mapping(address => bool) public isUnderlyingToken;

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        ICurveFi curvePool_,
        uint256 pid_,
        address rewarder_,
        address booster_,
        address[] memory rewardTokens_
    ) BasePositionVault(asset_, centralRegistry_) {

        // We will only support Curves new ng pools with read only reentry protection
        require(pid_ > 176, "ConvexPositionVault: unsafe pools");

        strategyData.curvePool = curvePool_;
        strategyData.pid = pid_;
        strategyData.rewarder = IBaseRewardPool(rewarder_);
        strategyData.booster = IBooster(booster_);
        strategyData.rewardTokens = rewardTokens_;

        uint256 coinsLength;
        address token;
        // Figure out how many tokens are in the curve pool.
        while (true) {
            try strategyData.curvePool.coins(coinsLength) {
                ++coinsLength;
            } catch {
                break;
            }
        }

        require (coinsLength == 4, "ConvexPositionVault: vault configured for 3Pool");

        strategyData.underlyingTokens = new address[](coinsLength);
        for (uint256 i; i < coinsLength; ) {
            token = strategyData.curvePool.coins(i);
            strategyData.underlyingTokens[i] = token;
            isUnderlyingToken[token] = true;

            unchecked {
                ++i;
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
    /// @notice Harvests and compounds outstanding vault rewards and vests pending rewards.
    /// @dev Only callable by Gelato Network bot
    /// @param data Bytes array for aggregator swap data.
    /// @param maxSlippage Maximum allowable slippage on swapping.
    /// @return yield The amount of new assets acquired from compounding vault yield.
    function harvest(
        bytes memory data,
        uint256 maxSlippage
    ) public override onlyHarvestor vaultActive nonReentrant returns (uint256 yield) {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // We need to claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest once previous reward period is done.
        if (
            vaultData.lastVestClaim >=
            vaultData.vestingPeriodEnd
        ) {

            // Cache strategy data
            StrategyData memory sd = strategyData;

            // Harvest convex position.
            sd.rewarder.getReward(address(this), true);

            // Claim extra rewards
            uint256 extraRewardsLength = sd.rewarder.extraRewardsLength();
            for (uint256 i; i < extraRewardsLength; ++i) {
                IRewards extraReward = IRewards(sd.rewarder.extraRewards(i));
                extraReward.getReward();
            }

            uint256 valueIn;
            
            {

                SwapperLib.Swap[] memory swapDataArray = abi.decode(
                    data,
                    (SwapperLib.Swap[])
                );
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

                    // Take platform fee
                    protocolFee = rewardAmount.mulDivDown(
                        vaultHarvestFee(),
                        1e18
                    );
                    rewardAmount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        address(rewardToken),
                        centralRegistry.feeAccumulator(),
                        protocolFee
                    );

                    (rewardPrice, ) = getPriceRouter().getPrice(address(rewardToken), true, true);

                    // Get the reward token value in USD.
                    valueIn = rewardAmount.mulDivDown(
                        rewardPrice,
                        10 ** ERC20(rewardToken).decimals()
                    );

                    if (!isUnderlyingToken[rewardToken]) {
                        SwapperLib.swap(
                            swapDataArray[j],
                            centralRegistry.priceRouter(),
                            10000 // swap for 100% slippage, we have slippage check later for global level
                        );
                    }

                }
            }

            // add liquidity to curve and check for slippage
            require(_addLiquidityToCurve() >
                valueIn.mulDivDown(1e18 - maxSlippage, 1e18), "ConvexPositionVault: bad slippage");
            
            // Deposit assets into convex
            yield = ERC20(asset()).balanceOf(address(this));
            _deposit(yield);

            // Update vesting info
            vaultData.rewardRate = uint128(yield.mulDivDown(rewardOffset, vestPeriod));
            vaultData.vestingPeriodEnd = uint64(block.timestamp + vestPeriod);
            vaultData.lastVestClaim = uint64(block.timestamp);

            emit Harvest(yield);
        } 
        // else yield is zero
    }

    /// INTERNAL POSITION LOGIC ///
    /// @notice Withdraws specified amount of assets from Convex reward pool
    /// @param assets The amount of assets to withdraw
    function _withdraw(uint256 assets) internal override {
        strategyData.rewarder.withdrawAndUnwrap(assets, false);
    }

    /// @notice Deposits specified amount of assets into Convex booster contract
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(asset(), address(strategyData.booster), assets);
        strategyData.booster.deposit(strategyData.pid, assets, true);
    }

    /// @notice Gets the balance of assets inside Convex reward pool
    /// @return The current balance of assets
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return strategyData.rewarder.balanceOf(address(this));
    }

    /// @notice Adds underlying tokens to the vaults Curve 4Pool LP
    /// @return valueOut The total value of the assets in USD
    function _addLiquidityToCurve() internal returns (uint256 valueOut) {
        address underlyingToken;
        uint256 assetPrice;
        uint256[4] memory amounts;

        for (uint256 k; k < 4; ++k) {
            underlyingToken = strategyData.underlyingTokens[k];
            amounts[k] = ERC20(underlyingToken).balanceOf(
                address(this)
            );
            SwapperLib.approveTokenIfNeeded(
                underlyingToken,
                address(strategyData.curvePool),
                amounts[k]
            );

            (assetPrice, ) = getPriceRouter().getPrice(
                underlyingToken,
                true,
                true
            );

            valueOut += amounts[k].mulDivDown(
                assetPrice,
                10 ** ERC20(underlyingToken).decimals()
            );
        
        }

        strategyData.curvePool.add_liquidity(amounts, 0, true);

    }

}
