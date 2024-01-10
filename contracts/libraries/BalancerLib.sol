// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { CommonLib, IERC20 } from "contracts/libraries/CommonLib.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";

library BalancerLib {
    /// ERRORS ///

    error BalancerLib__ReceivedAmountIsLessThanMinimum(
        uint256 amount,
        uint256 minimum
    );

    /// FUNCTIONS ///

    /// @notice Enter a balancer position.
    /// @param balancerVault The balancer vault address.
    /// @param balancerPoolId The balancer pool ID.
    /// @param lpToken The Curve LP token address.
    /// @param tokens The underlying coin addresses of Curve LP.
    /// @param lpMinOutAmount The minimum output amount.
    function enterBalancer(
        address balancerVault,
        bytes32 balancerPoolId,
        address lpToken,
        address[] calldata tokens,
        uint256 lpMinOutAmount
    ) internal returns (uint256 lpOutAmount) {
        uint256 numTokens = tokens.length;
        uint256[] memory balances = new uint256[](numTokens);
        uint256 value;

        // approve tokens
        for (uint256 i; i < numTokens; ) {
            balances[i] = CommonLib.getTokenBalance(tokens[i]);
            SwapperLib._approveTokenIfNeeded(
                tokens[i],
                balancerVault,
                balances[i]
            );

            if (CommonLib.isETH(tokens[i])) {
                value = balances[i];
            }

            unchecked {
                ++i;
            }
        }

        IBalancerVault(balancerVault).joinPool{ value: value }(
            balancerPoolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                tokens,
                balances,
                abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    balances,
                    1
                ),
                false // do not use internal balances
            )
        );

        // check min out amount
        lpOutAmount = IERC20(lpToken).balanceOf(address(this));
        if (lpOutAmount < lpMinOutAmount) {
            revert BalancerLib__ReceivedAmountIsLessThanMinimum(
                lpOutAmount,
                lpMinOutAmount
            );
        }
    }

    /// @dev Exit a balancer position.
    /// @param balancerVault The balancer vault address.
    /// @param balancerPoolId The balancer pool ID.
    /// @param lpToken The Balancer BPT token address.
    /// @param tokens The underlying coin addresses of Balancer BPT.
    /// @param lpAmount The LP amount to exit.
    function exitBalancer(
        address balancerVault,
        bytes32 balancerPoolId,
        address lpToken,
        address[] calldata tokens,
        uint256 lpAmount,
        bool singleAssetWithdraw,
        uint256 singleAssetIndex
    ) internal {
        // approve lp token
        SwapperLib._approveTokenIfNeeded(lpToken, balancerVault, lpAmount);

        uint256 numTokens = tokens.length;
        uint256[] memory balances = new uint256[](numTokens);

        if (!singleAssetWithdraw) {
            IBalancerVault(balancerVault).exitPool(
                balancerPoolId,
                address(this),
                payable(address(this)),
                IBalancerVault.ExitPoolRequest(
                    tokens,
                    balances,
                    abi.encode(
                        IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                        lpAmount
                    ),
                    false // do not use internal balances
                )
            );
        } else {
            IBalancerVault(balancerVault).exitPool(
                balancerPoolId,
                address(this),
                payable(address(this)),
                IBalancerVault.ExitPoolRequest(
                    tokens,
                    balances,
                    abi.encode(
                        IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                        lpAmount,
                        singleAssetIndex
                    ),
                    false // do not use internal balances
                )
            );
        }
    }
}
