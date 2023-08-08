// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

struct LzCallParams {
        address payable refundAddress;
        address zroPaymentAddress;
        bytes adapterParams;
    }

interface ICVE {

    /// @notice Used by protocol messaging hub to mint gauge emissions for the upcoming epoch
    function mintGaugeEmissions(
        uint256 gaugeEmissions,
        address gaugePool
    ) external;

    /// @notice Sends CVE Gauge Emissions or token lock data to a desired destination chain
    function sendAndCall(
        address from,
        uint16 dstChainId,
        bytes32 toAddress,
        uint256 amount,
        bytes calldata payload,
        uint64 dstGasForCall,
        LzCallParams calldata callParams
    ) external payable;
}
