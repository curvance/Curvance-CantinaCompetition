// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IWormhole } from "contracts/interfaces/external/wormhole/IWormhole.sol";
import { IWormholeRelayer } from "contracts/interfaces/external/wormhole/IWormholeRelayer.sol";
import { ITokenMessenger } from "contracts/interfaces/external/wormhole/ITokenMessenger.sol";
import { ITokenBridge } from "contracts/interfaces/external/wormhole/ITokenBridge.sol";

contract FeeTokenBridgingHub is ReentrancyGuard {
    /// TYPES ///

    enum Transfer {
        TOKEN_BRIDGE,
        CCTP
    }

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
    /// @param dstChainId Destination chain ID.
    /// @param transferToken Whether deliver token or not.
    /// @return Total gas cost.
    function quoteWormholeFee(
        uint256 dstChainId,
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
        uint256 dstChainId,
        address to,
        uint256 amount
    ) internal {
        uint256 wormholeFee = _quoteWormholeFee(dstChainId, true);

        // Validate that we have sufficient fees to send crosschain
        if (address(this).balance < wormholeFee) {
            revert FeeTokenBridgingHub__InsufficientGasToken();
        }

        ITokenMessenger circleTokenMessenger = centralRegistry
            .circleTokenMessenger();

        if (
            address(circleTokenMessenger) != address(0) &&
            circleTokenMessenger.remoteTokenMessengers(
                centralRegistry.cctpDomain(dstChainId)
            ) !=
            bytes32(0)
        ) {
            _transferFeeTokenViaCCTP(
                circleTokenMessenger,
                dstChainId,
                to,
                amount,
                wormholeFee
            );
        } else {
            _transferTokenViaWormhole(
                feeToken,
                dstChainId,
                to,
                amount,
                wormholeFee
            );
        }
    }

    function _transferFeeTokenViaCCTP(
        ITokenMessenger circleTokenMessenger,
        uint256 dstChainId,
        address to,
        uint256 amount,
        uint256 wormholeFee
    ) internal {
        IWormholeRelayer wormholeRelayer = centralRegistry.wormholeRelayer();
        uint16 wormholeChainId = centralRegistry.wormholeChainId(dstChainId);

        SwapperLib._approveTokenIfNeeded(
            feeToken,
            address(circleTokenMessenger),
            amount
        );

        uint64 nonce = circleTokenMessenger.depositForBurnWithCaller(
            amount,
            centralRegistry.cctpDomain(dstChainId),
            bytes32(uint256(uint160(to))),
            feeToken,
            bytes32(uint256(uint160(to)))
        );

        IWormholeRelayer.MessageKey[]
            memory messageKeys = new IWormholeRelayer.MessageKey[](1);
        messageKeys[0] = IWormholeRelayer.MessageKey(
            2, // CCTP_KEY_TYPE
            abi.encodePacked(centralRegistry.cctpDomain(block.chainid), nonce)
        );

        address defaultDeliveryProvider = wormholeRelayer
            .getDefaultDeliveryProvider();

        wormholeRelayer.sendToEvm{ value: wormholeFee }(
            wormholeChainId,
            to,
            abi.encode(uint8(1), feeToken, amount),
            0,
            0,
            _GAS_LIMIT,
            wormholeChainId,
            address(0),
            defaultDeliveryProvider,
            messageKeys,
            15
        );
    }

    function _transferTokenViaWormhole(
        address token,
        uint256 dstChainId,
        address to,
        uint256 amount,
        uint256 wormholeFee
    ) internal returns (uint64) {
        ITokenBridge tokenBridge = centralRegistry.tokenBridge();
        uint16 wormholeChainId = centralRegistry.wormholeChainId(dstChainId);
        IWormhole wormholeCore = centralRegistry.wormholeCore();
        uint256 messageFee = wormholeCore.messageFee();

        SwapperLib._approveTokenIfNeeded(token, address(tokenBridge), amount);

        bytes memory payload = abi.encode(uint8(1), feeToken, amount);

        uint64 sequence = tokenBridge.transferTokensWithPayload{
            value: messageFee
        }(
            token,
            amount,
            wormholeChainId,
            bytes32(uint256(uint160(to))),
            0,
            payload
        );

        IWormholeRelayer.VaaKey[]
            memory vaaKeys = new IWormholeRelayer.VaaKey[](1);
        vaaKeys[0] = IWormholeRelayer.VaaKey({
            emitterAddress: bytes32(uint256(uint160(address(tokenBridge)))),
            chainId: wormholeCore.chainId(),
            sequence: sequence
        });

        return
            centralRegistry.wormholeRelayer().sendVaasToEvm{
                value: wormholeFee - messageFee
            }(wormholeChainId, to, payload, 0, _GAS_LIMIT, vaaKeys);
    }

    /// @notice Quotes gas cost and token fee for executing crosschain
    ///         wormhole deposit and messaging.
    /// @param dstChainId Destination chain ID.
    /// @param transferToken Whether deliver token or not.
    /// @return nativeFee Total gas cost.
    function _quoteWormholeFee(
        uint256 dstChainId,
        bool transferToken
    ) internal view returns (uint256 nativeFee) {
        IWormholeRelayer wormholeRelayer = centralRegistry.wormholeRelayer();
        IWormhole wormholeCore = centralRegistry.wormholeCore();

        (nativeFee, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            centralRegistry.wormholeChainId(dstChainId),
            0,
            _GAS_LIMIT
        );

        if (transferToken) {
            // Add cost of publishing the 'sending token' wormhole message.
            nativeFee += wormholeCore.messageFee();
        }
    }
}
