// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

struct LzCallParams {
    address payable refundAddress;
    address zroPaymentAddress;
    bytes adapterParams;
}

interface ICVE {
    /// @notice Used by protocol messaging hub to mint gauge emissions for
    ///         the upcoming epoch
    function mintGaugeEmissions(address gaugePool, uint256 amount) external;

    /// @notice Used by gauge pools to mint CVE for a users lock boost
    function mintLockBoost(uint256 amount) external;

    /// @notice Sends CVE Gauge Emissions or token lock data to
    ///         a desired destination chain
    function sendAndCall(
        address from,
        uint16 dstChainId,
        bytes32 toAddress,
        uint256 amount,
        bytes calldata payload,
        uint64 dstGasForCall,
        LzCallParams calldata callParams
    ) external payable;

    /// @notice Estimates gas token needed to execute the desired sendAndCall
    function estimateSendAndCallFee(
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint256 _amount,
        bytes calldata _payload,
        uint64 _dstGasForCall,
        bool _useZro,
        bytes calldata _adapterParams
    ) external view returns (uint256);
}
