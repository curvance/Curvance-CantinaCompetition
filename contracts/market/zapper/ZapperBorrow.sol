// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DToken } from "contracts/market/collateral/DToken.sol";
import { FeeTokenBridgingHub } from "contracts/architecture/FeeTokenBridgingHub.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ZapperBorrow is FeeTokenBridgingHub {
    /// ERRORS ///

    error ZapperBorrow__InvalidSwapper(address invalidSwapper);
    error ZapperBorrow__InvalidSwapData();

    /// CONSTRUCTOR ///

    receive() external payable {}

    constructor(
        ICentralRegistry centralRegistry_
    ) FeeTokenBridgingHub(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @param dstChainId Chain ID of the target blockchain.
    function borrowAndBridge(
        address dToken,
        uint256 borrowAmount,
        SwapperLib.Swap memory swapData,
        uint256 dstChainId
    ) external payable {
        uint256 balance = IERC20(feeToken).balanceOf(address(this));

        // borrow
        DToken(dToken).borrowFor(msg.sender, address(this), borrowAmount);

        address underlying = DToken(dToken).underlying();

        // swap
        if (underlying != feeToken) {
            if (
                swapData.target == address(0) ||
                swapData.inputToken != underlying ||
                swapData.outputToken != feeToken ||
                swapData.inputAmount != borrowAmount
            ) {
                revert ZapperBorrow__InvalidSwapData();
            }

            if (!centralRegistry.isSwapper(swapData.target)) {
                revert ZapperBorrow__InvalidSwapper(swapData.target);
            }
            unchecked {
                SwapperLib.swap(swapData);
            }
        } else {
            if (swapData.target != address(0)) {
                revert ZapperBorrow__InvalidSwapData();
            }
        }

        _sendFeeToken(
            centralRegistry.wormholeChainId(dstChainId),
            msg.sender,
            IERC20(feeToken).balanceOf(address(this)) - balance
        );
    }
}
