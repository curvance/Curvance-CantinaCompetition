// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonLib, IERC20 } from "contracts/market/zapper/protocols/CommonLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { ICurveSwap } from "contracts/interfaces/external/curve/ICurve.sol";

library CurveLib {
    
    /// @dev Enter Curve
    /// @param lpMinter The minter address of Curve LP
    /// @param lpToken The Curve LP token address
    /// @param tokens The underlying coin addresses of Curve LP
    /// @param lpMinOutAmount The minimum output amount
    function enterCurve(
        address lpMinter,
        address lpToken,
        address[] calldata tokens,
        uint256 lpMinOutAmount
    ) internal returns (uint256 lpOutAmount) {
        bool hasETH;

        uint256 numTokens = tokens.length;

        uint256[] memory balances = new uint256[](numTokens);
        // approve tokens
        for (uint256 i; i < numTokens; ++i) {
            balances[i] = CommonLib.getTokenBalance(tokens[i]);
            SwapperLib.approveTokenIfNeeded(tokens[i], lpMinter, balances[i]);
            if (CommonLib.isETH(tokens[i])) {
                hasETH = true;
            }
        }

        // enter curve lp minter
        if (numTokens == 4) {
            uint256[4] memory amounts;
            amounts[0] = balances[0];
            amounts[1] = balances[1];
            amounts[2] = balances[2];
            amounts[3] = balances[3];
            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{
                    value: CommonLib.getETHBalance()
                }(amounts, 0);
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        } else if (numTokens == 3) {
            uint256[3] memory amounts;
            amounts[0] = balances[0];
            amounts[1] = balances[1];
            amounts[2] = balances[2];
            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{
                    value: CommonLib.getETHBalance()
                }(amounts, 0);
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        } else {
            uint256[2] memory amounts;
            amounts[0] = balances[0];
            amounts[1] = balances[1];

            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{
                    value: CommonLib.getETHBalance()
                }(amounts, 0);
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        }

        // check min out amount
        lpOutAmount = IERC20(lpToken).balanceOf(address(this));
        require(
            lpOutAmount >= lpMinOutAmount,
            "Received less than lpMinOutAmount"
        );
    }

    /// @dev Exit curvance
    /// @param lpMinter The minter address of Curve LP
    /// @param lpToken The Curve LP token address
    /// @param tokens The underlying coin addresses of Curve LP
    /// @param lpAmount The LP amount to exit
    function exitCurve(
        address lpMinter,
        address lpToken,
        address[] calldata tokens,
        uint256 lpAmount
    ) internal {
        // approve lp token
        SwapperLib.approveTokenIfNeeded(lpToken, lpMinter, lpAmount);

        uint256 numTokens = tokens.length;
        // enter curve lp minter
        if (numTokens == 4) {
            uint256[4] memory amounts;
            ICurveSwap(lpMinter).remove_liquidity(lpAmount, amounts);
        } else if (numTokens == 3) {
            uint256[3] memory amounts;
            ICurveSwap(lpMinter).remove_liquidity(lpAmount, amounts);
        } else {
            uint256[2] memory amounts;
            ICurveSwap(lpMinter).remove_liquidity(lpAmount, amounts);
        }
    }
}
