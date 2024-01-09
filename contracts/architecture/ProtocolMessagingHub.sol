// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugeController } from "contracts/gauge/GaugeController.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { ReentrancyGuard } from "contracts/libraries/external/ReentrancyGuard.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "contracts/interfaces/IERC20Metadata.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";
import { IFeeAccumulator, EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";
import { IWormholeRelayer } from "contracts/interfaces/wormhole/IWormholeRelayer.sol";
import { ICircleRelayer } from "contracts/interfaces/wormhole/ICircleRelayer.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/wormhole/ITokenBridgeRelayer.sol";

contract ProtocolMessagingHub is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Gas limit with which to call `targetAddress` via wormhole.
    uint256 internal constant _GAS_LIMIT = 250_000;

    /// @notice CVE contract address.
    ICVE public immutable cve;

    /// @notice veCVE contract address.
    address public immutable veCVE;

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

    /// @notice Wormhole TokenBridgeRelayer.
    ITokenBridgeRelayer public immutable tokenBridgeRelayer;

    /// @notice Wormhole specific chain ID for evm chain ID.
    mapping(uint256 => uint16) public wormholeChainId;

    /// `bytes4(keccak256(bytes("ProtocolMessagingHub__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xc70c67ab;

    /// STORAGE ///

    uint256 public isPaused; // 0 or 1 = activate; 2 = paused

    /// @notice Status of message hash whether it's delivered or not.
    mapping(bytes32 => bool) public isDeliveredMessageHash;

    /// ERRORS ///

    error ProtocolMessagingHub__Unauthorized();
    error ProtocolMessagingHub__InvalidCentralRegistry();
    error ProtocolMessagingHub__FeeTokenIsZeroAddress();
    error ProtocolMessagingHub__WormholeRelayerIsZeroAddress();
    error ProtocolMessagingHub__CircleRelayerIsZeroAddress();
    error ProtocolMessagingHub__TokenBridgeRelayerIsZeroAddress();
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
    error ProtocolMessagingHub__MessagingHubPaused();
    error ProtocolMessagingHub__MessageHashIsAlreadyDelivered(
        bytes32 messageHash
    );

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address feeToken_,
        address wormholeRelayer_,
        address circleRelayer_,
        address tokenBridgeRelayer_
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
        if (tokenBridgeRelayer_ == address(0)) {
            revert ProtocolMessagingHub__TokenBridgeRelayerIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        cve = ICVE(centralRegistry.cve());
        veCVE = centralRegistry.veCVE();
        feeToken = feeToken_;
        wormholeRelayer = IWormholeRelayer(wormholeRelayer_);
        circleRelayer = ICircleRelayer(circleRelayer_);
        tokenBridgeRelayer = ITokenBridgeRelayer(tokenBridgeRelayer_);
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
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory /* additionalMessages */,
        bytes32 srcAddress,
        uint16 srcChainId,
        bytes32 deliveryHash
    ) external payable {
        _checkMessagingHubStatus();

        if (isDeliveredMessageHash[deliveryHash]) {
            revert ProtocolMessagingHub__MessageHashIsAlreadyDelivered(
                deliveryHash
            );
        }

        isDeliveredMessageHash[deliveryHash] = true;

        if (msg.sender != address(wormholeRelayer)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 gethChainId = centralRegistry.messagingToGETHChainId(
            srcChainId
        );
        address srcAddr = address(uint160(uint256(srcAddress)));

        OmnichainData memory operator = centralRegistry.getOmnichainOperators(
            srcAddr,
            gethChainId
        );

        // Validate message came directly from MessagingHub on the source chain
        if (
            centralRegistry.supportedChainData(gethChainId).messagingHub !=
            srcAddr
        ) {
            return;
        }

        // Validate the operator is authorized.
        if (operator.isAuthorized < 2) {
            return;
        }

        // We can skip validating the source chainId is correct for the
        // operator, due to fetching from (srcAddress, srcChainID) mapping.

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
            (, bytes memory emissionData) = abi.decode(
                payload,
                (uint8, bytes)
            );

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

    /// @notice Sends fee tokens to the Messaging Hub on `dstChainId`.
    /// @param dstChainId Wormhole specific destination chain ID .
    /// @param to The address of Messaging Hub on `dstChainId`.
    /// @param amount The amount of token to transfer.
    function sendFees(uint16 dstChainId, address to, uint256 amount) external {
        _checkMessagingHubStatus();
        _checkPermissions();

        {
            // Avoid stack too deep
            uint256 gethChainId = centralRegistry.messagingToGETHChainId(
                dstChainId
            );
            OmnichainData memory operator = centralRegistry
                .getOmnichainOperators(to, gethChainId);

            // Validate that the operator is authorized.
            if (operator.isAuthorized < 2) {
                revert ProtocolMessagingHub__OperatorIsNotAuthorized(
                    to,
                    gethChainId
                );
            }

            // Validate that the operator messaging chain matches.
            // the destination chain id.
            if (operator.messagingChainId != dstChainId) {
                revert ProtocolMessagingHub__MessagingChainIdIsNotDstChainId(
                    operator.messagingChainId,
                    dstChainId
                );
            }

            // Validate that we are aiming for a supported chain.
            if (
                centralRegistry.supportedChainData(gethChainId).isSupported < 2
            ) {
                revert ProtocolMessagingHub__GETHChainIdIsNotSupported(
                    gethChainId
                );
            }
        }

        (uint256 messageFee, ) = _quoteWormholeFee(dstChainId, true);

        // Validate that we have sufficient fees to send crosschain.
        if (address(this).balance < messageFee) {
            revert ProtocolMessagingHub__InsufficientGasToken();
        }

        // Pull the fee token from the fee accumulator.
        // This will revert if we've misconfigured fee token contract supply
        // by `amount`.
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

    /// @notice Register wormhole specific chain IDs for evm chain IDs.
    /// @param chainIds EVM chain IDs.
    /// @param wormholeChainIds Wormhole specific chain IDs.
    function registerWormholeChainIDs(
        uint256[] calldata chainIds,
        uint16[] calldata wormholeChainIds
    ) external {
        _checkAuthorizedPermissions(true);

        uint256 numChainIds = chainIds.length;

        for (uint256 i; i < numChainIds; ++i) {
            wormholeChainId[chainIds[i]] = wormholeChainIds[i];
        }
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

    /// @param dstChainId Chain ID of the target blockchain.
    /// @param recipient The address of recipient on destination chain.
    /// @param amount The amount of token to bridge.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function bridgeCVE(
        uint256 dstChainId,
        address recipient,
        uint256 amount
    ) external payable returns (uint64) {
        if (msg.sender != address(cve)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        cve.approve(address(tokenBridgeRelayer), amount);

        return
            tokenBridgeRelayer.transferTokensWithRelay{ value: msg.value }(
                address(cve),
                amount,
                0,
                wormholeChainId[dstChainId],
                bytes32(uint256(uint160(recipient))),
                0
            );
    }

    /// @param dstChainId Chain ID of the target blockchain.
    /// @param recipient The address of recipient on destination chain.
    /// @param amount The amount of token to bridge.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function bridgeVeCVELock(
        uint256 dstChainId,
        address recipient,
        uint256 amount
    ) external payable returns (uint64) {
        if (msg.sender != veCVE) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        cve.approve(address(tokenBridgeRelayer), amount);

        // Sather can insert lock migration logic here.
        // return
        //     tokenBridgeRelayer.transferTokensWithRelay{ value: msg.value }(
        //         address(cve),
        //         amount,
        //         0,
        //         wormholeChainId[dstChainId],
        //         bytes32(uint256(uint160(recipient))),
        //         0
        //     );
    }

    /// PERMISSIONED EXTERNAL FUNCTIONS ///

    /// @notice Permissioned function that flips the pause status of the
    ///         Messaging Hub.
    function flipMessagingHubStatus() external {
        // If the messaging hub is currently paused,
        // then we are turning pause state off
        bool state = isPaused == 2 ? false : true;
        _checkAuthorizedPermissions(state);

        // Possible outcomes:
        // If pause state is being turned off aka false, then we are turning
        // the messaging hub back on which means isPaused will be = 1
        //
        // If pause state is being turned on aka true, then we are turning
        // the messaging hub off which means isPaused will be = 2
        isPaused = state ? 1 : 2;
    }

    /// @notice Permissioned function for returning fees reimbursed from
    ///         wormhole to FeeAccumulator.
    /// @dev This is for if we ever need to depreciate this
    ///      ProtocolMessagingHub for another.
    /// NOTE: This does not allow any loss of funds as authorized perms are
    ///       required to change fee accumulator, meaning in order to steal
    ///       funds a malicious actor would have had to compromise the whole
    ///       system already. Thus, we only need to check for DAO perms here.
    function returnReimbursedFees() external {
        _checkAuthorizedPermissions(true);

        SafeTransferLib.safeTransfer(
            feeToken,
            centralRegistry.feeAccumulator(),
            IERC20(feeToken).balanceOf(address(this))
        );
    }

    /// @notice Sends veCVE locked token data to destination chain.
    /// @param dstChainId Wormhole specific destination chain ID where
    ///                   the message data should be sent.
    /// @param toAddress The destination address specified by `dstChainId`.
    /// @param payload The payload data that is sent along with the message.
    function sendWormholeMessages(
        uint16 dstChainId,
        address toAddress,
        bytes calldata payload
    ) external payable {
        _checkMessagingHubStatus();
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

        (uint256 messageFee, ) = _quoteWormholeFee(dstChainId, false);

        wormholeRelayer.sendPayloadToEvm{ value: messageFee }(
            dstChainId,
            toAddress,
            abi.encode(uint8(4), payload), // payload
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

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    /// @dev Checks whether the Messaging Hub is paused or not.
    function _checkMessagingHubStatus() internal view {
        if (isPaused == 2) {
            revert ProtocolMessagingHub__MessagingHubPaused();
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkPermissions() internal view {
        if (
            !centralRegistry.isHarvester(msg.sender) &&
            msg.sender != centralRegistry.feeAccumulator()
        ) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller has sufficient permissions
    ///      based on `state`, turning something off is less "risky" than
    ///      enabling something, so `state` = true has reduced permissioning
    ///      compared to `state` = false.
    function _checkAuthorizedPermissions(bool state) internal view {
        if (state) {
            if (!centralRegistry.hasDaoPermissions(msg.sender)) {
                _revert(_UNAUTHORIZED_SELECTOR);
            }
        } else {
            if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
                _revert(_UNAUTHORIZED_SELECTOR);
            }
        }
    }
}
