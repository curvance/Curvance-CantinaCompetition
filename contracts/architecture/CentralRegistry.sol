// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165 } from "contracts/libraries/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ICentralRegistry, ChainData, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";

contract CentralRegistry is ERC165 {
    /// CONSTANTS ///

    uint256 public constant DENOMINATOR = 10000; // Scalar for math
    /// `bytes4(keccak256(bytes("CentralRegistry_ParametersMisconfigured()")))`
    uint256 internal constant _PARAMETERS_MISCONFIGURED_SELECTOR = 0x6fc38aea;
    /// `bytes4(keccak256(bytes("CentralRegistry_Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x88f093e;
    uint256 public immutable genesisEpoch; // Genesis Epoch timestamp

    /// STORAGE ///

    /// DAO GOVERNANCE OPERATORS
    address public daoAddress; // DAO multisig
    address public timelock; // DAO multisig, with time delay
    address public emergencyCouncil; // Multi-protocol multisig, for emergencies

    /// CURVANCE TOKEN CONTRACTS
    address public CVE; // CVE contract address
    address public veCVE; // veCVE contract address
    address public callOptionCVE; // CVE Call Option contract address

    /// DAO CONTRACTS DATA
    address public cveLocker; // CVE Locker contract address
    address public protocolMessagingHub; // This chains Protocol Messaging Hub contract address
    address public priceRouter; // Price Router contract address
    address public zroAddress; // ZRO contract address for layerzero
    address public feeAccumulator; // Fee Accumulator contract address

    /// PROTOCOL VALUES in `EXP_SCALE` set in `DENOMINATOR`
    uint256 public protocolCompoundFee = 100 * 1e14; // Fee for compounding position vaults
    uint256 public protocolYieldFee = 1500 * 1e14; // Fee on yield in position vaults
    /// Joint fee value so that we can perform one less external call in position vault contracts
    uint256 public protocolHarvestFee = protocolCompoundFee + protocolYieldFee;
    uint256 public protocolLeverageFee; // Protocol Fee on leveraging
    uint256 public earlyUnlockPenaltyValue; // Penalty Fee for unlocking from veCVE early
    uint256 public voteBoostValue; // Voting power bonus for Continuous Lock Mode
    uint256 public lockBoostValue; // Rewards bonus for Continuous Lock Mode

    /// PROTOCOL VALUES DATA `EXP_SCALE` set in `DENOMINATOR`
    /// @notice Lending Market => Protocol Reserve Factor on interest generated
    mapping(address => uint256) public protocolInterestFactor;

    /// DAO PERMISSION DATA
    mapping(address => bool) public hasDaoPermissions;
    mapping(address => bool) public hasElevatedPermissions;

    /// MULTICHAIN CONFIGURATION DATA
    /// We store this data redundantly so that we can quickly get whatever output we need,
    /// with low gas overhead
    uint256 public supportedChains; // How many other chains are supported
    mapping(uint256 => ChainData) public supportedChainData; // ChainId => 2 = supported; 1 = unsupported
    /// Address => chainID => Curvance identification information
    mapping(address => mapping (uint256 => OmnichainData)) public omnichainOperators;
    mapping(uint256 => uint256) public messagingToGETHChainId;
    mapping(uint256 => uint256) public GETHToMessagingChainId;

    /// DAO CONTRACT MAPPINGS
    mapping(address => bool) public isZapper;
    mapping(address => bool) public isSwapper;
    mapping(address => bool) public isVeCVELocker;
    mapping(address => bool) public isGaugeController;
    mapping(address => bool) public isHarvester;
    mapping(address => bool) public isLendingMarket;
    mapping(address => bool) public isEndpoint;

    /// EVENTS ///

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event NewTimelockConfiguration(
        address indexed previousTimelock,
        address indexed newTimelock
    );
    event EmergencyCouncilTransferred(
        address indexed previousEmergencyCouncil,
        address indexed newEmergencyCouncil
    );

    event NewCurvanceContract(string indexed contractType, address newAddress);
    event RemovedCurvanceContract(
        string indexed contractType,
        address removedAddress
    );

    event NewChainAdded(uint256 chainId, address operatorAddress);
    event RemovedChain(uint256 chainId, address operatorAddress);

    /// ERRORS ///
    error CentralRegistry_ParametersMisconfigured();
    error CentralRegistry_Unauthorized();

    /// MODIFIERS ///

    modifier onlyDaoManager() {
        if (msg.sender != daoAddress) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
        _;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
        _;
    }

    modifier onlyEmergencyCouncil() {
        if (msg.sender != emergencyCouncil) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
        _;
    }

    modifier onlyDaoPermissions() {
        if (!hasDaoPermissions[msg.sender]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
        _;
    }

    modifier onlyElevatedPermissions() {
        if (!hasElevatedPermissions[msg.sender]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
        _;
    }

    /// CONSTRUCTOR ///

    constructor(
        address daoAddress_,
        address timelock_,
        address emergencyCouncil_,
        uint256 genesisEpoch_
    ) {
        if (daoAddress_ == address(0)) {
            daoAddress_ = msg.sender;
        }

        if (timelock_ == address(0)) {
            timelock_ = msg.sender;
        }

        if (emergencyCouncil_ == address(0)) {
            emergencyCouncil_ = msg.sender;
        }

        /// Configure DAO permission data
        daoAddress = daoAddress_;
        timelock = timelock_;
        emergencyCouncil = emergencyCouncil_;

        hasDaoPermissions[daoAddress] = true;
        hasDaoPermissions[timelock] = true;
        hasDaoPermissions[emergencyCouncil] = true;

        hasElevatedPermissions[timelock] = true;
        hasElevatedPermissions[emergencyCouncil] = true;

        genesisEpoch = genesisEpoch_;

        emit OwnershipTransferred(address(0), daoAddress_);
        emit NewTimelockConfiguration(address(0), timelock_);
        emit EmergencyCouncilTransferred(address(0), emergencyCouncil_);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Sets a new CVE contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    function setCVE(address newCVE) external onlyElevatedPermissions {
        CVE = newCVE;
    }

    /// @notice Sets a new veCVE contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    function setVeCVE(address newVeCVE) external onlyElevatedPermissions {
        veCVE = newVeCVE;
    }

    /// @notice Sets a new CVE contract address
    /// @dev Only callable by the DAO
    function setCallOptionCVE(
        address newCallOptionCVE
    ) external onlyDaoPermissions {
        callOptionCVE = newCallOptionCVE;
    }

    /// @notice Sets a new CVE locker contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    function setCVELocker(
        address newCVELocker
    ) external onlyElevatedPermissions {
        cveLocker = newCVELocker;
    }

    /// @notice Sets a new protocol messaging hub contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    function setProtocolMessagingHub(
        address newProtocolMessagingHub
    ) external onlyElevatedPermissions {
        protocolMessagingHub = newProtocolMessagingHub;
    }

    /// @notice Sets a new price router contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    function setPriceRouter(
        address newPriceRouter
    ) external onlyElevatedPermissions {
        priceRouter = newPriceRouter;
    }

    /// @notice Sets a new ZRO contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    function setZroAddress(
        address newZroAddress
    ) external onlyElevatedPermissions {
        zroAddress = newZroAddress;
    }

    /// @notice Sets a new fee hub contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    function setFeeAccumulator(
        address newFeeAccumulator
    ) external onlyElevatedPermissions {
        feeAccumulator = newFeeAccumulator;
    }

    /// @notice Sets the fee from yield by Curvance DAO to use as gas
    ///         to compound rewards for users
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 5%
    function setProtocolCompoundFee(
        uint256 value
    ) external onlyElevatedPermissions {
        if (value > 500) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        /// CompoundFee is represented in 1e16 format
        /// So we need to multiply by 1e14 to format properly
        /// from basis points to %
        protocolCompoundFee = value * 1e14;

        /// Update vault harvest fee with new yield fee
        protocolHarvestFee = protocolYieldFee + (value * 1e14);
    }

    /// @notice Sets the fee taken by Curvance DAO on all generated
    ///         by the protocol
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 20%
    function setProtocolYieldFee(
        uint256 value
    ) external onlyElevatedPermissions {
        if (value > 2000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        /// YieldFee is represented in 1e16 format
        /// So we need to multiply by 1e14 to format properly
        /// from basis points to %
        protocolYieldFee = value * 1e14;

        /// Update vault harvest fee with new yield fee
        protocolHarvestFee = (value * 1e14) + protocolCompoundFee;
    }

    /// @notice Sets the fee taken by Curvance DAO on leverage/deleverage
    ///         via position folding
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 1%
    function setProtocolLeverageFee(
        uint256 value
    ) external onlyElevatedPermissions {
        if (value > 100) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        protocolLeverageFee = value;
    }

    /// @notice Sets the fee taken by Curvance DAO from interest generated
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 50%
    function setProtocolInterestRateFee(
        address market,
        uint256 value
    ) external onlyElevatedPermissions {
        if (value > 5000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        if (!isLendingMarket[market]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        /// Interest Rate fee is represented as 1e16 format
        /// So we need to multiply by 1e14 to format properly
        /// from basis points to %
        protocolInterestFactor[market] = value * 1e14;
    }

    /// @notice Sets the early unlock penalty value for when users want to
    ///         unlock their veCVE early
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be between 30% and 90%
    function setEarlyUnlockPenaltyValue(
        uint256 value
    ) external onlyElevatedPermissions {
        if ((value > 9000 || value < 3000) && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        earlyUnlockPenaltyValue = value;
    }

    /// @notice Sets the voting power boost received by locks using
    ///         Continuous Lock mode
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier
    function setVoteBoostValue(
        uint256 value
    ) external onlyElevatedPermissions {
        if (value < DENOMINATOR && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        voteBoostValue = value;
    }

    /// @notice Sets the emissions boost received by choosing
    ///         to lock emissions at veCVE
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier
    function setLockBoostValue(
        uint256 value
    ) external onlyElevatedPermissions {
        if (value < DENOMINATOR && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        lockBoostValue = value;
    }

    /// OWNERSHIP LOGIC

    function transferDaoOwnership(
        address newDaoAddress
    ) external onlyElevatedPermissions {
        address previousDaoAddress = daoAddress;
        daoAddress = newDaoAddress;

        delete hasDaoPermissions[previousDaoAddress];

        hasDaoPermissions[newDaoAddress] = true;

        emit OwnershipTransferred(previousDaoAddress, newDaoAddress);
    }

    function migrateTimelockConfiguration(
        address newTimelock
    ) external onlyEmergencyCouncil {
        address previousTimelock = timelock;
        timelock = newTimelock;

        /// Delete permission data
        delete hasDaoPermissions[previousTimelock];
        delete hasElevatedPermissions[previousTimelock];

        /// Add new permission data
        hasDaoPermissions[newTimelock] = true;
        hasElevatedPermissions[newTimelock] = true;

        emit NewTimelockConfiguration(previousTimelock, newTimelock);
    }

    function transferEmergencyCouncil(
        address newEmergencyCouncil
    ) external onlyEmergencyCouncil {
        address previousEmergencyCouncil = emergencyCouncil;
        emergencyCouncil = newEmergencyCouncil;

        /// Delete permission data
        delete hasDaoPermissions[previousEmergencyCouncil];
        delete hasElevatedPermissions[previousEmergencyCouncil];

        /// Add new permission data
        hasDaoPermissions[newEmergencyCouncil] = true;
        hasElevatedPermissions[newEmergencyCouncil] = true;

        emit EmergencyCouncilTransferred(
            previousEmergencyCouncil,
            newEmergencyCouncil
        );
    }

    /// MULTICHAIN SUPPORT LOGIC

    function addChainSupport(
        address newOmnichainOperator,
        address messagingHub,
        bytes calldata cveAddress,
        uint256 chainId,
        uint256 sourceAux,
        uint256 destinationAux,
        uint256 messagingChainId
    ) external onlyElevatedPermissions {
        if (omnichainOperators[newOmnichainOperator][chainId].isAuthorized == 2) {
            // Chain Operator already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        if (supportedChainData[chainId].isSupported == 2) {
            // Chain already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        supportedChainData[chainId] = ChainData({
            isSupported: 2,
            messagingHub: messagingHub,
            asSourceAux: sourceAux,
            asDestinationAux: destinationAux,
            cveAddress: bytes32(cveAddress)
        });
        messagingToGETHChainId[messagingChainId] = chainId;
        GETHToMessagingChainId[chainId] = messagingChainId;
        supportedChains++;
        omnichainOperators[newOmnichainOperator][chainId] = OmnichainData({
            isAuthorized: 2,
            chainId: chainId,
            messagingChainId: messagingChainId,
            cveAddress: cveAddress
        });

        emit NewChainAdded(chainId, newOmnichainOperator);
    }

    /// @notice removes
    function removeChainSupport(
        address currentOmnichainOperator,
        uint256 chainId
    ) external onlyDaoPermissions {
        OmnichainData storage operatorToRemove = omnichainOperators[
            currentOmnichainOperator
        ][chainId];
        if (omnichainOperators[currentOmnichainOperator][chainId].isAuthorized < 2) {
            // Operator unsupported
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        if (supportedChainData[operatorToRemove.chainId].isSupported < 2) {
            // Chain already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Remove chain support from protocol
        supportedChainData[operatorToRemove.chainId].isSupported = 1;
        // Remove operator support from protocol
        operatorToRemove.isAuthorized = 1;
        // Decrease supportedChains
        supportedChains--;
        // Remove messagingChainId <> GETH chainId mapping table references
        delete GETHToMessagingChainId[
            messagingToGETHChainId[operatorToRemove.messagingChainId]
        ];
        delete messagingToGETHChainId[operatorToRemove.messagingChainId];

        emit RemovedChain(operatorToRemove.chainId, currentOmnichainOperator);
    }

    /// CONTRACT MAPPING LOGIC

    function addZapper(address newZapper) external onlyElevatedPermissions {
        if (isZapper[newZapper]) {
            // Zapper already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isZapper[newZapper] = true;

        emit NewCurvanceContract("Zapper", newZapper);
    }

    function removeZapper(
        address currentZapper
    ) external onlyElevatedPermissions {
        if (!isZapper[currentZapper]) {
            // Not a Zapper
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isZapper[currentZapper];

        emit RemovedCurvanceContract("Zapper", currentZapper);
    }

    function addSwapper(address newSwapper) external onlyElevatedPermissions {
        if (isSwapper[newSwapper]) {
            // Swapper already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isSwapper[newSwapper] = true;

        emit NewCurvanceContract("Swapper", newSwapper);
    }

    function removeSwapper(
        address currentSwapper
    ) external onlyElevatedPermissions {
        if (!isSwapper[currentSwapper]) {
            // Not a Swapper
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isSwapper[currentSwapper];

        emit RemovedCurvanceContract("Swapper", currentSwapper);
    }

    function addVeCVELocker(
        address newVeCVELocker
    ) external onlyElevatedPermissions {
        if (isVeCVELocker[newVeCVELocker]) {
            // VeCVE locker already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isVeCVELocker[newVeCVELocker] = true;

        emit NewCurvanceContract("VeCVELocker", newVeCVELocker);
    }

    function removeVeCVELocker(
        address currentVeCVELocker
    ) external onlyElevatedPermissions {
        if (!isVeCVELocker[currentVeCVELocker]) {
            // Not a VeCVE locker
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isVeCVELocker[currentVeCVELocker];

        emit RemovedCurvanceContract("VeCVELocker", currentVeCVELocker);
    }

    function addGaugeController(
        address newGaugeController
    ) external onlyElevatedPermissions {
        if (isGaugeController[newGaugeController]) {
            // Gauge Controller already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isGaugeController[newGaugeController] = true;

        emit NewCurvanceContract("Gauge Controller", newGaugeController);
    }

    function removeGaugeController(
        address currentGaugeController
    ) external onlyElevatedPermissions {
        if (!isGaugeController[currentGaugeController]) {
            // Not a Gauge Controller
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isGaugeController[currentGaugeController];

        emit RemovedCurvanceContract(
            "Gauge Controller",
            currentGaugeController
        );
    }

    function addHarvester(
        address newHarvester
    ) external onlyElevatedPermissions {
        if (isHarvester[newHarvester]) {
            // Harvestor already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isHarvester[newHarvester] = true;

        emit NewCurvanceContract("Harvestor", newHarvester);
    }

    function removeHarvester(
        address currentHarvester
    ) external onlyElevatedPermissions {
        if (!isHarvester[currentHarvester]) {
            // Not a Harvestor
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isHarvester[currentHarvester];

        emit RemovedCurvanceContract("Harvestor", currentHarvester);
    }

    /// @notice Add a new lending market and associated fee configurations.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      and 50% for interest generated
    /// @param newLendingMarket The address of the new lending market to be added.
    /// @param marketInterestFactor The interest factor associated with the lending market.
    function addLendingMarket(
        address newLendingMarket,
        uint256 marketInterestFactor
    ) external onlyElevatedPermissions {
        if (isLendingMarket[newLendingMarket]) {
            // Lending market already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Ensure that lending market parameter is a lending market
        if (
            !ERC165Checker.supportsInterface(
                newLendingMarket,
                type(ILendtroller).interfaceId
            )
        ) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        if (marketInterestFactor > 5000) {
            /// Fee too high
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isLendingMarket[newLendingMarket] = true;
        protocolInterestFactor[newLendingMarket] = marketInterestFactor;

        emit NewCurvanceContract("Lending Market", newLendingMarket);
    }

    /// @notice Remove a current lending market from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    /// @param currentLendingMarket The address of the lending market to be removed.
    function removeLendingMarket(
        address currentLendingMarket
    ) external onlyElevatedPermissions {
        if (!isLendingMarket[currentLendingMarket]) {
            // Not a Lending market
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isLendingMarket[currentLendingMarket];

        emit RemovedCurvanceContract("Lending Market", currentLendingMarket);
    }

    /// @notice Add a new crosschain endpoint.
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    /// @param newEndpoint The address of the new crosschain endpoint to be added.
    function addEndpoint(
        address newEndpoint
    ) external onlyElevatedPermissions {
        if (isEndpoint[newEndpoint]) {
            // Endpoint already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isEndpoint[newEndpoint] = true;

        emit NewCurvanceContract("Endpoint", newEndpoint);
    }

    /// @notice Removes a current crosschain endpoint.
    /// @dev Only callable on a 7 day delay or by the Emergency Council
    /// @param currentEndpoint The address of the crosschain endpoint to be removed.
    function removeEndpoint(
        address currentEndpoint
    ) external onlyElevatedPermissions {
        if (!isEndpoint[currentEndpoint]) {
            // Not an Endpoint
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isEndpoint[currentEndpoint];

        emit RemovedCurvanceContract("Endpoint", currentEndpoint);
    }

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ICentralRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
