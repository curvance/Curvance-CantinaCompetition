// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { GaugeController } from "contracts/gauge/GaugeController.sol";

import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";
import { IFeeAccumulator } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, omnichainData } from "contracts/interfaces/ICentralRegistry.sol";

contract FeeAccumulator is ReentrancyGuard {

    /// CONSTANTS ///

    uint256 public constant DENOMINATOR = 10000; // Scalar for math
    IWETH public immutable WETH; // Address of WETH
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///
    mapping (uint256 => uint256) nonceUsed;

    /// ERRORS ///

    error ProtocolMessagingHub_ConfigurationError();

    /// MODIFIERS ///

    modifier onlyHarvestor() {
        require(
            centralRegistry.isHarvester(msg.sender),
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

    constructor(
        ICentralRegistry centralRegistry_,
        address WETH_
    ) {
        if (!ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )){
                revert ProtocolMessagingHub_ConfigurationError();
            }

        centralRegistry = centralRegistry_;
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
        bytes memory // payload: The bytes containing the _tokenOut, 
                     //_deadline, _amountOutMin, _toAddr
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

    function onOFTReceived(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes32 from,
        uint256, // amount
        bytes calldata payload
    ) external onlyLayerZero {
        omnichainData memory operator = centralRegistry.omnichainOperators(address(uint160(uint256(from))));

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

        (address[] memory gaugePools, 
        uint256[] memory emissionTotals, 
        address[][] memory tokens, 
        uint256[][] memory emissions, 
        uint256 chainLockedAmount, 
        uint256 messageType) = abi.decode(
            payload,
            (address[], uint256[], address[][], uint256[][], uint256, uint256)
        );

        // Message Type 1: notify feeAccumulator of locked tokens on a chain
        if (messageType == 1) {
            IFeeAccumulator(centralRegistry.feeAccumulator()).notifyCrossChainLockData(operator.chainId, chainLockedAmount);
            nonceUsed[nonce] = 2; // 2 = used; 0 or 1 = unused
            return;
        }

        // Message Type 2+: update gauge emissions for all gauge controllers on this chain
        { // Use scoping for stack too deep logic
            ICVE cveAddress = ICVE(centralRegistry.CVE());
            uint256 lockBoostMultiplier = centralRegistry.lockBoostValue();
            uint256 numPools = gaugePools.length;
            GaugeController gaugePool;

            for (uint256 i; i < numPools; ) {
                gaugePool = GaugeController(gaugePools[i]);
                // Mint epoch gauge emissions to the gauge pool
                cveAddress.mintGaugeEmissions(
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

}
