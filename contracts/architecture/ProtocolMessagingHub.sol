// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugeController } from "contracts/gauge/GaugeController.sol";
import { FeeTokenBridgingHub } from "contracts/architecture/FeeTokenBridgingHub.sol";

import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";
import { IFeeAccumulator, EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/external/wormhole/ITokenBridgeRelayer.sol";

contract ProtocolMessagingHub is FeeTokenBridgingHub {
    /// CONSTANTS ///

    /// @notice CVE contract address.
    ICVE public immutable cve;

    /// @notice veCVE contract address.
    address public immutable veCVE;

    /// @notice Wormhole specific chain ID for evm chain ID.
    mapping(uint256 => uint16) public wormholeChainId;

    /// `bytes4(keccak256(bytes("ProtocolMessagingHub__Unauthorized()")))`.
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xc70c67ab;

    /// STORAGE ///

    /// @notice 0 or 1 = activate; 2 = paused.
    uint256 public isPaused;
    /// @notice Status of message hash whether it's delivered or not.
    mapping(bytes32 => bool) public isDeliveredMessageHash;

    /// ERRORS ///

    error ProtocolMessagingHub__Unauthorized();
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
        ICentralRegistry centralRegistry_
    ) FeeTokenBridgingHub(centralRegistry_) {
        cve = ICVE(centralRegistry.cve());
        veCVE = centralRegistry.veCVE();
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
    ///                the Wormhole Relayer contract).
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

        address wormholeRelayer = address(centralRegistry.wormholeRelayer());

        if (msg.sender != wormholeRelayer) {
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

        // Validate message came directly from MessagingHub on the source chain.
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

            address feeToken = centralRegistry.feeToken();

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
        } else if (payloadId == 5) {
            (, bytes memory lockData) = abi.decode(payload, (uint8, bytes));

            (address recipient, uint256 amount, bool continuousLock) = abi
                .decode(lockData, (address, uint256, bool));

            cve.mintVeCVELock(amount);
            cve.approve(veCVE, amount);

            RewardsData memory rewardData;

            // rewardData is forced to be an empty struct since Curvance does
            // not how long it has been between lock destruction and creation,
            // and any dynamic action could have stale characteristics.
            IVeCVE(veCVE).createLockFor(
                recipient,
                amount,
                continuousLock,
                rewardData,
                "",
                0
            );
        }
    }

    /// @notice Sends fee tokens to the Messaging Hub on `dstChainId`.
    /// @param dstChainId Wormhole specific destination chain ID.
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

        // Pull the fee token from the fee accumulator.
        // This will revert if we've misconfigured fee token contract supply
        // by `amount`.
        SafeTransferLib.safeTransferFrom(
            centralRegistry.feeToken(),
            centralRegistry.feeAccumulator(),
            address(this),
            amount
        );

        _sendFeeToken(dstChainId, to, amount);
    }

    /// @notice Send wormhole message to bridge CVE.
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

        _checkMessagingHubStatus();

        ITokenBridgeRelayer tokenBridgeRelayer = centralRegistry
            .tokenBridgeRelayer();

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

    /// @notice Send wormhole message to bridge VeCVE lock.
    /// @param dstChainId Chain ID of the target blockchain.
    /// @param recipient The address of recipient on destination chain.
    /// @param amount The amount of token to bridge.
    /// @param continuousLock Whether the lock should be continuous or not.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function bridgeVeCVELock(
        uint256 dstChainId,
        address recipient,
        uint256 amount,
        bool continuousLock
    ) external payable returns (uint64) {
        if (msg.sender != veCVE) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _checkMessagingHubStatus();

        address dstMessagingHub = centralRegistry
            .supportedChainData(dstChainId)
            .messagingHub;
        bytes memory payload = abi.encode(recipient, amount, continuousLock);

        return
            _sendWormholeMessages(
                wormholeChainId[dstChainId],
                dstMessagingHub,
                msg.value,
                5,
                payload
            );
    }

    /// @notice Sends veCVE locked token data to destination chain.
    /// @param dstChainId Wormhole specific destination chain ID where
    ///                   the message data should be sent.
    /// @param toAddress The destination address specified by `dstChainId`.
    /// @param payload The payload data that is sent along with the message.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function sendWormholeMessages(
        uint16 dstChainId,
        address toAddress,
        bytes calldata payload
    ) external payable returns (uint64) {
        _checkMessagingHubStatus();
        _checkPermissions();

        uint256 messageFee = _quoteWormholeFee(dstChainId, false);

        return
            _sendWormholeMessages(
                dstChainId,
                toAddress,
                messageFee,
                4,
                payload
            );
    }

    /// @notice Returns required amount of CVE for relayer fee.
    /// @param dstChainId Chain ID of the target blockchain.
    /// @return Required fee.
    function cveRelayerFee(
        uint256 dstChainId
    ) external view returns (uint256) {
        return
            centralRegistry.tokenBridgeRelayer().calculateRelayerFee(
                wormholeChainId[dstChainId],
                address(cve),
                18
            );
    }

    /// @notice Returns required amount of native asset for message fee.
    /// @return Required fee.
    function cveBridgeFee() external view returns (uint256) {
        return centralRegistry.wormholeCore().messageFee();
    }

    /// DAO PERMISSIONED EXTERNAL FUNCTIONS ///

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

        address feeToken = centralRegistry.feeToken();

        SafeTransferLib.safeTransfer(
            feeToken,
            centralRegistry.feeAccumulator(),
            IERC20(feeToken).balanceOf(address(this))
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Sends veCVE locked token data to destination chain.
    /// @param dstChainId Wormhole specific destination chain ID where
    ///                   the message data should be sent.
    /// @param toAddress The destination address specified by `dstChainId`.
    /// @param payloadId The id of payload.
    /// @param payload The payload data that is sent along with the message.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function _sendWormholeMessages(
        uint16 dstChainId,
        address toAddress,
        uint256 messageFee,
        uint8 payloadId,
        bytes memory payload
    ) internal returns (uint64) {
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

        return
            centralRegistry.wormholeRelayer().sendPayloadToEvm{
                value: messageFee
            }(
                dstChainId,
                toAddress,
                abi.encode(payloadId, payload), // payload
                0, // no receiver value needed since we're just passing a message
                _GAS_LIMIT
            );
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
