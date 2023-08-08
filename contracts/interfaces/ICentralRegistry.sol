// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

/// TYPES ///

struct omnichainData {
    uint256 isAuthorized; // Whether the contract is supported or not; 2 = yes; 0 or 1 = no
    // @dev We will need to make sure SALTs are different crosschain
    //      so that we do not accidently deploy the same contract address
    //      across multiple chains
    uint256 chainId; // chainId where this address authorized 
    uint256 messagingChainId; // messaging chainId where this address authorized
    bytes cveAddress; // CVE Address on the chain
}

interface ICentralRegistry {
    /// @notice Returns Genesis Epoch Timestamp of Curvance
    function genesisEpoch() external view returns (uint256);

    /// @notice Returns Protocol DAO Address
    function daoAddress() external view returns (address);

    /// @notice Returns whether the caller has dao permissions or not
    function hasDaoPermissions(address _address) external view returns (bool);

    /// @notice Returns whether the caller has elevated protocol permissions
    ///         or not
    function hasElevatedPermissions(
        address _address
    ) external view returns (bool);

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

    /// @notice Returns ZRO Payment Address
    function zroAddress() external view returns (address);

    /// @notice Returns feeAccumulator Address
    function feeAccumulator() external view returns (address);

    /// @notice Returns protocolCompoundFee Address
    function protocolCompoundFee() external view returns (uint256);

    /// @notice Returns protocolYieldFee Address
    function protocolYieldFee() external view returns (uint256);

    /// @notice Returns protocolHarvestFee Address
    function protocolHarvestFee() external view returns (uint256);

    /// @notice Returns protocolLiquidationFee Address
    function protocolLiquidationFee() external view returns (uint256);

    /// @notice Returns protocolLeverageFee Address
    function protocolLeverageFee() external view returns (uint256);

    /// @notice Returns protocolInterestRateFee Address
    function protocolInterestRateFee() external view returns (uint256);

    /// @notice Returns earlyUnlockPenaltyValue value in basis point form
    function earlyUnlockPenaltyValue() external view returns (uint256);

    /// @notice Returns voteBoostValue value in basis point form
    function voteBoostValue() external view returns (uint256);

    /// @notice Returns lockBoostValue value in basis point form
    function lockBoostValue() external view returns (uint256);

    /// @notice Returns what other chains are supported
    function supportedChains() external view returns (uint256[] memory);

    // Address => Curvance identification information
    function omnichainOperators(address _address) external view returns (omnichainData memory);

    /// @notice Returns whether the inputted address is an approved zapper
    function isZapper(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved swapper
    function isSwapper(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved veCVELocker
    function isVeCVELocker(
        address _address
    ) external view returns (bool);

    /// @notice Returns whether the inputted address is a Gauge Controller
    function isGaugeController(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Harvester
    function isHarvester(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Lending Market
    function isLendingMarket(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an Approved Endpoint
    function isEndpoint(address _address) external view returns (bool);
}
