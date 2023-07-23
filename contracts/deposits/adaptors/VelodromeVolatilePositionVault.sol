// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, IPriceRouter, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IOptiSwap } from "contracts/interfaces/external/velodrome/IOptiSwap.sol";
import { IOptiSwapPair } from "contracts/interfaces/external/velodrome/IOptiSwapPair.sol";

contract VelodromeVolatilePositionVault is BasePositionVault {
    using Math for uint256;

    /// EVENTS ///
    event Harvest(uint256 yield);

    /// STRUCTS ///
    struct StrategyData {
        /// @notice Velodrome Gauge contract
        IVeloGauge gauge;
        /// @notice Velodrome Pair Factory contract
        IVeloPairFactory pairFactory;
        /// @notice Velodrome Router contract
        IVeloRouter router;
        /// @notice LP first token address
        address tokenA;
        /// @notice LP second token address
        address tokenB;
        /// @notice Velodrome reward tokens
        address[] rewardTokens;
    }

    /// STORAGE ///

    /// Vault Strategy Data
    StrategyData public strategyData;

    /// @notice Is an underlying token of the vAMM LP
    mapping(address => bool) public isUnderlyingToken;

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        IVeloGauge gauge,
        IVeloPairFactory pairFactory,
        IVeloRouter router,
        address tokenA,
        address tokenB,
        address[] memory rewardTokens
    ) BasePositionVault(asset_, centralRegistry_) {

        strategyData.tokenA = tokenA;
        strategyData.tokenB = tokenB;
        strategyData.gauge = gauge;
        strategyData.router = router;
        strategyData.pairFactory = pairFactory;
        strategyData.rewardTokens = rewardTokens;

        isUnderlyingToken[tokenA] = true;
        isUnderlyingToken[tokenB] = true;

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

            // claim velodrome rewards
            sd.gauge.getReward(address(this), sd.rewardTokens);

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

                for (uint256 i; i < numRewardTokens; ++i) {
                    rewardToken = sd.rewardTokens[i];
                    rewardAmount = ERC20(rewardToken).balanceOf(address(this));

                    if (rewardAmount == 0){
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

                    if (!isUnderlyingToken[rewardToken]) {
                        SwapperLib.swap(
                            swapDataArray[i],
                            centralRegistry.priceRouter(),
                            10000 // swap for 100% slippage, we have slippage check later for global level
                        );
                    }
                }
            }

            uint256 totalAmountA;
            uint256 totalAmountB;

            {
                // swap tokenA to LP Token underlying tokens
                totalAmountA = ERC20(sd.tokenA).balanceOf(address(this));

                require(totalAmountA > 0, "VelodromeVolatilePositionVault: slippage error");

                (uint256 r0, uint256 r1, ) = IVeloPair(asset()).getReserves();
                uint256 reserveA = sd.tokenA == IVeloPair(asset()).token0()
                    ? r0
                    : r1;

                uint256 swapAmount = _optimalDeposit(totalAmountA, reserveA);

                _swapExactTokensForTokens(sd.tokenA, sd.tokenB, swapAmount);

                totalAmountA -= swapAmount;
                totalAmountB = ERC20(sd.tokenB).balanceOf(address(this));

            }

            uint256 valueOut;

            (uint256 tokenAPrice, ) = getPriceRouter().getPrice(sd.tokenA, true, true);
            (uint256 tokenBPrice, ) = getPriceRouter().getPrice(sd.tokenB, true, true);
            valueOut =
                totalAmountA.mulDivDown(
                    tokenAPrice,
                    10 ** ERC20(sd.tokenA).decimals()
                ) +
                totalAmountB.mulDivDown(
                    tokenBPrice,
                    10 ** ERC20(sd.tokenB).decimals()
                );

            // check for slippage
            require(valueOut >
            valueIn.mulDivDown(1e18 - maxSlippage, 1e18), "VelodromeVolatilePositionVault: bad slippage");

            // add liquidity to velodrome lp
            yield = _addLiquidity(
                sd.tokenA,
                sd.tokenB,
                totalAmountA,
                totalAmountB
            );
            
            // deposit assets into velodrome gauge
            _deposit(yield);
            
            // update vesting info
            vaultData.rewardRate = uint128(yield.mulDivDown(rewardOffset, vestPeriod));
            vaultData.vestingPeriodEnd = uint64(block.timestamp + vestPeriod);
            vaultData.lastVestClaim = uint64(block.timestamp);

            emit Harvest(yield);
        } // else yield is zero.
    }

    /// INTERNAL POSITION LOGIC ///
    function _withdraw(uint256 assets) internal override {
        strategyData.gauge.withdraw(assets);
    }

    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(asset(), address(strategyData.gauge), assets);
        strategyData.gauge.deposit(assets, 0);
    }

    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return strategyData.gauge.balanceOf(address(this));
    }

    function _optimalDeposit(
        uint256 amountA,
        uint256 reserveA
    ) internal view returns (uint256) {
        uint256 swapFee = strategyData.pairFactory.getFee(false);
        uint256 swapFeeFactor = 10000 - swapFee;
        uint256 a = (10000 + swapFeeFactor) * reserveA;
        uint256 b = amountA * 10000 * reserveA * 4 * swapFeeFactor;
        uint256 c = Math.sqrt(a * a + b);
        uint256 d = swapFeeFactor * 2;
        return (c - a) / d;
    }

    function _approveRouter(address token, uint256 amount) internal {
        if (ERC20(token).allowance(address(this), address(strategyData.router)) >= amount) {
            return;
        }
            
        SafeTransferLib.safeApprove(token, address(strategyData.router), type(uint256).max);
    }

    function _swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal {
        _approveRouter(tokenIn, amount);
        strategyData.router.swapExactTokensForTokensSimple(
            amount,
            0,
            tokenIn,
            tokenOut,
            false,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 liquidity) {
        _approveRouter(tokenA, amountA);
        _approveRouter(tokenB, amountB);
        (, , liquidity) = strategyData.router.addLiquidity(
            tokenA,
            tokenB,
            false,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

}
