// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface ICVE {
    /// @notice Sends CVE to a desired destination chain
    function sendFrom(
        address _from,
        uint16 _dstChainId,
        address _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams,
        bytes calldata _payload
    ) external;

    /// @notice Sends CVE Gauge Emissions to a desired destination chain
    function sendEmissions(
        address _from,
        uint16 _dstChainId,
        address _toAddress,
        address[] calldata _pools,
        uint256[] calldata _poolEmissions,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external;
}
