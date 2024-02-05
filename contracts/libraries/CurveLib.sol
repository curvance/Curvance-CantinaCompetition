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
    error CurveLib__InvalidPoolType();

    /// FUNCTIONS ///

    /// @notice Enter a Curve lp token position.
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param lpToken The Curve lp token address.
    /// @param tokens The underlying coins of the Curve lp token.
    /// @param lpMinOutAmount The minimum output amount acceptable.
    /// @return lpOutAmount The output amount of Curve lp token received.
    function enterCurve(
        address lpMinter,
        address lpToken,
        address[] calldata tokens,
        uint256 lpMinOutAmount
    ) internal returns (uint256 lpOutAmount) {
        uint256 numTokens = tokens.length;
        // We check token number here as Curvance aims to only support
        // up to 4Pool assets, so we have no need for 5Pool+ routing.
        if (numTokens > 4 || numTokens < 2) {
            revert CurveLib__InvalidPoolType();
        }

        uint256[] memory balances = new uint256[](numTokens);
        uint256 value;
        bool containsEth;
        
        // Approve tokens to deposit into Curve lp.
        for (uint256 i; i < numTokens; ++i) {
            balances[i] = CommonLib.getTokenBalance(tokens[i]);
            SwapperLib._approveTokenIfNeeded(
                tokens[i], 
                lpMinter, 
                balances[i]
            );

            if (CommonLib.isETH(tokens[i])) {
                // If eth is somehow contained in a pool twice, 
                // something is wrong and we need to halt execution.
                if (containsEth) {
                    revert CurveLib__InvalidPoolInvariantError();
                }

                value = balances[i];
                containsEth = true;
            }
        }

        // Enter curve lp token position.
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

        lpOutAmount = IERC20(lpToken).balanceOf(address(this));
        // Validate we got an acceptable amount of lp tokens.
        if (lpOutAmount < lpMinOutAmount) {
            revert CurveLib__ReceivedAmountIsLessThanMinimum(
                lpOutAmount,
                lpMinOutAmount
            );
        }
    }

    /// @notice Exit a Curve lp token position.
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param lpToken The Curve lp token address.
    /// @param tokens The underlying coins of the Curve lp token.
    /// @param lpAmount The Curve lp token amount to exit.
    /// @param singleAssetWithdraw Whether lp should be unwrapped to a single
    ///                            token or not. 
    ///                            0 = all tokens.
    ///                            1 = single token; uint256 interface.
    ///                            2+ = single token; int128 interface.
    /// @param singleAssetIndex Used if `singleAssetWithdraw` != 0, indicates
    ///                         the coin index inside the Curve lp
    ///                         to withdraw as.
    function exitCurve(
        address lpMinter,
        address lpToken,
        address[] calldata tokens,
        uint256 lpAmount,
        uint256 singleAssetWithdraw,
        uint256 singleAssetIndex
    ) internal {
        // Approve Curve lp token.
        SwapperLib._approveTokenIfNeeded(lpToken, lpMinter, lpAmount);

        uint256 numTokens = tokens.length;
        if (singleAssetWithdraw == 0) {
            // We need to check numTokens in here specifically as single
            // coin liquidity withdrawal will work for any number of
            // underlying tokens.
            if (numTokens > 4 || numTokens < 2) {
                revert CurveLib__InvalidPoolType();
            }

            if (numTokens == 4) {
                uint256[4] memory amounts;
                return ICurveSwap(lpMinter).remove_liquidity(
                    lpAmount, 
                    amounts
                );
            }

            if (numTokens == 3) {
                uint256[3] memory amounts;
                return ICurveSwap(lpMinter).remove_liquidity(
                    lpAmount, 
                    amounts
                );
            }

            uint256[2] memory amounts;
            return ICurveSwap(lpMinter).remove_liquidity(lpAmount, amounts);
        }

        // Withdraw as 1 token with uint256 interface.
        if (singleAssetWithdraw == 1) {
            return ICurveSwap(lpMinter).remove_liquidity_one_coin(
                lpAmount,
                singleAssetIndex,
                0
            );
        }

        // Withdraw as 1 token with int128 interface.
        ICurveSwap(lpMinter).remove_liquidity_one_coin(
            lpAmount,
            int128(uint128(singleAssetIndex)),
            0
        );
    }
}
