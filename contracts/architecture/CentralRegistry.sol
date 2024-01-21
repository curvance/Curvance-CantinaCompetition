// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DENOMINATOR } from "contracts/libraries/Constants.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { ICentralRegistry, ChainData, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { IFeeAccumulator } from "contracts/interfaces/IFeeAccumulator.sol";
import { IWormhole } from "contracts/interfaces/external/wormhole/IWormhole.sol";
import { IWormholeRelayer } from "contracts/interfaces/external/wormhole/IWormholeRelayer.sol";
import { ICircleRelayer } from "contracts/interfaces/external/wormhole/ICircleRelayer.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/external/wormhole/ITokenBridgeRelayer.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CentralRegistry is ERC165 {
    /// CONSTANTS ///

    /// @notice Genesis Epoch timestamp.
    uint256 public immutable genesisEpoch;

    /// @notice Sequencer Uptime feed address for L2.
    address public immutable sequencer;

    /// @notice Address of fee token.
    address public immutable feeToken;

    /// @dev bytes4(keccak256(bytes("CentralRegistry__ParametersMisconfigured()")))
    uint256 internal constant _PARAMETERS_MISCONFIGURED_SELECTOR = 0xa5bb570d;

    /// @dev bytes4(keccak256(bytes("CentralRegistry__Unauthorized()")))
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xe675838a;

    /// STORAGE ///

    // DAO GOVERNANCE OPERATORS

    /// @notice DAO multisig.
    address public daoAddress;

    /// @notice DAO multisig, with time delay.
    address public timelock;

    /// @notice Multi-protocol multisig, for emergencies.
    address public emergencyCouncil;

    // CURVANCE TOKEN CONTRACTS

    /// @notice CVE contract address.
    address public cve;

    /// @notice veCVE contract address.
    address public veCVE;

    /// @notice CVE Call Option contract address.
    address public oCVE;

    // DAO CONTRACTS DATA

    /// @notice CVE Locker contract address.
    address public cveLocker;

    /// @notice This chains Protocol Messaging Hub contract address.
    address public protocolMessagingHub;

    /// @notice Oracle Router contract address.
    address public oracleRouter;

    /// @notice Fee Accumulator contract address.
    address public feeAccumulator;

    // CROSS-CHAIN MESSAGING DATA

    /// @notice Address of Wormhole core contract.
    IWormhole public wormholeCore;

    /// @notice Address of Wormhole Relayer.
    IWormholeRelayer public wormholeRelayer;

    /// @notice Address of Wormhole Circle Relayer.
    ICircleRelayer public circleRelayer;

    /// @notice Wormhole TokenBridgeRelayer.
    ITokenBridgeRelayer public tokenBridgeRelayer;

    // GELATO ADDRESSES

    /// @notice The address of gelato sponsor.
    address public gelatoSponsor;

    // PROTOCOL VALUES

    // Values are always set in `Basis Points`, any fees are converted to `WAD`
    // while multipliers stay in `DENOMINATOR` Fees:

    /// @notice Fee for compounding position vaults.
    uint256 public protocolCompoundFee = 100 * 1e14;

    /// @notice Fee on yield in position vaults.
    uint256 public protocolYieldFee = 1500 * 1e14;

    /// @notice Joint fee value so that we can perform one less external call
    ///         in position vault contracts.
    uint256 public protocolHarvestFee = protocolCompoundFee + protocolYieldFee;

    /// @notice Protocol Fee on leveraging.
    uint256 public protocolLeverageFee;

    // Multipliers:

    /// @notice Penalty multiplier for unlocking a veCVE lock early.
    uint256 public earlyUnlockPenaltyMultiplier;

    /// @notice Voting power multiplier for Continuous Lock Mode.
    uint256 public voteBoostMultiplier;

    /// @notice Gauge rewards multiplier for locking gauge emissions.
    uint256 public lockBoostMultiplier;

    // PROTOCOL VALUES DATA `WAD` set in `DENOMINATOR`.
    /// @notice Market Manager => Protocol Reserve Factor on interest generated
    mapping(address => uint256) public protocolInterestFactor;

    // DAO PERMISSION DATA

    mapping(address => bool) public hasDaoPermissions;
    mapping(address => bool) public hasElevatedPermissions;

    // MULTICHAIN CONFIGURATION DATA
    // We store this data redundantly so that we can quickly get whatever
    // output we need, with low gas overhead.

    /// @notice How many other chains are supported.
    uint256 public supportedChains;
    /// @notice Address array for all Curvance markets on this chain.
    address[] public marketManagers;

    /// @notice ChainId => 2 = supported; 1 = unsupported.
    mapping(uint256 => ChainData) public supportedChainData;

    /// @notice Address => chainID => Curvance identification information.
    mapping(address => mapping(uint256 => OmnichainData))
        public omnichainOperators;
    mapping(uint16 => uint256) public messagingToGETHChainId;
    mapping(uint256 => uint16) public GETHToMessagingChainId;

    // WORMHOLE CONTRACT MAPPINGS

    /// @notice Wormhole specific chain ID for evm chain ID.
    mapping(uint256 => uint16) public wormholeChainId;

    // DAO CONTRACT MAPPINGS

    mapping(address => bool) public isZapper;
    mapping(address => bool) public isSwapper;
    mapping(address => bool) public isVeCVELocker;
    mapping(address => bool) public isGaugeController;
    mapping(address => bool) public isHarvester;
    mapping(address => bool) public isMarketManager;
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
    event CoreContractSet(string indexed contractType, address newAddress);
    event NewCurvanceContract(string indexed contractType, address newAddress);
    event RemovedCurvanceContract(
        string indexed contractType,
        address removedAddress
    );
    event FeeTokenSet(address newAddress);
    event WormholeCoreSet(address newAddress);
    event WormholeRelayerSet(address newAddress);
    event CircleRelayerSet(address newAddress);
    event TokenBridgeRelayerSet(address newAddress);
    event GelatoSponsorSet(address newAddress);
    event NewChainAdded(uint256 chainId, address operatorAddress);
    event RemovedChain(uint256 chainId, address operatorAddress);

    /// ERRORS ///

    error CentralRegistry__InvalidFeeToken();
    error CentralRegistry__ParametersMisconfigured();
    error CentralRegistry__Unauthorized();

    /// CONSTRUCTOR ///

    constructor(
        address daoAddress_,
        address timelock_,
        address emergencyCouncil_,
        uint256 genesisEpoch_,
        address sequencer_,
        address feeToken_
    ) {
        if (feeToken_ == address(0)) {
            revert CentralRegistry__InvalidFeeToken();
        }

        if (daoAddress_ == address(0)) {
            daoAddress_ = msg.sender;
        }

        if (timelock_ == address(0)) {
            timelock_ = msg.sender;
        }

        if (emergencyCouncil_ == address(0)) {
            emergencyCouncil_ = msg.sender;
        }

        // Configure DAO permission data
        daoAddress = daoAddress_;
        timelock = timelock_;
        emergencyCouncil = emergencyCouncil_;

        // Provide base dao permissioning to `daoAddress`,
        // `timelock`, `emergencyCouncil`.
        hasDaoPermissions[daoAddress] = true;
        hasDaoPermissions[timelock] = true;
        hasDaoPermissions[emergencyCouncil] = true;

        // Provide elevated dao permissioning to `timelock`,
        // `emergencyCouncil`.
        hasElevatedPermissions[timelock] = true;
        hasElevatedPermissions[emergencyCouncil] = true;

        genesisEpoch = genesisEpoch_;
        sequencer = sequencer_;

        feeToken = feeToken_;

        emit OwnershipTransferred(address(0), daoAddress_);
        emit NewTimelockConfiguration(address(0), timelock_);
        emit EmergencyCouncilTransferred(address(0), emergencyCouncil_);
    }

    /// EXTERNAL FUNCTIONS ///

    function withdrawReservesMulti(address[] calldata dTokens) external {
        // Match permissioning check to normal withdrawReserves().
        _checkDaoPermissions();

        uint256 dTokenLength = dTokens.length;
        if (dTokenLength == 0) {
           _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        IMToken dToken;

        for(uint256 i; i < dTokenLength; ) {
            dToken = IMToken(dTokens[i++]);
            // Revert if somehow a misconfigured token made it in here.
            if (dToken.isCToken()) {
                _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
            }

            dToken.processWithdrawReserves();
        }
    }

    /// @notice Sets a new CVE contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newCVE The new address of cve.
    function setCVE(address newCVE) external {
        _checkElevatedPermissions();

        cve = newCVE;
        emit CoreContractSet("CVE", newCVE);
    }

    /// @notice Sets a new veCVE contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newVeCVE The new address of veCVE.
    function setVeCVE(address newVeCVE) external {
        _checkElevatedPermissions();

        veCVE = newVeCVE;
        emit CoreContractSet("VeCVE", newVeCVE);
    }

    /// @notice Sets a new oCVE contract address.
    /// @dev Only callable by a call with base DAO permissioning.
    /// @param newOCVE The new address of oCVE.
    function setOCVE(address newOCVE) external {
        // Lower permissioning on call option CVE,
        // since its only used initially in Curvance
        _checkDaoPermissions();

        oCVE = newOCVE;
        emit CoreContractSet("oCVE", newOCVE);
    }

    /// @notice Sets a new CVE locker contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newCVELocker The new address of cveLocker.
    function setCVELocker(address newCVELocker) external {
        _checkElevatedPermissions();

        cveLocker = newCVELocker;
        emit CoreContractSet("CVE Locker", newCVELocker);
    }

    /// @notice Sets a new protocol messaging hub contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newProtocolMessagingHub The new address of protocolMessagingHub.
    function setProtocolMessagingHub(
        address newProtocolMessagingHub
    ) external {
        _checkElevatedPermissions();

        protocolMessagingHub = newProtocolMessagingHub;

        // If the feeAccumulator is already set up,
        // notify it that the messaging hub has been updated.
        if (feeAccumulator != address(0)) {
            IFeeAccumulator(feeAccumulator).notifyUpdatedMessagingHub();
        }

        emit CoreContractSet(
            "Protocol Messaging Hub",
            newProtocolMessagingHub
        );
    }

    /// @notice Sets a new oracle router contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newOracleRouter The new address of oracleRouter.
    function setOracleRouter(address newOracleRouter) external {
        _checkElevatedPermissions();

        oracleRouter = newOracleRouter;
        emit CoreContractSet("Oracle Router", newOracleRouter);
    }

    /// @notice Sets a new fee hub contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newFeeAccumulator The new address of feeAccumulator.
    function setFeeAccumulator(address newFeeAccumulator) external {
        _checkElevatedPermissions();

        feeAccumulator = newFeeAccumulator;
        emit CoreContractSet("Fee Accumulator", newFeeAccumulator);
    }

    /// @notice Sets an address of WormholeCore contract.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newWormholeCore The new address of WormholeCore.
    function setWormholeCore(address newWormholeCore) external {
        _checkElevatedPermissions();

        wormholeCore = IWormhole(newWormholeCore);
        emit WormholeCoreSet(newWormholeCore);
    }

    /// @notice Sets an address of WormholeRelayer contract.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newWormholeRelayer The new address of wormholeRelayer.
    function setWormholeRelayer(address newWormholeRelayer) external {
        _checkElevatedPermissions();

        wormholeRelayer = IWormholeRelayer(newWormholeRelayer);
        emit WormholeRelayerSet(newWormholeRelayer);
    }

    /// @notice Sets an address of Wormhole CircleRelayer contract.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newCircleRelayer The new address of Wormhole CircleRelayer.
    function setCircleRelayer(address newCircleRelayer) external {
        _checkElevatedPermissions();

        circleRelayer = ICircleRelayer(newCircleRelayer);
        emit CircleRelayerSet(newCircleRelayer);
    }

    /// @notice Sets an address of Wormhole TokenBridgeRelayer contract.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newTokenBridgeRelayer The new address of Wormhole TokenBridgeRelayer.
    function setTokenBridgeRelayer(address newTokenBridgeRelayer) external {
        _checkElevatedPermissions();

        tokenBridgeRelayer = ITokenBridgeRelayer(newTokenBridgeRelayer);
        emit TokenBridgeRelayerSet(newTokenBridgeRelayer);
    }

    /// @notice Register wormhole specific chain IDs for evm chain IDs.
    /// @param chainIds EVM chain IDs.
    /// @param wormholeChainIds Wormhole specific chain IDs.
    function registerWormholeChainIDs(
        uint256[] calldata chainIds,
        uint16[] calldata wormholeChainIds
    ) external {
        _checkElevatedPermissions();

        uint256 numChainIds = chainIds.length;

        for (uint256 i; i < numChainIds; ++i) {
            wormholeChainId[chainIds[i]] = wormholeChainIds[i];
        }
    }

    /// @notice Sets an address of gelato sponsor.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newGelatoSponsor The new address of new gelato sponsor.
    function setGelatoSponsor(address newGelatoSponsor) external {
        _checkElevatedPermissions();

        gelatoSponsor = newGelatoSponsor;
        emit GelatoSponsorSet(newGelatoSponsor);
    }

    /// @notice Sets the fee from yield by Curvance DAO to use as gas
    ///         to compound rewards for users.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 5%.
    function setProtocolCompoundFee(uint256 value) external {
        _checkElevatedPermissions();

        if (value > 500) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config.
        protocolCompoundFee = _bpToWad(value);

        // Update vault harvest fee with new yield fee
        protocolHarvestFee = protocolYieldFee + _bpToWad(value);
    }

    /// @notice Sets the fee taken by Curvance DAO on all generated
    ///         by the protocol
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 20%
    function setProtocolYieldFee(uint256 value) external {
        _checkElevatedPermissions();

        if (value > 2000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config
        protocolYieldFee = _bpToWad(value);

        // Update vault harvest fee with new yield fee
        protocolHarvestFee = _bpToWad(value) + protocolCompoundFee;
    }

    /// @notice Sets the fee taken by Curvance DAO on leverage/deleverage
    ///         via position folding
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 2%
    function setProtocolLeverageFee(uint256 value) external {
        _checkElevatedPermissions();

        if (value > 200) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config
        protocolLeverageFee = _bpToWad(value);
    }

    /// @notice Sets the fee taken by Curvance DAO from interest generated
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 50%
    function setProtocolInterestRateFee(
        address market,
        uint256 value
    ) external {
        _checkElevatedPermissions();

        if (value > 5000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        if (!isMarketManager[market]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config
        protocolInterestFactor[market] = _bpToWad(value);
    }

    /// @notice Sets the early unlock penalty value for when users want to
    ///         unlock their veCVE early
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be between 30% and 90%
    function setEarlyUnlockPenaltyMultiplier(uint256 value) external {
        _checkElevatedPermissions();

        if (value > 9000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        if (value < 3000 && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        earlyUnlockPenaltyMultiplier = value;
    }

    /// @notice Sets the voting power boost received by locks using
    ///         Continuous Lock mode
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier
    function setVoteBoostMultiplier(uint256 value) external {
        _checkElevatedPermissions();

        if (value < DENOMINATOR && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        voteBoostMultiplier = value;
    }

    /// @notice Sets the emissions boost received by choosing
    ///         to lock emissions at veCVE
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier
    function setLockBoostMultiplier(uint256 value) external {
        _checkElevatedPermissions();

        if (value < DENOMINATOR && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        lockBoostMultiplier = value;
    }

    /// OWNERSHIP LOGIC

    function transferDaoOwnership(address newDaoAddress) external {
        _checkElevatedPermissions();

        address previousDaoAddress = daoAddress;
        daoAddress = newDaoAddress;

        delete hasDaoPermissions[previousDaoAddress];

        hasDaoPermissions[newDaoAddress] = true;

        emit OwnershipTransferred(previousDaoAddress, newDaoAddress);
    }

    function migrateTimelockConfiguration(address newTimelock) external {
        _checkEmergencyCouncilPermissions();

        address previousTimelock = timelock;
        timelock = newTimelock;

        // Delete permission data
        delete hasDaoPermissions[previousTimelock];
        delete hasElevatedPermissions[previousTimelock];

        // Add new permission data
        hasDaoPermissions[newTimelock] = true;
        hasElevatedPermissions[newTimelock] = true;

        emit NewTimelockConfiguration(previousTimelock, newTimelock);
    }

    function transferEmergencyCouncil(address newEmergencyCouncil) external {
        _checkEmergencyCouncilPermissions();

        address previousEmergencyCouncil = emergencyCouncil;
        emergencyCouncil = newEmergencyCouncil;

        // Delete permission data
        delete hasDaoPermissions[previousEmergencyCouncil];
        delete hasElevatedPermissions[previousEmergencyCouncil];

        // Add new permission data
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
        address cveAddress,
        uint256 chainId,
        uint256 sourceAux,
        uint256 destinationAux,
        uint16 messagingChainId
    ) external {
        _checkElevatedPermissions();

        if (
            omnichainOperators[newOmnichainOperator][chainId].isAuthorized == 2
        ) {
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
            cveAddress: cveAddress
        });
        messagingToGETHChainId[messagingChainId] = chainId;
        GETHToMessagingChainId[chainId] = messagingChainId;
        supportedChains++;
        omnichainOperators[newOmnichainOperator][chainId] = OmnichainData({
            isAuthorized: 2,
            messagingChainId: messagingChainId,
            cveAddress: cveAddress
        });

        emit NewChainAdded(chainId, newOmnichainOperator);
    }

    /// @notice removes
    function removeChainSupport(
        address currentOmnichainOperator,
        uint256 chainId
    ) external {
        // Lower permissioning on removing chains as it only
        // mitigates risk to the system
        _checkDaoPermissions();

        OmnichainData storage operatorToRemove = omnichainOperators[
            currentOmnichainOperator
        ][chainId];
        // Validate that `currentOmnichainOperator` is currently supported.
        if (
            omnichainOperators[currentOmnichainOperator][chainId]
                .isAuthorized < 2
        ) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Validate that `chainId` is currently supported.
        if (supportedChainData[chainId].isSupported < 2) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Remove chain support from protocol
        supportedChainData[chainId].isSupported = 1;
        // Remove operator support from protocol
        operatorToRemove.isAuthorized = 1;
        // Decrease supportedChains
        supportedChains--;
        // Remove messagingChainId <> GETH chainId mapping table references
        delete GETHToMessagingChainId[
            messagingToGETHChainId[operatorToRemove.messagingChainId]
        ];
        delete messagingToGETHChainId[operatorToRemove.messagingChainId];

        emit RemovedChain(chainId, currentOmnichainOperator);
    }

    /// CONTRACT MAPPING LOGIC

    function addZapper(address newZapper) external {
        _checkElevatedPermissions();

        if (isZapper[newZapper]) {
            // Zapper already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isZapper[newZapper] = true;

        emit NewCurvanceContract("Zapper", newZapper);
    }

    function removeZapper(address currentZapper) external {
        _checkElevatedPermissions();

        if (!isZapper[currentZapper]) {
            // Not a Zapper
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isZapper[currentZapper];

        emit RemovedCurvanceContract("Zapper", currentZapper);
    }

    function addSwapper(address newSwapper) external {
        _checkElevatedPermissions();

        if (isSwapper[newSwapper]) {
            // Swapper already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isSwapper[newSwapper] = true;

        emit NewCurvanceContract("Swapper", newSwapper);
    }

    function removeSwapper(address currentSwapper) external {
        _checkElevatedPermissions();

        if (!isSwapper[currentSwapper]) {
            // Not a Swapper
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isSwapper[currentSwapper];

        emit RemovedCurvanceContract("Swapper", currentSwapper);
    }

    function addVeCVELocker(address newVeCVELocker) external {
        _checkElevatedPermissions();

        if (isVeCVELocker[newVeCVELocker]) {
            // VeCVE locker already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isVeCVELocker[newVeCVELocker] = true;

        emit NewCurvanceContract("VeCVELocker", newVeCVELocker);
    }

    function removeVeCVELocker(address currentVeCVELocker) external {
        _checkElevatedPermissions();

        if (!isVeCVELocker[currentVeCVELocker]) {
            // Not a VeCVE locker
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isVeCVELocker[currentVeCVELocker];

        emit RemovedCurvanceContract("VeCVELocker", currentVeCVELocker);
    }

    function addGaugeController(address newGaugeController) external {
        _checkElevatedPermissions();

        if (isGaugeController[newGaugeController]) {
            // Gauge Controller already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isGaugeController[newGaugeController] = true;

        emit NewCurvanceContract("Gauge Controller", newGaugeController);
    }

    function removeGaugeController(address currentGaugeController) external {
        _checkElevatedPermissions();

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

    function addHarvester(address newHarvester) external {
        _checkElevatedPermissions();

        if (isHarvester[newHarvester]) {
            // Harvestor already added
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isHarvester[newHarvester] = true;

        emit NewCurvanceContract("Harvestor", newHarvester);
    }

    function removeHarvester(address currentHarvester) external {
        _checkElevatedPermissions();

        if (!isHarvester[currentHarvester]) {
            // Not a Harvestor
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isHarvester[currentHarvester];

        emit RemovedCurvanceContract("Harvestor", currentHarvester);
    }

    /// @notice Add a new market manager and associated fee configurations.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      and 50% for interest generated.
    /// @param newMarketManager The address of new market manager to be added.
    /// @param marketInterestFactor The interest factor associated with
    ///                             the market manager.
    function addMarketManager(
        address newMarketManager,
        uint256 marketInterestFactor
    ) external {
        _checkElevatedPermissions();

        // Validate that `newMarketManager` is not already added.
        if (isMarketManager[newMarketManager]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Ensure that `newMarketManager` is a market manager.
        if (
            !ERC165Checker.supportsInterface(
                newMarketManager,
                type(IMarketManager).interfaceId
            )
        ) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Validate that desired interest factored is within
        // acceptable bounds.
        if (marketInterestFactor > 5000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isMarketManager[newMarketManager] = true;
        // We store supported markets semi redundantly for offchain querying.
        marketManagers.push(newMarketManager);
        protocolInterestFactor[newMarketManager] = _bpToWad(
            marketInterestFactor
        );

        emit NewCurvanceContract("Market Manager", newMarketManager);
    }

    /// @notice Remove a current market manager from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param currentMarketManager The address of the market manager
    ///                             to be removed.
    function removeMarketManager(address currentMarketManager) external {
        _checkElevatedPermissions();

        // Validate that `newMarketManager` is currently supported.
        if (!isMarketManager[currentMarketManager]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isMarketManager[currentMarketManager];

        // Cache market list.
        uint256 numMarkets = marketManagers.length;
        uint256 marketIndex = numMarkets;

        for (uint256 i; i < numMarkets; ++i) {
            if (marketManagers[i] == currentMarketManager) {
                marketIndex = i;
                break;
            }
        }

        // Validate we found the market and remove 1 from numMarkets
        // so it corresponds to last element index now (starting at index 0).
        // This is an additional runtime invariant check for extra security.
        if (marketIndex >= numMarkets--) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Copy last `marketManagers` slot to `marketIndex` slot.
        marketManagers[marketIndex] = marketManagers[numMarkets];
        // Remove the last element to remove `currentMarketManager`
        // from marketManagers list.
        marketManagers.pop();

        emit RemovedCurvanceContract("Market Manager", currentMarketManager);
    }

    /// @notice Add a new crosschain endpoint.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param newEndpoint The address of the new crosschain endpoint
    ///                    to be added.
    function addEndpoint(address newEndpoint) external {
        _checkElevatedPermissions();

        // Validate that `newEndpoint` is not currently supported.
        if (isEndpoint[newEndpoint]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isEndpoint[newEndpoint] = true;

        emit NewCurvanceContract("Endpoint", newEndpoint);
    }

    /// @notice Removes a current crosschain endpoint.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param currentEndpoint The address of the crosschain endpoint
    ///                        to be removed.
    function removeEndpoint(address currentEndpoint) external {
        _checkElevatedPermissions();

        // Validate that `currentEndpoint` is currently supported.
        if (!isEndpoint[currentEndpoint]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isEndpoint[currentEndpoint];

        emit RemovedCurvanceContract("Endpoint", currentEndpoint);
    }

    function getOmnichainOperators(
        address _address,
        uint256 chainID
    ) external view returns (OmnichainData memory) {
        return omnichainOperators[_address][chainID];
    }

    /// PUBLIC FUNCTIONS ///

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ICentralRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Multiplies `value` by 1e14 to convert it from `basis points`
    ///         to WAD.
    /// @dev Internal helper function for easily converting between scalars.
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        return value * 100000000000000;
    }

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkEmergencyCouncilPermissions() internal view {
        if (msg.sender != emergencyCouncil) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!hasDaoPermissions[msg.sender]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!hasElevatedPermissions[msg.sender]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }
}
