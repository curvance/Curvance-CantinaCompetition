// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeTransferLib } from "./SafeTransferLib.sol";
import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IPriceRouter } from "../interfaces/IPriceRouter.sol";

library SwapperLib {
    /// STRUCTS ///
    struct Swap {
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        address target;
        bytes call;
    }

    struct ZapperCall {
        address inputToken;
        uint256 inputAmount;
        address target;
        bytes call;
    }

    /// CONSTANTS ///
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;

    /// @notice Checks if the slippage is within an acceptable range.
    /// @dev Calculates whether the zap slippage for the given input
    ///      falls within the accepted range.
    ///      If not, the function reverts with a message.
    /// @param usdInput The USD amount input for the transaction.
    /// @param usdOutput The USD amount output from the transaction.
    /// @param slippage The slippage percentage for the transaction.
    function checkSlippage(
        uint256 usdInput,
        uint256 usdOutput,
        uint256 slippage
    ) internal pure {
        require(
            usdOutput >=
                (usdInput * (SLIPPAGE_DENOMINATOR - slippage)) / slippage &&
                usdOutput <=
                (usdInput * (SLIPPAGE_DENOMINATOR + slippage)) / slippage,
            "SwapperLib: exceed slippage"
        );
    }

    /// @dev Swap input token
    /// @param swapData The swap data
    /// @param priceRouter The price router address
    /// @param slippage Slippage settings
    function swap(
        Swap memory swapData,
        address priceRouter,
        uint256 slippage
    ) internal {
        (uint256 price, uint256 errorCode) = IPriceRouter(priceRouter)
            .getPrice(swapData.inputToken, true, true);
        require(errorCode < 2, "SwapperLib: input token price bad source");
        uint256 usdInput = (price * swapData.inputAmount) /
            (10 ** ERC20(swapData.inputToken).decimals());

        approveTokenIfNeeded(
            swapData.inputToken,
            swapData.target,
            swapData.inputAmount
        );

        uint256 outputAmountBefore = IERC20(swapData.outputToken).balanceOf(
            address(this)
        );

        (bool success, bytes memory retData) = swapData.target.call(
            swapData.call
        );

        propagateError(success, retData, "SwapperLib: swap");

        require(success == true, "SwapperLib: swap error");

        uint256 outputAmount = IERC20(swapData.outputToken).balanceOf(
            address(this)
        ) - outputAmountBefore;

        (price, errorCode) = IPriceRouter(priceRouter).getPrice(
            swapData.outputToken,
            true,
            true
        );
        require(errorCode < 2, "SwapperLib: OT price bad source");
        uint256 usdOutput = (price * outputAmount) /
            (10 ** ERC20(swapData.outputToken).decimals());

        checkSlippage(usdInput, usdOutput, slippage);
    }

    /// @notice Zaps an input token into an output token.
    /// @dev Calls the `zap` function in a specified contract (the zapper).
    ///      First, it approves the zapper to transfer
    ///         the required amount of the input token.
    ///      Then, it calls the zapper and checks
    ///         if the operation was successful.
    ///      If the call failed, it reverts with an error message.
    /// @param zapperCall A `ZapperCall` struct containing
    ///                         the zapper contract address,
    ///                   the calldata for the `zap` function,
    ///                         the input token address and the input amount.
    function zap(ZapperCall memory zapperCall) internal {
        SwapperLib.approveTokenIfNeeded(
            zapperCall.inputToken,
            zapperCall.target,
            zapperCall.inputAmount
        );
        (bool success, bytes memory retData) = zapperCall.target.call(
            zapperCall.call
        );
        SwapperLib.propagateError(success, retData, "SwapperLib: zapper");
    }

    /// @dev Approve token if needed
    /// @param token The token address
    /// @param spender The spender address
    /// @param amount The approve amount
    function approveTokenIfNeeded(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            SafeTransferLib.safeApprove(token, spender, amount);
        }
    }

    /// @dev Propagate error message
    /// @param success If transaction is successful
    /// @param data The transaction result data
    /// @param errorMessage The custom error message
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
