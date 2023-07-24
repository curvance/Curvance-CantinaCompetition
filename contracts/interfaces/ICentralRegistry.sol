// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

interface ICentralRegistry {
    /// @notice Returns Genesis Epoch Timestamp of Curvance
    function genesisEpoch() external view returns (uint256);

    /// @notice Returns Protocol DAO Address
    function daoAddress() external view returns (address);

    /// @notice Returns whether the caller has dao permissions or not
    function hasDaoPermissions(address _address) external view returns (bool);

    /// @notice Returns whether the caller has elevated protocol permissions or not
    function hasElevatedPermissions(address _address) external view returns (bool);

    /// @notice Returns CVE Locker Address
    function cveLocker() external view returns (address);

    /// @notice Returns CVE Address
    function CVE() external view returns (address);

    /// @notice Returns veCVE Address
    function veCVE() external view returns (address);

    /// @notice Returns Call Option Address
    function callOptionCVE() external view returns (address);

    /// @notice Returns Protocol Messaging Hub Address
    function protocolMessagingHub() external view returns (address);

    /// @notice Returns Price Router Address
    function priceRouter() external view returns (address);

    /// @notice Returns Deposit Router Address
    function depositRouter() external view returns (address);

    /// @notice Returns ZRO Payment Address
    function zroAddress() external view returns (address);

    /// @notice Returns feeHub Address
    function feeHub() external view returns (address);

    /// @notice Returns protocolYieldFee Address
    function protocolYieldFee() external view returns (uint256);

    /// @notice Returns protocolLiquidationFee Address
    function protocolLiquidationFee() external view returns (uint256);

    /// @notice Returns protocolLiquidationFee Address
    function protocolLeverageFee() external view returns (uint256);

    /// @notice Returns voteBoostValue value in basis point form
    function voteBoostValue() external view returns (uint256);

    /// @notice Returns lockBoostValue value in basis point form
    function lockBoostValue() external view returns (uint256);

    /// @notice Returns whether the inputted address is an approved zapper
    function approvedZapper(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved swapper
    function approvedSwapper(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved veCVELocker
    function approvedVeCVELocker(
        address _address
    ) external view returns (bool);

    /// @notice Returns whether the inputted address is a Gauge Controller
    function gaugeController(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Harvester
    function harvester(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Lending Market
    function lendingMarket(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Fee Manager
    function feeManager(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an Approved Endpoint
    function approvedEndpoint(address _address) external view returns (bool);
}
