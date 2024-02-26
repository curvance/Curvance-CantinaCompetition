// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DToken } from "contracts/market/collateral/DToken.sol";
import { FeeTokenBridgingHub } from "contracts/architecture/FeeTokenBridgingHub.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract BorrowZapper is FeeTokenBridgingHub {
    /// ERRORS ///

    error BorrowZapper__InvalidSwapper(address invalidSwapper);
    error BorrowZapper__InvalidSwapData();

    /// CONSTRUCTOR ///

    receive() external payable {}

    constructor(
        ICentralRegistry centralRegistry_
    ) FeeTokenBridgingHub(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Borrows of behalf of the caller from `dToken` then bridge
    ///         funds to desired destination chain.
    /// @dev Requires that caller delegated borrowing functionality to this
    ///      contract prior.
    /// @param dToken The dToken contract to borrow from.
    /// @param borrowAmount The amount of dToken underlying to borrow.
    /// @param swapData Swap instruction data to route from dToken underlying
    ///                 to `feeToken`.
    /// @param dstChainId Chain ID of the target blockchain.
    function borrowAndBridge(
        address dToken,
        uint256 borrowAmount,
        SwapperLib.Swap memory swapData,
        uint256 dstChainId
    ) external payable nonReentrant {
        uint256 balancePrior = IERC20(feeToken).balanceOf(address(this));

        // Borrow on behalf of caller.
        DToken(dToken).borrowFor(msg.sender, address(this), borrowAmount);

        address underlying = DToken(dToken).underlying();

        // Check if swapping is necessary.
        if (underlying != feeToken) {
            if (
                swapData.target == address(0) ||
                swapData.inputToken != underlying ||
                swapData.outputToken != feeToken ||
                swapData.inputAmount != borrowAmount
            ) {
                revert BorrowZapper__InvalidSwapData();
            }

            // Validate target contract is an approved swapper.
            if (!centralRegistry.isSwapper(swapData.target)) {
                revert BorrowZapper__InvalidSwapper(swapData.target);
            }
            unchecked {
                SwapperLib.swap(centralRegistry, swapData);
            }
        } else {
            if (swapData.target != address(0)) {
                revert BorrowZapper__InvalidSwapData();
            }
        }

        // Bridge the fee token to `dstChainId` via Wormhole.
        _sendFeeToken(
            dstChainId,
            msg.sender,
            IERC20(feeToken).balanceOf(address(this)) - balancePrior
        );
    }
}
