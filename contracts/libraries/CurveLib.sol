// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonLib, IERC20 } from "contracts/libraries/CommonLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { ICurveSwap } from "contracts/interfaces/external/curve/ICurve.sol";

library CurveLib {
    /// ERRORS ///

    error CurveLib__ReceivedAmountIsLessThanMinimum(
        uint256 amount,
        uint256 minimum
    );
    error CurveLib__InvalidPoolInvariantError();

    /// FUNCTIONS ///

    /// @notice Enter a curve position.
    /// @param lpMinter The minter address of Curve LP.
    /// @param lpToken The Curve LP token address.
    /// @param tokens The underlying coin addresses of Curve LP.
    /// @param lpMinOutAmount The minimum output amount.
    function enterCurve(
        address lpMinter,
        address lpToken,
        address[] calldata tokens,
        uint256 lpMinOutAmount
    ) internal returns (uint256 lpOutAmount) {
        uint256 value;
        bool containsEth;

        uint256 numTokens = tokens.length;

        uint256[] memory balances = new uint256[](numTokens);
        // Approve tokens.
        for (uint256 i; i < numTokens; ) {
            balances[i] = CommonLib.getTokenBalance(tokens[i]);
            SwapperLib._approveTokenIfNeeded(tokens[i], lpMinter, balances[i]);

            if (CommonLib.isETH(tokens[i])) {
                // If eth is somehow contained in a pool twice, 
                // something is wrong and we need to halt execution.
                if (containsEth) {
                    revert CurveLib__InvalidPoolInvariantError();
                }

                value = balances[i];
                containsEth = true;
            }

            unchecked {
                ++i;
            }
        }

        // Enter curve lp minter.
        if (numTokens == 4) {
            uint256[4] memory amounts;
            amounts[0] = balances[0];
            amounts[1] = balances[1];
            amounts[2] = balances[2];
            amounts[3] = balances[3];
            ICurveSwap(lpMinter).add_liquidity{ value: value }(amounts, 0);
        } else if (numTokens == 3) {
            uint256[3] memory amounts;
            amounts[0] = balances[0];
            amounts[1] = balances[1];
            amounts[2] = balances[2];
            ICurveSwap(lpMinter).add_liquidity{ value: value }(amounts, 0);
        } else {
            uint256[2] memory amounts;
            amounts[0] = balances[0];
            amounts[1] = balances[1];

            ICurveSwap(lpMinter).add_liquidity{ value: value }(amounts, 0);
        }

        // Check min out amount.
        lpOutAmount = IERC20(lpToken).balanceOf(address(this));
        if (lpOutAmount < lpMinOutAmount) {
            revert CurveLib__ReceivedAmountIsLessThanMinimum(
                lpOutAmount,
                lpMinOutAmount
            );
        }
    }

    /// @notice Exit a curve position.
    /// @param lpMinter The minter address of Curve LP.
    /// @param lpToken The Curve LP token address.
    /// @param tokens The underlying coin addresses of Curve LP.
    /// @param lpAmount The LP amount to exit.
    function exitCurve(
        address lpMinter,
        address lpToken,
        address[] calldata tokens,
        uint256 lpAmount,
        uint256 singleAssetWithdraw,
        uint256 singleAssetIndex
    ) internal {
        // Approve lp token.
        SwapperLib._approveTokenIfNeeded(lpToken, lpMinter, lpAmount);

        uint256 numTokens = tokens.length;
        if (singleAssetWithdraw == 0) {
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
        } else {
            if (singleAssetWithdraw == 1) {
                ICurveSwap(lpMinter).remove_liquidity_one_coin(
                    lpAmount,
                    singleAssetIndex,
                    0
                );
            } else {
                ICurveSwap(lpMinter).remove_liquidity_one_coin(
                    lpAmount,
                    int128(uint128(singleAssetIndex)),
                    0
                );
            }
        }
    }
}
