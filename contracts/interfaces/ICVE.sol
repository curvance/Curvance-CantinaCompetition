// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface ICVE {

    struct LzCallParams {
        address payable refundAddress;
        address zroPaymentAddress;
        bytes adapterParams;
    }

    /// @notice Used by protocol messaging hub to mint gauge emissions for the upcoming epoch
    function mintGaugeEmissions(
        uint256 gaugeEmissions,
        address gaugePool
    ) external;

    /// @notice Sends CVE Gauge Emissions or token lock data to a desired destination chain
    function sendAndCall(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint256 _amount,
        bytes calldata _payload,
        uint64 _dstGasForCall,
        LzCallParams calldata _callParams
    ) external payable;
}
