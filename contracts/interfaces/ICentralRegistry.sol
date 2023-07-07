// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

interface ICentralRegistry {
    // @notice Returns Genesis Epoch Timestamp of Curvance
    function genesisEpoch() external view returns (uint256);

    // @notice Returns Protocol DAO Address
    function daoAddress() external view returns (address);

    // @notice Returns CVE Locker Address
    function cveLocker() external view returns (address);

    // @notice Returns CVE Address
    function CVE() external view returns (address);

    // @notice Returns veCVE Address
    function veCVE() external view returns (address);

    // @notice Returns Call Option Address
    function callOptionCVE() external view returns (address);

    // @notice Returns Gauge Controller Address
    function gaugeController() external view returns (address);

    // @notice Returns Voting Hub Address
    function votingHub() external view returns (address);

    // @notice Returns Price Router Address
    function priceRouter() external view returns (address);

    // @notice Returns Deposit Router Address
    function depositRouter() external view returns (address);

    // @notice Returns ZRO Payment Address
    function zroAddress() external view returns (address);

    // @notice Returns feeHub Address
    function feeHub() external view returns (address);

    // @notice Returns feeRouter Address
    function feeRouter() external view returns (address);

    // @notice Returns protocolYieldFee Address
    function protocolYieldFee() external view returns (uint256);

    // @notice Returns protocolLiquidationFee Address
    function protocolLiquidationFee() external view returns (uint256);

    // @notice Returns protocolLiquidationFee Address
    function protocolLeverageFee() external view returns (uint256);

    // @notice Returns voteBoostValue value in basis point form
    function voteBoostValue() external view returns (uint256);

    // @notice Returns lockBoostValue value in basis point form
    function lockBoostValue() external view returns (uint256);

    // @notice Returns whether the inputted address is a Harvester
    function isHarvester(address _address) external view returns (bool);

    // @notice Returns whether the inputted address is a lending market
    function isLendingMarket(address _address) external view returns (bool);

    // @notice Returns whether the inputted address is a fee manager
    function isFeeManager(address _address) external view returns (bool);

    // @notice Returns whether the inputted address is an approved endpoint
    function isApprovedEndpoint(address _address) external view returns (bool);

    // @notice Returns whether the current chain is the protocol hub chain
    function isHubChain() external view returns (bool);
}
