// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IERC20Metadata } from "contracts/interfaces/IERC20Metadata.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IWormhole } from "contracts/interfaces/external/wormhole/IWormhole.sol";
import { IWormholeRelayer } from "contracts/interfaces/external/wormhole/IWormholeRelayer.sol";
import { ICircleRelayer } from "contracts/interfaces/external/wormhole/ICircleRelayer.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/external/wormhole/ITokenBridgeRelayer.sol";

contract FeeTokenBridgingHub is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Gas limit with which to call `targetAddress` via wormhole.
    uint256 internal constant _GAS_LIMIT = 250_000;

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Address of fee token.
    address public immutable feeToken;

    /// ERRORS ///

    error FeeTokenBridgingHub__InvalidCentralRegistry();
    error FeeTokenBridgingHub__InsufficientGasToken();

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert FeeTokenBridgingHub__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        feeToken = centralRegistry.feeToken();
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Quotes gas cost and token fee for executing crosschain
    ///         wormhole deposit and messaging.
    /// @param dstChainId Wormhole specific destination chain ID.
    /// @param transferToken Whether deliver token or not.
    /// @return Total gas cost.
    function quoteWormholeFee(
        uint16 dstChainId,
        bool transferToken
    ) external view returns (uint256) {
        return _quoteWormholeFee(dstChainId, transferToken);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Sends fee tokens to the receiver on `dstChainId`.
    /// @param dstChainId Wormhole specific destination chain ID.
    /// @param to The address of receiver on `dstChainId`.
    /// @param amount The amount of token to transfer.
    function _sendFeeToken(
        uint16 dstChainId,
        address to,
        uint256 amount
    ) internal {
        uint256 messageFee = _quoteWormholeFee(dstChainId, true);

        // Validate that we have sufficient fees to send crosschain
        if (address(this).balance < messageFee) {
            revert FeeTokenBridgingHub__InsufficientGasToken();
        }

        ICircleRelayer circleRelayer = centralRegistry.circleRelayer();
        ITokenBridgeRelayer tokenBridgeRelayer = centralRegistry
            .tokenBridgeRelayer();

        if (
            address(circleRelayer) != address(0) &&
            circleRelayer.getRegisteredContract(dstChainId) != bytes32(0)
        ) {
            SwapperLib._approveTokenIfNeeded(
                feeToken,
                address(circleRelayer),
                amount
            );

            // Sends funds to feeAccumulator on another chain
            circleRelayer.transferTokensWithRelay{ value: messageFee }(
                IERC20Metadata(feeToken),
                amount,
                0,
                dstChainId,
                bytes32(uint256(uint160(to)))
            );
        } else {
            SwapperLib._approveTokenIfNeeded(
                feeToken,
                address(tokenBridgeRelayer),
                amount
            );

            tokenBridgeRelayer.transferTokensWithRelay{ value: messageFee }(
                feeToken,
                amount,
                0,
                dstChainId,
                bytes32(uint256(uint160(to))),
                0
            );
        }
    }

    /// @notice Quotes gas cost and token fee for executing crosschain
    ///         wormhole deposit and messaging.
    /// @param dstChainId Wormhole specific destination chain ID.
    /// @param transferToken Whether deliver token or not.
    /// @return nativeFee Total gas cost.
    function _quoteWormholeFee(
        uint16 dstChainId,
        bool transferToken
    ) internal view returns (uint256 nativeFee) {
        ICircleRelayer circleRelayer = centralRegistry.circleRelayer();
        IWormholeRelayer wormholeRelayer = centralRegistry.wormholeRelayer();
        IWormhole wormholeCore = centralRegistry.wormholeCore();

        // Cost of delivering token and payload to targetChain.
        if (
            address(circleRelayer) != address(0) &&
            circleRelayer.getRegisteredContract(dstChainId) != bytes32(0)
        ) {
            (nativeFee, ) = wormholeRelayer.quoteEVMDeliveryPrice(
                dstChainId,
                0,
                _GAS_LIMIT
            );
        }

        if (transferToken) {
            // Add cost of publishing the 'sending token' wormhole message.
            nativeFee += wormholeCore.messageFee();
        }
    }
}
