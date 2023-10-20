// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonLib, IERC20 } from "contracts/market/zapper/protocols/CommonLib.sol";
import { Math } from "contracts/libraries/Math.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

library VelodromeLib {
    /// ERRORS ///

    error VelodromeLib__ReceivedAmountIsLessThanMinimum(
        uint256 amount,
        uint256 minimum
    );
    
    /// CONSTANTS ///

    uint256 public constant VELODROME_ADD_LIQUIDITY_SLIPPAGE = 100; // 1%
    
    /// FUNCTIONS ///

    /// @dev Enter Velodrome
    /// @param router The velodrome router address
    /// @param factory The velodrome factory address
    /// @param lpToken The LP token address
    /// @param lpMinOutAmount The minimum output amount
    function enterVelodrome(
        address router,
        address factory,
        address lpToken,
        uint256 lpMinOutAmount
    ) internal returns (uint256 lpOutAmount) {
        address token0 = IVeloPair(lpToken).token0();
        address token1 = IVeloPair(lpToken).token1();
        bool stable = IVeloPool(lpToken).stable();

        uint256 amount0;
        uint256 amount1;

        amount0 = CommonLib.getTokenBalance(token0);
        if (amount0 > 0) {
            (uint256 r0, uint256 r1, ) = IVeloPair(lpToken).getReserves();
            uint256 swapAmount = _optimalDeposit(
                factory,
                lpToken,
                amount0,
                r0,
                r1,
                10 ** ERC20(token0).decimals(),
                10 ** ERC20(token1).decimals(),
                stable
            );

            amount1 = _swapExactTokensForTokens(
                router,
                lpToken,
                token0,
                token1,
                swapAmount,
                stable
            );
            amount0 -= swapAmount;

            uint256 newLpOutAmount = _addLiquidity(
                router,
                token0,
                token1,
                stable,
                amount0,
                amount1,
                VELODROME_ADD_LIQUIDITY_SLIPPAGE
            );

            lpOutAmount += newLpOutAmount;
        }

        amount1 = CommonLib.getTokenBalance(token1);
        if (amount1 > 0) {
            (uint256 r0, uint256 r1, ) = IVeloPair(lpToken).getReserves();
            uint256 swapAmount = _optimalDeposit(
                factory,
                lpToken,
                amount1,
                r1,
                r0,
                10 ** ERC20(token1).decimals(),
                10 ** ERC20(token0).decimals(),
                stable
            );

            amount0 = _swapExactTokensForTokens(
                router,
                lpToken,
                token1,
                token0,
                swapAmount,
                stable
            );
            amount1 -= swapAmount;

            uint256 newLpOutAmount = _addLiquidity(
                router,
                token0,
                token1,
                stable,
                amount0,
                amount1,
                VELODROME_ADD_LIQUIDITY_SLIPPAGE
            );

            lpOutAmount += newLpOutAmount;
        }

        if (lpOutAmount < lpMinOutAmount) {
            revert VelodromeLib__ReceivedAmountIsLessThanMinimum(
                lpOutAmount,
                lpMinOutAmount
            );
        }
    }

    /// @dev Exit velodrome
    /// @param router The velodrome router address
    /// @param lpToken The LP token address
    /// @param lpAmount The LP amount to exit
    function exitVelodrome(
        address router,
        address lpToken,
        uint256 lpAmount
    ) internal {
        address token0 = IVeloPair(lpToken).token0();
        address token1 = IVeloPair(lpToken).token1();
        bool stable = IVeloPool(lpToken).stable();

        SwapperLib.approveTokenIfNeeded(lpToken, router, lpAmount);
        IVeloRouter(router).removeLiquidity(
            token0,
            token1,
            stable,
            lpAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /// @notice Adds `token0` and `token1` into a velodrome LP
    /// @param router The velodrome router address
    /// @param token0 The first token of the pair
    /// @param token1 The second token of the pair
    /// @param amount0 The amount of the `token0`
    /// @param amount1 The amount of the `token1`
    /// @param slippage The slippage percent, 10000 for 100%
    /// @return liquidity The amount of LP tokens received
    function _addLiquidity(
        address router,
        address token0,
        address token1,
        bool stable,
        uint256 amount0,
        uint256 amount1,
        uint256 slippage
    ) internal returns (uint256 liquidity) {
        SwapperLib.approveTokenIfNeeded(token0, router, amount0);
        SwapperLib.approveTokenIfNeeded(token1, router, amount1);
        (, , liquidity) = IVeloRouter(router).addLiquidity(
            token0,
            token1,
            stable,
            amount0,
            amount1,
            amount0 - (amount0 * slippage) / 10000,
            amount1 - (amount1 * slippage) / 10000,
            address(this),
            block.timestamp
        );
    }

    /// @notice Calculates the optimal amount of TokenA to swap to TokenB
    ///         for a perfect LP deposit for a stable pair
    /// @param amountA The amount of `token0` this vault has currently
    /// @param reserveA The amount of `token0` the LP has in reserve
    /// @param reserveB The amount of `token1` the LP has in reserve
    /// @param decimalsA The decimals of `token0`
    /// @param decimalsB The decimals of `token1`
    /// @return The optimal amount of TokenA to swap
    function _optimalDeposit(
        address factory,
        address lpToken,
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB,
        uint256 decimalsA,
        uint256 decimalsB,
        bool stable
    ) internal view returns (uint256) {
        if (stable) {
            uint256 num;
            uint256 den;

            uint256 a = (amountA * 1e18) / decimalsA;
            uint256 x = (reserveA * 1e18) / decimalsA;
            uint256 y = (reserveB * 1e18) / decimalsB;
            uint256 x2 = (x * x) / 1e18;
            uint256 y2 = (y * y) / 1e18;
            uint256 p = (y * (((x2 * 3 + y2) * 1e18) / (y2 * 3 + x2))) / x;
            num = a * y;
            den = ((a + x) * p) / 1e18 + y;

            return ((num / den) * decimalsA) / 1e18;
        } else {
            uint256 swapFee = IVeloPairFactory(factory).getFee(lpToken, false);
            uint256 swapFeeFactor = 10000 - swapFee;
            uint256 a = (10000 + swapFeeFactor) * reserveA;
            uint256 b = amountA * 10000 * reserveA * 4 * swapFeeFactor;
            uint256 c = Math.sqrt(a * a + b);
            uint256 d = swapFeeFactor * 2;
            return (c - a) / d;
        }
    }

    /// @notice Swaps an exact amount of `tokenIn` for `tokenOut`
    /// @param tokenIn The token to be swapped from
    /// @param tokenOut The token to be swapped into
    /// @param amount The amount of `tokenIn` to be swapped
    function _swapExactTokensForTokens(
        address router,
        address lpToken,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool stable
    ) internal returns (uint256) {
        SwapperLib.approveTokenIfNeeded(tokenIn, router, amount);

        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = tokenIn;
        routes[0].to = tokenOut;
        routes[0].stable = stable;
        routes[0].factory = IVeloPool(lpToken).factory();

        uint256[] memory amountsOut = IVeloRouter(router)
            .swapExactTokensForTokens(
                amount,
                0,
                routes,
                address(this),
                block.timestamp
            );

        return amountsOut[amountsOut.length - 1];
    }
}
