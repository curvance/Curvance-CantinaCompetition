// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface ICVE {
    /// @notice Sends CVE to a desired destination chain
    function sendFrom(
        address from,
        uint16 dstChainId,
        address toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams,
        bytes calldata payload
    ) external;

    /// @notice Sends CVE Gauge Emissions to a desired destination chain
    function sendEmissions(
        address from,
        uint16 dstChainId,
        address toAddress,
        address[] calldata pools,
        uint256[] calldata poolEmissions,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external;
}
