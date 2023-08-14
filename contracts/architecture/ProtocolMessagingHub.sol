// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { GaugeController } from "contracts/gauge/GaugeController.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ICVE, LzCallParams } from "contracts/interfaces/ICVE.sol";
import { IFeeAccumulator, EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { swapRouter, lzTxObj } from "contracts/interfaces/layerzero/IStargateRouter.sol";
import { PoolData } from "contracts/interfaces/IProtocolMessagingHub.sol";

contract ProtocolMessagingHub is ReentrancyGuard {
    /// CONSTANTS ///

    uint256 public constant DENOMINATOR = 10000; // Scalar for math
    ICVE public immutable CVE; // CVE contract address
    IWETH public immutable WETH; // Address of WETH
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///
    mapping(uint256 => uint256) public nonceUsed;

    /// ERRORS ///

    error ProtocolMessagingHub_ConfigurationError();
    error ProtocolMessagingHub_InsufficientGasToken();

    /// MODIFIERS ///

    modifier onlyAuthorized() {
        require(
            centralRegistry.isHarvester(msg.sender) ||
                msg.sender == centralRegistry.feeAccumulator(),
            "ProtocolMessagingHub: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "ProtocolMessagingHub: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyLayerZero() {
        require(
            msg.sender == centralRegistry.CVE(),
            "ProtocolMessagingHub: UNAUTHORIZED"
        );
        _;
    }

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address WETH_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert ProtocolMessagingHub_ConfigurationError();
        }

        centralRegistry = centralRegistry_;
        CVE = ICVE(centralRegistry.CVE());
        WETH = IWETH(WETH_);
    }

    /// EXTERNAL FUNCTIONS ///

    // Used when fees are received from other chains
    function sgReceive(
        uint16, // chainId: The remote chainId sending the tokens
        bytes memory, // srcAddress: The remote Bridge address
        uint256, // nonce: The message ordering nonce
        address token, // The token contract on the local chain
        uint256 amountLD, // The qty of local _token contract tokens
        bytes memory // payload: The bytes containing the _tokenOut, //_deadline, _amountOutMin, _toAddr
    ) external payable {
        // Stargate uses address(0) = ETH
        if (token == address(0)) {
            WETH.deposit{ value: amountLD }(amountLD);
            SafeTransferLib.safeTransfer(
                address(WETH),
                centralRegistry.feeAccumulator(),
                amountLD
            );
        }
    }

    /// @notice Sends gauge emission information to multiple destination chains
    /// @param dstChainId Destination chain ID where the message data should be sent
    /// @param toAddress The destination address specified by `dstChainId`
    /// @param payload The payload data that is sent along with the message
    /// @param dstGasForCall The amount of gas that should be provided for the call on the destination chain
    /// @param adapterParams Additional parameters for the adapter, as bytes
    /// @param callParams AdditionalParameters for the call, as LzCallParams
    /// @dev   We redundantly pass adapterParams & callParams so we do not need to coerce data in the function,
    ///        calls with this function will have messageType = 3
    function sendGaugeEmissions(
        uint16 dstChainId,
        bytes32 toAddress,
        bytes calldata payload,
        uint64 dstGasForCall,
        bytes calldata adapterParams,
        LzCallParams calldata callParams
    ) external onlyAuthorized {
        // Validate that we are aiming for a supported chain
        if (
            centralRegistry
                .supportedChainData(
                    centralRegistry.messagingToGETHChainId(dstChainId)
                )
                .isSupported < 2
        ) {
            revert ProtocolMessagingHub_ConfigurationError();
        }
        CVE.sendAndCall{
            value: CVE.estimateSendAndCallFee(
                dstChainId,
                toAddress,
                0,
                payload,
                dstGasForCall,
                false, // may need to turn on ZRO in the future but can redeploy ProtocolMessagingHub
                adapterParams
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

    /// @notice Sends WETH fees to the Fee Accumulator on `dstChainId`
    /// @param to The address Stargate Endpoint to call
    /// @param poolData Stargate pool routing data
    /// @param lzTxParams Supplemental LayerZero parameters for the transaction
    /// @param payload Additional payload data
    function sendFees(
        address to,
        PoolData calldata poolData,
        lzTxObj calldata lzTxParams,
        bytes calldata payload
    ) external onlyAuthorized {
        OmnichainData memory operator = centralRegistry.omnichainOperators(to);
        // Validate that the operator is authorized
        if (operator.isAuthorized < 2) {
            revert ProtocolMessagingHub_ConfigurationError();
        }

        // Validate that the operator messaging chain matches the destination chain id
        if (operator.messagingChainId != poolData.dstChainId) {
            revert ProtocolMessagingHub_ConfigurationError();
        }

        // Validate that we are aiming for a supported chain
        if (
            centralRegistry
                .supportedChainData(
                    centralRegistry.messagingToGETHChainId(poolData.dstChainId)
                )
                .isSupported < 2
        ) {
            revert ProtocolMessagingHub_ConfigurationError();
        }

        address endpoint = IFeeAccumulator(centralRegistry.feeAccumulator())
            .router();

        bytes memory bytesTo = new bytes(32);
        assembly {
            mstore(add(bytesTo, 32), to)
        }

        // Might be worth it to remove this and let the transaction fail if we do not have sufficient funds attached
        // @trust what do you think?
        {
            // Scoping to avoid stack too deep
            (uint256 messageFee, ) = this.quoteStargateFee(
                swapRouter(endpoint),
                uint16(poolData.dstChainId),
                1,
                bytesTo,
                "",
                lzTxParams
            );

            // Validate that we have sufficient fees to send crosschain
            if (poolData.amountLD < messageFee) {
                revert ProtocolMessagingHub_InsufficientGasToken();
            }
        }

        // Pull the WETH from the fee accumulator
        // This will revert if we've misconfigured WETH contract supply by `amountLD`
        SafeTransferLib.safeTransferFrom(
            address(WETH),
            centralRegistry.feeAccumulator(),
            address(this),
            poolData.amountLD
        );

        // Withdraw ETH from WETH contract
        WETH.withdraw(poolData.amountLD);

        // Sends funds to feeAccumulator on another chain
        swapRouter(endpoint).swap{ value: poolData.amountLD }(
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

    /// @notice Handles actions based on the payload provided from calling CVE's OFT integration where:
    ///         messageType = 1 corresponds to locked token information transfer
    ///         messageType = 2 receiving finalized token epoch rewards information
    ///         messageType = 3 corresponds to configuring gauge emissions for the chain
    /// @dev amount is always set to 0 since we are moving data, or minting gauge emissions here
    /// @param srcChainId The source chain ID from which the calldata was received
    /// @param srcAddress The CVE source address
    /// @param nonce A unique identifier for the transaction, used to prevent replay attacks
    /// @param from The address from which the OFT was sent
    /// @param payload The message calldata, encoded in bytes
    function onOFTReceived(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes32 from,
        uint256, // amount
        bytes calldata payload
    ) external onlyLayerZero {
        OmnichainData memory operator = centralRegistry.omnichainOperators(
            address(uint160(uint256(from)))
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

        // Validate message nonce has not been used before
        if (nonceUsed[nonce] == 2) {
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

        // Message Type 1: receive feeAccumulator information of locked tokens on a chain for the epoch
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
            nonceUsed[nonce] = 2; // 2 = used; 0 or 1 = unused
            return;
        }

        // Message Type 2: receive finalized epoch rewards data
        if (messageType == 2) {
            IFeeAccumulator(centralRegistry.feeAccumulator())
                .receiveExecutableLockData(chainLockedAmount);
        }

        // Message Type 3+: update gauge emissions for all gauge controllers on this chain
        {
            // Use scoping for stack too deep logic
            uint256 lockBoostMultiplier = centralRegistry.lockBoostValue();
            uint256 numPools = gaugePools.length;
            GaugeController gaugePool;

            for (uint256 i; i < numPools; ) {
                gaugePool = GaugeController(gaugePools[i]);
                // Mint epoch gauge emissions to the gauge pool
                CVE.mintGaugeEmissions(
                    (lockBoostMultiplier * emissionTotals[i]) / DENOMINATOR,
                    address(gaugePool)
                );
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

        nonceUsed[nonce] = 2; // 2 = used; 0 or 1 = unused
    }

    /// @notice Quotes gas cost for executing crosschain stargate swap
    /// @dev Intentionally greatly overestimates so we are sure that a multicall will not fail
    function overEstimateStargateFee(
        swapRouter stargateRouter,
        uint8 functionType,
        bytes calldata toAddress,
        uint256 transactions
    ) external view returns (uint256 fee, uint256) {
        if (block.chainid == 1) {
            (fee, ) = stargateRouter.quoteLayerZeroFee(
                110, // Arbitrum Destination
                functionType,
                toAddress,
                "",
                lzTxObj({
                    dstGasForCall: 0,
                    dstNativeAmount: 0,
                    dstNativeAddr: ""
                })
            );
            // Overestimate fees 5x to make sure it does not fail
            return (fee * transactions * 5, 0);
        }

        (fee, ) = stargateRouter.quoteLayerZeroFee(
            101, // Ethereum Destination
            functionType,
            toAddress,
            "",
            lzTxObj({
                dstGasForCall: 0,
                dstNativeAmount: 0,
                dstNativeAddr: ""
            })
        );
        // Overestimate fees by estimating moving to mainnet every time
        return (fee * transactions, 0);
    }

    /// @notice Quotes gas cost for executing crosschain stargate swap
    function quoteStargateFee(
        swapRouter stargateRouter,
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    ) external view returns (uint256, uint256) {
        return
            stargateRouter.quoteLayerZeroFee(
                _dstChainId,
                _functionType,
                _toAddress,
                _transferAndCallPayload,
                _lzTxParams
            );
    }

    /// @notice Permissioned function for returning fees reimbursed from Stargate to FeeAccumulator
    /// @dev    This is for if we ever need to depreciate this ProtocolMessagingHub for another
    function returnReimbursedFees() external onlyDaoPermissions {
        WETH.deposit{ value: address(this).balance }(address(this).balance);

        SafeTransferLib.safeTransfer(
            address(WETH),
            centralRegistry.feeAccumulator(),
            address(this).balance
        );
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Sends veCVE locked token data to destination chain
    /// @param dstChainId The destination chain ID where the message data should be sent
    /// @param toAddress The destination addresses specified by `dstChainId`
    /// @param payload The payload data that is sent along with the message
    /// @param dstGasForCall The amount of gas that should be provided for the call on the destination chain
    /// @param callParams AdditionalParameters for the call, as LzCallParams
    /// @param etherValue How much ether to attach to the transaction
    /// @dev   We redundantly pass adapterParams & callParams so we do not need to coerce data in the function,
    ///        calls with this function will have messageType = 1 or messageType = 2
    function sendLockedTokenData(
        uint16 dstChainId,
        bytes32 toAddress,
        bytes calldata payload,
        uint64 dstGasForCall,
        LzCallParams calldata callParams,
        uint256 etherValue
    ) public payable onlyAuthorized {
        // Validate that we are aiming for a supported chain
        if (
            centralRegistry
                .supportedChainData(
                    centralRegistry.messagingToGETHChainId(dstChainId)
                )
                .isSupported < 2
        ) {
            revert ProtocolMessagingHub_ConfigurationError();
        }

        //
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
}
