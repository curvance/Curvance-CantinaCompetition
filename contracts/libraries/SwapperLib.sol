// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IExternalCallDataChecker } from "contracts/interfaces/IExternalCallDataChecker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { CommonLib } from "contracts/libraries/CommonLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";

library SwapperLib {
    /// TYPES ///

    /// @notice Used to execute a swap, which is selling one token for another.
    /// @param inputToken Address of input token to swap from.
    /// @param inputAmount The amount of `inputToken` to swap.
    /// @param outputToken Address of token to swap into.
    /// @param target Address of the swapper, usually an aggregator.
    /// @param call Swap instruction calldata.
    struct Swap {
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        address target;
        bytes call;
    }

    /// @notice Used to execute a Zap, which is a single external action.
    /// @param inputToken Address of input token to Zap from.
    /// @param inputAmount The amount of `inputToken` to Zap.
    /// @param target Address of the Zapper, usually an aggregator.
    /// @param call Zap instruction calldata.
    struct ZapperCall {
        address inputToken;
        uint256 inputAmount;
        address target;
        bytes call;
    }

    /// ERRORS ///

    error SwapperLib__SwapError();
    error SwapperLib__UnknownCalldata();

    /// FUNCTIONS ///

    /// @notice Swaps `swapData.inputToken` into a `swapData.outputToken`.
    /// @param swapData The swap instruction data to execute.
    /// @return The output amount received from swapping.
    function swap(
        ICentralRegistry centralRegistry,
        Swap memory swapData
    ) internal returns (uint256) {
        address callDataChecker = centralRegistry.externalCallDataChecker(
            swapData.target
        );

        // Validate we know how to verify this calldata.
        if (callDataChecker == address(0)) {
            revert SwapperLib__UnknownCalldata();
        }

        // Verify calldata integrity.
        IExternalCallDataChecker(callDataChecker).checkCallData(
            swapData,
            address(this)
        );

        // Approve `swapData.inputToken` to target contract, if necessary.
        _approveTokenIfNeeded(
            swapData.inputToken,
            swapData.target,
            swapData.inputAmount
        );

        // Cache output token from struct for easier querying.
        address outputToken = swapData.outputToken;
        uint256 balance = CommonLib.getTokenBalance(outputToken);

        uint256 value = CommonLib.isETH(swapData.inputToken)
            ? swapData.inputAmount
            : 0;

        // Execute the swap.
        (bool success, bytes memory auxData) = swapData.target.call{
            value: value
        }(swapData.call);

        propagateError(success, auxData, "SwapperLib: swap");

        // Revert if the swap failed.
        if (!success) {
            revert SwapperLib__SwapError();
        }

        // Remove any excess approval.
        _removeApprovalIfNeeded(swapData.inputToken, swapData.target);

        return CommonLib.getTokenBalance(outputToken) - balance;
    }

    /// @notice Zaps an input token into something.
    /// @dev Calls the `zap` function in a specified contract (the zapper).
    ///      1. Approves the zapper to transfer the required amount
    ///         of the input token.
    ///      2. Calls the zapper and checks if the operation was successful.
    ///         If the call failed, it reverts with an error message.
    /// @param zapperCall A `ZapperCall` struct containing the zapper contract
    ///                   address, the calldata for the `zap` function,
    ///                   the input token address and the input amount.
    function zap(ZapperCall memory zapperCall) internal {
        // Approve `zapperCall.inputToken` to target contract, if necessary.
        _approveTokenIfNeeded(
            zapperCall.inputToken,
            zapperCall.target,
            zapperCall.inputAmount
        );

        // Check whether we need to attach gas token or not.
        uint256 value = 0;
        if (CommonLib.isETH(zapperCall.inputToken)) {
            value = zapperCall.inputAmount;
        }

        // Execute the zap.
        (bool success, bytes memory auxData) = zapperCall.target.call{
            value: value
        }(zapperCall.call);

        // Remove any excess approval.
        _removeApprovalIfNeeded(zapperCall.inputToken, zapperCall.target);

        SwapperLib.propagateError(success, auxData, "SwapperLib: zapper");
    }

    /// @notice Approves `token` spending allowance, if needed.
    /// @param token The token address to approve.
    /// @param spender The spender address.
    /// @param amount The approval amount.
    function _approveTokenIfNeeded(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (!CommonLib.isETH(token)) {
            SafeTransferLib.safeApprove(token, spender, amount);
        }
    }

    /// @notice Removes `token` spending allowance, if needed.
    /// @param token The token address to remove approval.
    /// @param spender The spender address.
    function _removeApprovalIfNeeded(
        address token, 
        address spender
    ) internal {
        if (!CommonLib.isETH(token)) {
            if (IERC20(token).allowance(address(this), spender) > 0) {
                SafeTransferLib.safeApprove(token, spender, 0);
            }
        }
    }

    /// @dev Propagates an error message.
    /// @param success If transaction was successful.
    /// @param data The transaction result data.
    /// @param errorMessage The custom error message.
    function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) internal pure {
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }
}
