// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonLib, IERC20 } from "contracts/market/zapper/protocols/CommonLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";

library BalancerLib {
    
    /// @dev Enter Balancer
    /// @param balancerVault The balancer vault address
    /// @param balancerPoolId The balancer pool ID
    /// @param lpToken The Curve LP token address
    /// @param tokens The underlying coin addresses of Curve LP
    /// @param lpMinOutAmount The minimum output amount
    function enterBalancer(
        address balancerVault,
        bytes32 balancerPoolId,
        address lpToken,
        address[] memory tokens,
        uint256 lpMinOutAmount
    ) internal returns (uint256 lpOutAmount) {
        uint256 numTokens = tokens.length;

        uint256[] memory balances = new uint256[](numTokens);
        // approve tokens
        for (uint256 i; i < numTokens; ++i) {
            balances[i] = CommonLib.getTokenBalance(tokens[i]);
            SwapperLib.approveTokenIfNeeded(
                tokens[i],
                balancerVault,
                balances[i]
            );
        }

        IBalancerVault(balancerVault).joinPool(
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
        require(
            lpOutAmount >= lpMinOutAmount,
            "Received less than lpMinOutAmount"
        );
    }

    /// @dev Exit balancer
    /// @param balancerVault The balancer vault address
    /// @param balancerPoolId The balancer pool ID
    /// @param lpToken The Curve LP token address
    /// @param tokens The underlying coin addresses of Curve LP
    /// @param lpAmount The LP amount to exit
    function exitBalancer(
        address balancerVault,
        bytes32 balancerPoolId,
        address lpToken,
        address[] memory tokens,
        uint256 lpAmount
    ) internal {
        // approve lp token
        SwapperLib.approveTokenIfNeeded(lpToken, balancerVault, lpAmount);

        uint256 numTokens = tokens.length;
        uint256[] memory balances = new uint256[](numTokens);
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
    }
}
