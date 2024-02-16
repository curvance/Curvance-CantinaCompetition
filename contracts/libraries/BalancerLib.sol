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
    error BalancerLib__InvalidPoolInvariantError();

    /// FUNCTIONS ///

    /// @notice Enter a balancer position.
    /// @param balancerVault The Balancer vault address.
    /// @param balancerPoolId The BPT pool ID.
    /// @param lpToken The BPT address.
    /// @param tokens The underlying token addresses of the BPT.
    /// @param lpMinOutAmount The minimum output amount acceptable.
    /// @return lpOutAmount The output amount of BPT received.
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
        bool containsEth;

        // Approve tokens to deposit into BPT.
        for (uint256 i; i < numTokens; ++i) {
            balances[i] = CommonLib.getTokenBalance(tokens[i]);
            SwapperLib._approveTokenIfNeeded(
                tokens[i],
                balancerVault,
                balances[i]
            );

            if (CommonLib.isETH(tokens[i])) {
                // If eth is somehow contained in a pool twice, 
                // something is wrong and we need to halt execution.
                if (containsEth) {
                    revert BalancerLib__InvalidPoolInvariantError();
                }

                value = balances[i];
                containsEth = true;
            }
        }

        // Enter BPT position.
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
                false // Do not use internal balances.
            )
        );

        lpOutAmount = IERC20(lpToken).balanceOf(address(this));
        // Validate we got an acceptable amount of BPTs.
        if (lpOutAmount < lpMinOutAmount) {
            revert BalancerLib__ReceivedAmountIsLessThanMinimum(
                lpOutAmount,
                lpMinOutAmount
            );
        }
    }

    /// @dev Exit a balancer position.
    /// @param balancerVault The Balancer vault address.
    /// @param balancerPoolId The BPT pool ID.
    /// @param lpToken The BPT address.
    /// @param tokens The underlying token addresses of the BPT.
    /// @param lpAmount The BPT amount to exit.
    /// @param singleAssetWithdraw Whether BPT should be unwrapped to a single
    ///                            token or not. 
    ///                            false = all tokens.
    ///                            true = single token.
    /// @param singleAssetIndex Used if `singleAssetWithdraw` = true,
    ///                         indicates the coin index inside the Balancer
    ///                         BPT to withdraw as.
    function exitBalancer(
        address balancerVault,
        bytes32 balancerPoolId,
        address lpToken,
        address[] calldata tokens,
        uint256 lpAmount,
        bool singleAssetWithdraw,
        uint256 singleAssetIndex
    ) internal {
        // Approve BPT.
        SwapperLib._approveTokenIfNeeded(lpToken, balancerVault, lpAmount);

        uint256 numTokens = tokens.length;
        uint256[] memory balances = new uint256[](numTokens);

        // Exit BPT position.
        if (!singleAssetWithdraw) {
            return IBalancerVault(balancerVault).exitPool(
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
                    false // Do not use internal balances.
                )
            );
        }

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
                false // Do not use internal balances.
            )
        );
    }
}
