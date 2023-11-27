// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { GaugeController } from "contracts/gauge/GaugeController.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICVE, LzCallParams } from "contracts/interfaces/ICVE.sol";
import { IFeeAccumulator, EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { SwapRouter, LzTxObj } from "contracts/interfaces/layerzero/IStargateRouter.sol";
import { PoolData } from "contracts/interfaces/IProtocolMessagingHub.sol";

contract ProtocolMessagingHub is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice CVE contract address
    ICVE public immutable CVE;
    /// @notice Address of fee token
    address public immutable feeToken;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Address of Stargate Router
    address public stargateRouter;

    /// ERRORS ///

    error ProtocolMessagingHub__Unauthorized();
    error ProtocolMessagingHub__InvalidCentralRegistry();
    error ProtocolMessagingHub__FeeTokenIsZeroAddress();
    error ProtocolMessagingHub__StargateRouterIsZeroAddress();
    error ProtocolMessagingHub__ChainIsNotSupported();
    error ProtocolMessagingHub__OperatorIsNotAuthorized(
        address to,
        uint256 gethChainId
    );
    error ProtocolMessagingHub__MessagingChainIdIsNotDstChainId(
        uint256 messagingChainId,
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
        address stargateRouter_
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
        if (stargateRouter_ == address(0)) {
            revert ProtocolMessagingHub__StargateRouterIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        CVE = ICVE(centralRegistry.CVE());
        feeToken = feeToken_;
        stargateRouter = stargateRouter_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Set Stargate router destination address to route fees
    function setStargateAddress(address newStargateRouter) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert ProtocolMessagingHub__Unauthorized();
        }

        if (newStargateRouter == address(0)) {
            revert ProtocolMessagingHub__StargateRouterIsZeroAddress();
        }

        stargateRouter = newStargateRouter;
    }

    /// @notice Used when fees are received from other chains.
    /// @param token The token contract on the local chain.
    /// @param amountLD The qty of local _token contract tokens.
    function sgReceive(
        uint16 /* chainId */, // The remote chainId sending the tokens
        bytes memory /* srcAddress */, // The remote Bridge address
        uint256 /* nonce */, // The message ordering nonce
        address token,
        uint256 amountLD,
        bytes memory /* payload */
    ) external payable {
        if (msg.sender != stargateRouter) {
            revert ProtocolMessagingHub__Unauthorized();
        }

        address locker = centralRegistry.cveLocker();

        SafeTransferLib.safeTransfer(token, locker, amountLD);

        IFeeAccumulator(centralRegistry.feeAccumulator()).recordEpochRewards(
            amountLD
        );
    }

    /// @notice Sends gauge emission information to multiple destination chains
    /// @param dstChainId Destination chain ID where the message data should be
    ///                   sent
    /// @param toAddress The destination address specified by `dstChainId`
    /// @param payload The payload data that is sent along with the message
    /// @param dstGasForCall The amount of gas that should be provided for
    ///                      the call on the destination chain
    /// @param callParams Additional parameters for the call, as LzCallParams
    /// @dev We redundantly pass adapterParams & callParams so we do not
    ///      need to coerce data in the function, calls with this function will
    ///      have messageType = 3
    function sendGaugeEmissions(
        uint16 dstChainId,
        bytes32 toAddress,
        bytes calldata payload,
        uint64 dstGasForCall,
        LzCallParams calldata callParams
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
        CVE.sendAndCall{
            value: CVE.estimateSendAndCallFee(
                dstChainId,
                toAddress,
                0,
                payload,
                dstGasForCall,
                // may need to turn on ZRO in the future but can redeploy
                // ProtocolMessagingHub
                false,
                callParams.adapterParams
            )
        }(
            address(this),
            dstChainId,
            toAddress,
            0,
            payload,
            dstGasForCall,
            callParams
        );
    }

    /// @notice Sends fee tokens to the Messaging Hub on `dstChainId`
    /// @param to The address of Messaging Hub on `dstChainId`
    /// @param poolData Stargate pool routing data
    /// @param lzTxParams Supplemental LayerZero parameters for the transaction
    /// @param payload Additional payload data
    function sendFees(
        address to,
        PoolData calldata poolData,
        LzTxObj calldata lzTxParams,
        bytes calldata payload
    ) external {
        _checkPermissions();

        {
            // Avoid stack too deep
            uint256 gethChainId = centralRegistry.messagingToGETHChainId(
                poolData.dstChainId
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
            if (operator.messagingChainId != poolData.dstChainId) {
                revert ProtocolMessagingHub__MessagingChainIdIsNotDstChainId(
                    operator.messagingChainId,
                    poolData.dstChainId
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

        bytes memory bytesTo = new bytes(32);
        assembly {
            mstore(add(bytesTo, 32), to)
        }

        (uint256 messageFee, ) = _quoteStargateFee(
            uint16(poolData.dstChainId),
            1,
            bytesTo,
            "",
            lzTxParams
        );

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
            poolData.amountLD
        );

        SwapperLib._approveTokenIfNeeded(
            feeToken,
            stargateRouter,
            poolData.amountLD
        );

        // Sends funds to feeAccumulator on another chain
        SwapRouter(stargateRouter).swap{ value: messageFee }(
            uint16(poolData.dstChainId),
            poolData.srcPoolId,
            poolData.dstPoolId,
            payable(address(this)),
            poolData.amountLD,
            poolData.minAmountLD,
            lzTxParams,
            bytesTo,
            payload
        );
    }

    /// @notice Handles actions based on the payload provided from calling
    ///         CVE's OFT integration where messageType:
    ///         1: corresponds to locked token information transfer
    ///         2: receiving finalized token epoch rewards information
    ///         3: corresponds to configuring gauge emissions for the chain
    /// @dev amount is always set to 0 since we are moving data,
    ///      or minting gauge emissions here
    /// @param srcChainId The source chain ID from which the calldata
    ///                   was received
    /// @param srcAddress The CVE source address
    /// @param from The address from which the OFT was sent
    /// @param payload The message calldata, encoded in bytes
    function onOFTReceived(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64, // nonce
        bytes32 from,
        uint256, // amount
        bytes calldata payload
    ) external {
        // Validate caller is CVE itself
        if (msg.sender != centralRegistry.CVE()) {
            revert ProtocolMessagingHub__Unauthorized();
        }

        OmnichainData memory operator = centralRegistry.getOmnichainOperators(
            address(uint160(uint256(from))),
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
        if (bytes32(operator.cveAddress) != bytes32(srcAddress)) {
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
                payload,
                (
                    address[],
                    uint256[],
                    address[][],
                    uint256[][],
                    uint256,
                    uint256
                )
            );

        // Message Type 1: receive feeAccumulator information of locked tokens
        //                 on a chain for the epoch
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

        // Message Type 2: receive finalized epoch rewards data
        if (messageType == 2) {
            IFeeAccumulator(centralRegistry.feeAccumulator())
                .receiveExecutableLockData(chainLockedAmount);
            return;
        }

        // Message Type 3+: update gauge emissions for all gauge controllers on
        //                  this chain
        {
            // Use scoping for stack too deep logic
            uint256 numPools = gaugePools.length;
            GaugeController gaugePool;

            for (uint256 i; i < numPools; ) {
                gaugePool = GaugeController(gaugePools[i]);
                // Mint epoch gauge emissions to the gauge pool
                CVE.mintGaugeEmissions(address(gaugePool), emissionTotals[i]);
                // Set upcoming epoch emissions for the voted configuration
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

    /// @notice Quotes gas cost for executing crosschain stargate swap
    function quoteStargateFee(
        uint16 dstChainId,
        uint8 functionType,
        bytes calldata toAddress,
        bytes calldata transferAndCallPayload,
        LzTxObj calldata lzTxParams
    ) external view returns (uint256, uint256) {
        return
            _quoteStargateFee(
                dstChainId,
                functionType,
                toAddress,
                transferAndCallPayload,
                lzTxParams
            );
    }

    /// @notice Permissioned function for returning fees reimbursed from
    ///         Stargate to FeeAccumulator
    /// @dev This is for if we ever need to depreciate this
    ///      ProtocolMessagingHub for another
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

    /// PUBLIC FUNCTIONS ///

    /// @notice Sends veCVE locked token data to destination chain
    /// @param dstChainId The destination chain ID where the message data
    ///                   should be sent
    /// @param toAddress The destination addresses specified by `dstChainId`
    /// @param payload The payload data that is sent along with the message
    /// @param dstGasForCall The amount of gas that should be provided for
    ///                      the call on the destination chain
    /// @param callParams AdditionalParameters for the call, as LzCallParams
    /// @param etherValue How much ether to attach to the transaction
    /// @dev We redundantly pass adapterParams & callParams so we do not
    ///      need to coerce data in the function, calls with this function will
    ///      have messageType = 1 or messageType = 2
    function sendLockedTokenData(
        uint16 dstChainId,
        bytes32 toAddress,
        bytes calldata payload,
        uint64 dstGasForCall,
        LzCallParams calldata callParams,
        uint256 etherValue
    ) public payable {
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

        if (msg.value != etherValue) {
            revert ProtocolMessagingHub__InvalidMsgValue();
        }

        CVE.sendAndCall{ value: etherValue }(
            address(this),
            dstChainId,
            toAddress,
            0,
            payload,
            dstGasForCall,
            callParams
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Quotes gas cost for executing crosschain stargate swap
    function _quoteStargateFee(
        uint16 dstChainId,
        uint8 functionType,
        bytes memory toAddress,
        bytes memory transferAndCallPayload,
        LzTxObj memory lzTxParams
    ) internal view returns (uint256, uint256) {
        return
            SwapRouter(stargateRouter).quoteLayerZeroFee(
                dstChainId,
                functionType,
                toAddress,
                transferAndCallPayload,
                lzTxParams
            );
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
