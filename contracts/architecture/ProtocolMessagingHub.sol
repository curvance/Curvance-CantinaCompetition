// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugeController } from "contracts/gauge/GaugeController.sol";

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "contracts/interfaces/IERC20Metadata.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";
import { IFeeAccumulator, EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";
import { IWormholeRelayer } from "contracts/interfaces/wormhole/IWormholeRelayer.sol";
import { ICircleRelayer } from "contracts/interfaces/wormhole/ICircleRelayer.sol";

contract ProtocolMessagingHub is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Gas limit with which to call `targetAddress` via wormhole.
    uint256 internal constant _GAS_LIMIT = 250_000;

    /// @notice CVE contract address.
    ICVE public immutable cve;

    /// @notice Address of fee token.
    address public immutable feeToken;

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Address of Wormhole core contract.
    IWormhole public immutable wormhole;

    /// @notice Address of Wormhole Relayer.
    IWormholeRelayer public immutable wormholeRelayer;

    /// @notice Address of Wormhole Circle Relayer.
    ICircleRelayer public immutable circleRelayer;

    /// ERRORS ///

    error ProtocolMessagingHub__Unauthorized();
    error ProtocolMessagingHub__InvalidCentralRegistry();
    error ProtocolMessagingHub__FeeTokenIsZeroAddress();
    error ProtocolMessagingHub__WormholeRelayerIsZeroAddress();
    error ProtocolMessagingHub__CircleRelayerIsZeroAddress();
    error ProtocolMessagingHub__ChainIsNotSupported();
    error ProtocolMessagingHub__OperatorIsNotAuthorized(
        address to,
        uint256 gethChainId
    );
    error ProtocolMessagingHub__MessagingChainIdIsNotDstChainId(
        uint16 messagingChainId,
        uint256 dstChainId
    );
    error ProtocolMessagingHub__GETHChainIdIsNotSupported(uint256 gethChainId);
    error ProtocolMessagingHub__InsufficientGasToken();
    error ProtocolMessagingHub__InvalidMsgValue();

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address feeToken_,
        address wormholeRelayer_,
        address circleRelayer_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert ProtocolMessagingHub__InvalidCentralRegistry();
        }
        if (feeToken_ == address(0)) {
            revert ProtocolMessagingHub__FeeTokenIsZeroAddress();
        }
        if (wormholeRelayer_ == address(0)) {
            revert ProtocolMessagingHub__WormholeRelayerIsZeroAddress();
        }
        if (circleRelayer_ == address(0)) {
            revert ProtocolMessagingHub__CircleRelayerIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        cve = ICVE(centralRegistry.cve());
        feeToken = feeToken_;
        wormholeRelayer = IWormholeRelayer(wormholeRelayer_);
        circleRelayer = ICircleRelayer(circleRelayer_);
        wormhole = ICircleRelayer(circleRelayer_).wormhole();
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Used when fees are received from other chains.
    ///         When a `send` is performed with this contract as the target,
    ///         this function will be invoked by the WormholeRelayer contract.
    /// NOTE: This function should be restricted such that only
    ///       the Wormhole Relayer contract can call it.
    /// @param payload An arbitrary message which was included in the delivery
    ///                by the requester. This message's signature will already
    ///                have been verified (as long as msg.sender is
    ///                the Wormhole Relayer contract)
    /// @param srcAddress The (wormhole format) address on the sending chain
    ///                   which requested this delivery.
    /// @param srcChainId The wormhole chain ID where delivery was requested.
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory /* additionalMessages */,
        bytes32 srcAddress,
        uint16 srcChainId,
        bytes32 /* deliveryHash */
    ) external payable {
        if (msg.sender != address(wormholeRelayer)) {
            revert ProtocolMessagingHub__Unauthorized();
        }

        uint8 payloadId = abi.decode(payload, (uint8));

        if (payloadId == 1) {
            (, bytes32 token, uint256 amount) = abi.decode(
                payload,
                (uint8, bytes32, uint256)
            );

            if (address(uint160(uint256(token))) == feeToken) {
                address locker = centralRegistry.cveLocker();
                SafeTransferLib.safeTransfer(feeToken, locker, amount);

                IFeeAccumulator(centralRegistry.feeAccumulator())
                    .recordEpochRewards(amount);
            }
        } else if (payloadId == 4) {
            (, address srcCVE, bytes memory emissionData) = abi.decode(
                payload,
                (uint8, address, bytes)
            );

            OmnichainData memory operator = centralRegistry
                .getOmnichainOperators(
                    address(uint160(uint256(srcAddress))),
                    centralRegistry.messagingToGETHChainId(srcChainId)
                );

            // Validate the operator is authorized
            if (operator.isAuthorized < 2) {
                return;
            }

            // If the operator is correct but the source chain Id
            // is invalid, ignore the message
            // Validate the source chainId is correct for the operator
            if (operator.messagingChainId != srcChainId) {
                return;
            }

            // Validate message came directly from CVE on the source chain
            if (operator.cveAddress != srcCVE) {
                return;
            }

            (
                address[] memory gaugePools,
                uint256[] memory emissionTotals,
                address[][] memory tokens,
                uint256[][] memory emissions,
                uint256 chainLockedAmount,
                uint256 messageType
            ) = abi.decode(
                    emissionData,
                    (
                        address[],
                        uint256[],
                        address[][],
                        uint256[][],
                        uint256,
                        uint256
                    )
                );

            // Message Type 1: receive feeAccumulator information of locked
            //                 tokens on a chain for the epoch.
            if (messageType == 1) {
                IFeeAccumulator(centralRegistry.feeAccumulator())
                    .receiveCrossChainLockData(
                        EpochRolloverData({
                            chainId: operator.chainId,
                            value: chainLockedAmount,
                            numChainData: 0,
                            epoch: 0
                        })
                    );
                return;
            }

            // Message Type 2: receive finalized epoch rewards data.
            if (messageType == 2) {
                IFeeAccumulator(centralRegistry.feeAccumulator())
                    .receiveExecutableLockData(chainLockedAmount);
                return;
            }

            // Message Type 3+: update gauge emissions for all gauge
            //                  controllers on this chain.
            {
                // Use scoping for stack too deep logic.
                uint256 numPools = gaugePools.length;
                GaugeController gaugePool;

                for (uint256 i; i < numPools; ) {
                    gaugePool = GaugeController(gaugePools[i]);
                    // Mint epoch gauge emissions to the gauge pool.
                    cve.mintGaugeEmissions(
                        address(gaugePool),
                        emissionTotals[i]
                    );
                    // Set upcoming epoch emissions for voted configuration.
                    gaugePool.setEmissionRates(
                        gaugePool.currentEpoch() + 1,
                        tokens[i],
                        emissions[i]
                    );

                    unchecked {
                        ++i;
                    }
                }
            }
        }
    }

    /// @notice Sends gauge emission information to multiple destination chains
    /// @param dstChainId Destination chain ID where the message data should be
    ///                   sent.
    /// @param toAddress The destination address specified by `dstChainId`.
    /// @param payload The payload data that is sent along with the message.
    /// @dev Calls with this function will have messageType = 3.
    function sendGaugeEmissions(
        uint16 dstChainId,
        address toAddress,
        bytes calldata payload
    ) external {
        _checkPermissions();

        // Validate that we are aiming for a supported chain
        if (
            centralRegistry
                .supportedChainData(
                    centralRegistry.messagingToGETHChainId(dstChainId)
                )
                .isSupported < 2
        ) {
            revert ProtocolMessagingHub__ChainIsNotSupported();
        }

        (uint256 messageFee, ) = _quoteWormholeFee(dstChainId, false);

        wormholeRelayer.sendPayloadToEvm{ value: messageFee }(
            dstChainId,
            toAddress,
            abi.encode(uint8(4), cve, payload), // payload
            0, // no receiver value needed since we're just passing a message
            _GAS_LIMIT
        );
    }

    /// @notice Sends fee tokens to the Messaging Hub on `dstChainId`.
    /// @param dstChainId Wormhole specific destination chain ID .
    /// @param to The address of Messaging Hub on `dstChainId`.
    /// @param amount The amount of token to transfer.
    function sendFees(uint16 dstChainId, address to, uint256 amount) external {
        _checkPermissions();

        {
            // Avoid stack too deep
            uint256 gethChainId = centralRegistry.messagingToGETHChainId(
                dstChainId
            );
            OmnichainData memory operator = centralRegistry
                .getOmnichainOperators(to, gethChainId);

            // Validate that the operator is authorized
            if (operator.isAuthorized < 2) {
                revert ProtocolMessagingHub__OperatorIsNotAuthorized(
                    to,
                    gethChainId
                );
            }

            // Validate that the operator messaging chain matches
            // the destination chain id
            if (operator.messagingChainId != dstChainId) {
                revert ProtocolMessagingHub__MessagingChainIdIsNotDstChainId(
                    operator.messagingChainId,
                    dstChainId
                );
            }

            // Validate that we are aiming for a supported chain
            if (
                centralRegistry.supportedChainData(gethChainId).isSupported < 2
            ) {
                revert ProtocolMessagingHub__GETHChainIdIsNotSupported(
                    gethChainId
                );
            }
        }

        (uint256 messageFee, ) = _quoteWormholeFee(dstChainId, true);

        // Validate that we have sufficient fees to send crosschain
        if (address(this).balance < messageFee) {
            revert ProtocolMessagingHub__InsufficientGasToken();
        }

        // Pull the fee token from the fee accumulator
        // This will revert if we've misconfigured fee token contract supply
        // by `amountLD`
        SafeTransferLib.safeTransferFrom(
            feeToken,
            centralRegistry.feeAccumulator(),
            address(this),
            amount
        );

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
    }

    /// @notice Quotes gas cost and token fee for executing crosschain
    ///         wormhole deposit and messaging.
    /// @param dstChainId Wormhole specific destination chain ID.
    /// @param transferToken Whether deliver token or not.
    /// @return Total gas cost.
    /// @return Deliverying fee.
    function quoteWormholeFee(
        uint16 dstChainId,
        bool transferToken
    ) external view returns (uint256, uint256) {
        return _quoteWormholeFee(dstChainId, transferToken);
    }

    /// @notice Permissioned function for returning fees reimbursed from
    ///         Stargate to FeeAccumulator.
    /// @dev This is for if we ever need to depreciate this
    ///      ProtocolMessagingHub for another.
    function returnReimbursedFees() external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert ProtocolMessagingHub__Unauthorized();
        }

        SafeTransferLib.safeTransfer(
            feeToken,
            centralRegistry.feeAccumulator(),
            IERC20(feeToken).balanceOf(address(this))
        );
    }

    /// @notice Sends veCVE locked token data to destination chain.
    /// @param dstChainId Destination chain ID where the message data should be
    ///                   sent.
    /// @param toAddress The destination address specified by `dstChainId`.
    /// @param payload The payload data that is sent along with the message.
    /// @param etherValue How much ether to attach to the transaction.
    /// @dev Calls with this function will have messageType = 1 or messageType = 2
    function sendLockedTokenData(
        uint16 dstChainId,
        address toAddress,
        bytes calldata payload,
        uint256 etherValue
    ) external payable {
        _checkPermissions();

        // Validate that we are aiming for a supported chain.
        if (
            centralRegistry
                .supportedChainData(
                    centralRegistry.messagingToGETHChainId(dstChainId)
                )
                .isSupported < 2
        ) {
            revert ProtocolMessagingHub__ChainIsNotSupported();
        }

        if (msg.value != etherValue) {
            revert ProtocolMessagingHub__InvalidMsgValue();
        }

        wormholeRelayer.sendPayloadToEvm{ value: etherValue }(
            dstChainId,
            toAddress,
            abi.encode(uint8(4), cve, payload), // payload
            0, // no receiver value needed since we're just passing a message
            _GAS_LIMIT
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Quotes gas cost and token fee for executing crosschain
    ///         wormhole deposit and messaging.
    /// @param dstChainId Wormhole specific destination chain ID.
    /// @param transferToken Whether deliver token or not.
    /// @return nativeFee Total gas cost.
    /// @return tokenFee Deliverying fee.
    function _quoteWormholeFee(
        uint16 dstChainId,
        bool transferToken
    ) internal view returns (uint256 nativeFee, uint256 tokenFee) {
        // Cost of delivering token and payload to targetChain.
        (nativeFee, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            dstChainId,
            0,
            _GAS_LIMIT
        );

        if (transferToken) {
            // Add cost of publishing the 'sending token' wormhole message.
            nativeFee += wormhole.messageFee();
        }

        tokenFee = circleRelayer.relayerFee(dstChainId, feeToken);
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkPermissions() internal view {
        if (
            !centralRegistry.isHarvester(msg.sender) &&
            msg.sender != centralRegistry.feeAccumulator()
        ) {
            revert ProtocolMessagingHub__Unauthorized();
        }
    }
}
