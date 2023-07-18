// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { SafeTransferLib } from "./SafeTransferLib.sol";
import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IPriceRouter } from "../interfaces/IPriceRouter.sol";

library SwapperLib {
    struct Swap {
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        address target;
        bytes call;
    }

    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;

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
            "exceed slippage"
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
        require(errorCode != 2, "input token price bad source");
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

        propagateError(success, retData, "swap");

        require(success == true, "swap returned an error");

        uint256 outputAmount = IERC20(swapData.outputToken).balanceOf(
            address(this)
        ) - outputAmountBefore;

        (price, errorCode) = IPriceRouter(priceRouter).getPrice(
            swapData.outputToken,
            true,
            true
        );
        require(errorCode != 2, "output token price bad source");
        uint256 usdOutput = (price * outputAmount) /
            (10 ** ERC20(swapData.outputToken).decimals());

        checkSlippage(usdInput, usdOutput, slippage);
    }

    /// @dev Approve token if needed
    /// @param _token The token address
    /// @param _spender The spender address
    /// @param _amount The approve amount
    function approveTokenIfNeeded(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _spender) < _amount) {
            SafeTransferLib.safeApprove(_token, _spender, _amount);
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
