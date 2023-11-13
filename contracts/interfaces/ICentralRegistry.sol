// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

/// TYPES ///

struct OmnichainData {
    uint256 isAuthorized; // Whether the contract is supported or not; 2 = yes; 0 or 1 = no
    // @dev We will need to make sure SALTs are different crosschain
    //      so that we do not accidently deploy the same contract address
    //      across multiple chains
    uint256 chainId; // chainId where this address authorized
    uint256 messagingChainId; // messaging chainId where this address authorized
    bytes cveAddress; // CVE Address on the chain as bytes array
}

struct ChainData {
    uint256 isSupported; // Whether the chain is supported or not; 2 = yes; 0 or 1 = no
    address messagingHub; // Contract address for destination chains Messaging Hub
    uint256 asSourceAux; // Auxilliary data when chain is source
    uint256 asDestinationAux; // Auxilliary data when chain is destination
    bytes32 cveAddress; // CVE Address on the chain as bytes32
}

interface ICentralRegistry {
    /// @notice Returns Genesis Epoch Timestamp of Curvance
    function genesisEpoch() external view returns (uint256);

    /// @notice Sequencer Uptime Feed address for L2.
    function sequencer() external view returns (address);

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
    function oCVE() external view returns (address);

    /// @notice Returns Protocol Messaging Hub Address
    function protocolMessagingHub() external view returns (address);

    /// @notice Returns Price Router Address
    function priceRouter() external view returns (address);

    /// @notice Returns ZRO Payment Address
    function zroAddress() external view returns (address);

    /// @notice Returns feeAccumulator Address
    function feeAccumulator() external view returns (address);

    /// @notice Returns protocolCompoundFee, in `WAD`
    function protocolCompoundFee() external view returns (uint256);

    /// @notice Returns protocolYieldFee, in `WAD`
    function protocolYieldFee() external view returns (uint256);

    /// @notice Returns protocolHarvestFee, in `WAD`
    function protocolHarvestFee() external view returns (uint256);

    /// @notice Returns protocolLeverageFee, in `WAD`
    function protocolLeverageFee() external view returns (uint256);

    /// @notice Lending Market => Protocol Reserve Factor on interest generated
    function protocolInterestFactor(
        address market
    ) external view returns (uint256);

    /// @notice Returns earlyUnlockPenaltyMultiplier value, in `Basis Points`
    function earlyUnlockPenaltyMultiplier() external view returns (uint256);

    /// @notice Returns voteBoostMultiplier value, in `Basis Points`
    function voteBoostMultiplier() external view returns (uint256);

    /// @notice Returns lockBoostMultiplier value, in `Basis Points`
    function lockBoostMultiplier() external view returns (uint256);

    /// @notice Returns how many other chains are supported
    function supportedChains() external view returns (uint256);

    /// @notice Returns whether a particular GETH chainId is supported
    /// ChainId => messagingHub address, 2 = supported; 1 = unsupported
    function supportedChainData(
        uint256 chainID
    ) external view returns (ChainData memory);

    // Address => chainID => Curvance identification information
    function getOmnichainOperators(
        address _address,
        uint256 chainID
    ) external view returns (OmnichainData memory);

    // Messaging specific ChainId => GETH comparable ChainId
    function messagingToGETHChainId(
        uint256 chainId
    ) external view returns (uint256);

    // GETH comparable ChainId => Messaging specific ChainId
    function GETHToMessagingChainId(
        uint256 chainId
    ) external view returns (uint256);

    /// @notice Returns whether the inputted address is an approved zapper
    function isZapper(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved swapper
    function isSwapper(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved veCVELocker
    function isVeCVELocker(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Gauge Controller
    function isGaugeController(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Harvester
    function isHarvester(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is a Lending Market
    function isLendingMarket(address _address) external view returns (bool);

    /// @notice Returns whether the inputted address is an Approved Endpoint
    function isEndpoint(address _address) external view returns (bool);
}
