// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DENOMINATOR } from "contracts/libraries/Constants.sol";

import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { ICentralRegistry, ChainData, OmnichainData } from "contracts/interfaces/ICentralRegistry.sol";
import { ITimelock } from "contracts/interfaces/ITimelock.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { IFeeAccumulator } from "contracts/interfaces/IFeeAccumulator.sol";
import { IWormhole } from "contracts/interfaces/external/wormhole/IWormhole.sol";
import { IWormholeRelayer } from "contracts/interfaces/external/wormhole/IWormholeRelayer.sol";
import { ITokenMessenger } from "contracts/interfaces/external/wormhole/ITokenMessenger.sol";
import { ITokenBridge } from "contracts/interfaces/external/wormhole/ITokenBridge.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance DAO Central Registry.
/// @notice Manages permissions and protocol contract registration
///         within the Curvance Protocol.
/// @dev The Central Registry acts a single source of truth for the Curvance
///      Protocol. This covers everything from multichain operations, to
///      contract locations, to protocol fees, to protocol multipliers
///      associated with various actions.
///
///      Permissions inside Curvance has two tiers:
///      - Standard DAO permissions: This is associated with actions that
///        reduce risk inside the Curvance system, or need to continually
///        managed by the DAO elected operating team.
///      - Elevated DAO permissions: This is associated with actions that
///        increase risk inside the Curvance system, the most sensitive of
///        controls. This requires a 7-day delay from the DAO elected
///        operating team for any action, or the "Emergency Council" made up
///        of both Curvance Collective members and external stakeholders.
///     
///      All values inside Curvance are entered in basis point form. However,
///      Fees are recorded internally in `WAD` format, or 1e18, rather than 
///      basis points, or 1e4. This is for greater precision in computations.
///      As a result, you will see multiplier values stored in 1e4 form,
///      and fees stored in 1e18 form. 
///
///      The Central Registry also manages the delegation system, creating
///      a new primitive as an alternative to the standard approval system.
///      Users can "delegate" specific actions or contracts to any address.
///      Providing that address authority on behalf of the user in the
///      contract. Approvals can also be mass revoked via the "approval index"
///      system. By incrementing one's approval index, a user can revoke all
///      approved address' delegation privileges at the same time.
///
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

    // DAO CONTRACTS DATA

    /// @notice CVE Locker contract address.
    address public cveLocker;
    /// @notice This chain's Protocol Messaging Hub contract address.
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

    /// @notice Address of Circle Token Messenger.
    ITokenMessenger public circleTokenMessenger;

    /// @notice Wormhole TokenBridge.
    ITokenBridge public tokenBridge;

    // GELATO ADDRESSES

    /// @notice The address of gelato sponsor.
    address public gelatoSponsor;

    // PROTOCOL FEES

    // Values are always set in `Basis Points` (1e4), fee values are converted
    // and stored in `WAD` while multipliers stay in `DENOMINATOR`.

    /// @notice Fee on yield generated for compounding vaults.
    uint256 public protocolCompoundFee = 100 * 1e14;
    /// @notice Fee on yield generated in vaults distributed to veCVE lockers.
    uint256 public protocolYieldFee = 1500 * 1e14;
    /// @notice Joint fee value so that we can perform one less external call
    ///         in vault contracts.
    uint256 public protocolHarvestFee = protocolCompoundFee + protocolYieldFee;
    /// @notice Protocol fee on leverage usage.
    uint256 public protocolLeverageFee;

    // ACTION MULTIPLIERS

    /// @notice Penalty multiplier for unlocking a veCVE lock early.
    uint256 public earlyUnlockPenaltyMultiplier;
    /// @notice Voting power multiplier for Continuous Lock mode.
    uint256 public voteBoostMultiplier;
    /// @notice Gauge rewards multiplier for locking gauge emissions.
    uint256 public lockBoostMultiplier;

    // PROTOCOL MONEY MARKET FEES

    /// @notice Debt token fee on interest generated.
    /// @dev Market Manager => Protocol Interest Factor, in `WAD`.
    mapping(address => uint256) public protocolInterestFactor;

    /// USER DELEGATION ///

    /// @notice A User's approval index acts as a way for users to manage
    ///         their delegatee's status across Curvance.
    /// @dev By incrementing their approval index, a user's delegates will all
    ///      have their delegation authority revoked across all Curvance
    ///      contracts.
    ///      User => Approval Index.
    mapping(address => uint256) public userApprovalIndex;

    /// @notice Whether a user wants to allow new delegating to be disabled.
    /// @dev User => Has new delegation  disabled.
    mapping(address => bool) public delegatingDisabled;

    // DAO PERMISSION DATA

    /// @notice Whether an address has DAO permissioning or not.
    /// @dev Address => DAO permission status.
    mapping(address => bool) public hasDaoPermissions;
    /// @notice Whether an address has Elevated DAO permissioning or not.
    /// @dev Address => Elevated DAO permission status.
    mapping(address => bool) public hasElevatedPermissions;

    // MULTICHAIN CONFIGURATION DATA

    // We store this data redundantly so that we can quickly get whatever
    // output we need, with low gas overhead.

    /// @notice Number of chains supported.
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

    // WORMHOLE/CCTP MAPPINGS

    /// @notice Wormhole specific chain ID for evm chain ID.
    mapping(uint256 => uint16) public wormholeChainId;

    /// @notice CCTP domain for evm chain ID.
    mapping(uint256 => uint32) public cctpDomain;

    // DAO CONTRACT MAPPINGS

    mapping(address => bool) public isZapper;
    mapping(address => bool) public isSwapper;
    mapping(address => bool) public isVeCVELocker;
    mapping(address => bool) public isGaugeController;
    mapping(address => bool) public isHarvester;
    mapping(address => bool) public isMarketManager;
    mapping(address => bool) public isEndpoint;
    mapping(address => address) public externalCallDataChecker;

    /// EVENTS ///

    event FeeSet(string indexed fee, uint256 newFee);
    event InterestFeeSet(address indexed market, uint256 newFee);
    event MultiplierSet(string indexed multiplier, uint256 newMultiplier);
    event ApprovalIndexIncremented(address indexed user, uint256 newIndex);
    event DelegableStatusSet(address indexed user, bool delegable);
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
    event CircleTokenMessengerSet(address newAddress);
    event WormholeChainIDsSet(uint256[] chainIds, uint16[] wormholeChainIds);
    event CCTPDomainsSet(uint256[] chainIds, uint32[] cctpDomains);
    event TokenBridgeSet(address newAddress);
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

        // Configure DAO permission data.
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

    /// @notice Withdraws all protocol reserve fees from a dToken
    ///         from interest generated and liquidations.
    /// @param dTokens Array of dToken addresses to withdraw fees from.
    function withdrawReservesMulti(address[] calldata dTokens) external {
        // Match permissioning check to normal withdrawReserves().
        _checkDaoPermissions();

        uint256 dTokenLength = dTokens.length;
        if (dTokenLength == 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        IMToken dToken;

        for (uint256 i; i < dTokenLength; ) {
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
    ///      Emits a {CoreContractSet} event.
    /// @param newCVE The new address of cve.
    function setCVE(address newCVE) external {
        _checkElevatedPermissions();

        cve = newCVE;
        emit CoreContractSet("CVE", newCVE);
    }

    /// @notice Sets a new veCVE contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {CoreContractSet} event.
    /// @param newVeCVE The new address of veCVE.
    function setVeCVE(address newVeCVE) external {
        _checkElevatedPermissions();

        veCVE = newVeCVE;
        emit CoreContractSet("VeCVE", newVeCVE);
    }

    /// @notice Sets a new CVE locker contract address
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {CoreContractSet} event.
    /// @param newCVELocker The new address of cveLocker.
    function setCVELocker(address newCVELocker) external {
        _checkElevatedPermissions();

        cveLocker = newCVELocker;
        emit CoreContractSet("CVE Locker", newCVELocker);
    }

    /// @notice Sets a new protocol messaging hub contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {CoreContractSet} event.
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

    /// @notice Sets a new Oracle Router contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {CoreContractSet} event.
    /// @param newOracleRouter The new address of oracleRouter.
    function setOracleRouter(address newOracleRouter) external {
        _checkElevatedPermissions();

        oracleRouter = newOracleRouter;
        emit CoreContractSet("Oracle Router", newOracleRouter);
    }

    /// @notice Sets a new fee accumulator contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {CoreContractSet} event.
    /// @param newFeeAccumulator The new address of feeAccumulator.
    function setFeeAccumulator(address newFeeAccumulator) external {
        _checkElevatedPermissions();

        feeAccumulator = newFeeAccumulator;
        emit CoreContractSet("Fee Accumulator", newFeeAccumulator);
    }

    /// @notice Sets a new WormholeCore contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {WormholeCoreSet} event.
    /// @param newWormholeCore The new address of WormholeCore.
    function setWormholeCore(address newWormholeCore) external {
        _checkElevatedPermissions();

        wormholeCore = IWormhole(newWormholeCore);
        emit WormholeCoreSet(newWormholeCore);
    }

    /// @notice Sets a new WormholeRelayer contract address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {WormholeRelayerSet} event.
    /// @param newWormholeRelayer The new address of wormholeRelayer.
    function setWormholeRelayer(address newWormholeRelayer) external {
        _checkElevatedPermissions();

        wormholeRelayer = IWormholeRelayer(newWormholeRelayer);
        emit WormholeRelayerSet(newWormholeRelayer);
    }

    /// @notice Sets an address of Circle TokenMessenger contract.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {CircleTokenMessengerSet} event.
    /// @param newCircleTokenMessenger The new address of Circle TokenMessenger.
    function setCircleTokenMessenger(
        address newCircleTokenMessenger
    ) external {
        _checkElevatedPermissions();

        circleTokenMessenger = ITokenMessenger(newCircleTokenMessenger);
        emit CircleTokenMessengerSet(newCircleTokenMessenger);
    }

    /// @notice Sets an address of Wormhole TokenBridge contract.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {TokenBridgeSet} event.
    /// @param newTokenBridge The new address of Wormhole TokenBridge.
    function setTokenBridge(address newTokenBridge) external {
        _checkElevatedPermissions();

        tokenBridge = ITokenBridge(newTokenBridge);
        emit TokenBridgeSet(newTokenBridge);
    }

    /// @notice Registers wormhole specific chain IDs for evm chain IDs.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {WormholeChainIDsSet} event.
    /// @param chainIds Array of EVM chain IDs to register.
    /// @param wormholeChainIds Array of Wormhole specific chain IDs.
    function registerWormholeChainIDs(
        uint256[] calldata chainIds,
        uint16[] calldata wormholeChainIds
    ) external {
        _checkElevatedPermissions();

        uint256 numChainIds = chainIds.length;
        for (uint256 i; i < numChainIds; ++i) {
            wormholeChainId[chainIds[i]] = wormholeChainIds[i];
        }
        emit WormholeChainIDsSet(chainIds, wormholeChainIds);
    }

    /// @notice Registers CCTP domains for EVM chain IDs.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {CCTPDomainsSet} event.
    /// @param chainIds EVM chain IDs.
    /// @param cctpDomains CCTP domains.
    function registerCCTPDomains(
        uint256[] calldata chainIds,
        uint32[] calldata cctpDomains
    ) external {
        _checkElevatedPermissions();

        uint256 numChainIds = chainIds.length;

        for (uint256 i; i < numChainIds; ++i) {
            cctpDomain[chainIds[i]] = cctpDomains[i];
        }
        emit CCTPDomainsSet(chainIds, cctpDomains);
    }

    /// @notice Sets an address of gelato sponsor.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {GelatoSponsorSet} event.
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
    ///      Emits a {FeeSet} event.
    /// @param value The new fee to take on compound to fund future
    ///              auto compounding, in `basis points`.
    function setProtocolCompoundFee(uint256 value) external {
        _checkElevatedPermissions();

        // Compound fee cannot be more than 5%.
        if (value > 500) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config.
        protocolCompoundFee = _bpToWad(value);

        // Update vault harvest fee with new yield fee.
        protocolHarvestFee = protocolYieldFee + _bpToWad(value);

        emit FeeSet("Compound", value);
    }

    /// @notice Sets the fee taken by Curvance DAO on all generated
    ///         by the protocol.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 50%.
    ///      Emits a {FeeSet} event.
    /// @param value The new fee to take on compound to distribute to veCVE
    ///              lockers, in `basis points`.
    function setProtocolYieldFee(uint256 value) external {
        _checkElevatedPermissions();

        // Compound fee cannot be more than 50%.
        if (value > 5000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config.
        protocolYieldFee = _bpToWad(value);

        // Update vault harvest fee with new yield fee.
        protocolHarvestFee = _bpToWad(value) + protocolCompoundFee;

        emit FeeSet("Yield", value);
    }

    /// @notice Sets the fee taken by Curvance DAO on leverage/deleverage
    ///         via position folding.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 2%.
    ///      Emits a {FeeSet} event.
    /// @param value The new fee to take on leverage/deleverage when done
    ///              by position folding, in `basis points`.
    function setProtocolLeverageFee(uint256 value) external {
        _checkElevatedPermissions();

        // Leverage fee cannot be more than 2%.
        if (value > 200) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }
        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config.
        protocolLeverageFee = _bpToWad(value);

        emit FeeSet("Leverage", value);
    }

    /// @notice Sets the fee taken by Curvance DAO from interest generated.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 50%.
    ///      Emits an {InterestFeeSet} event.
    /// @param market The address of the market manager to configure
    ///               interest fees of.
    /// @param value The new fee to take on interest generated
    ///              by a debt token, in `basis points`.
    function setProtocolInterestRateFee(
        address market,
        uint256 value
    ) external {
        _checkElevatedPermissions();

        // Interest fee cannot be more than 50%.
        if (value > 5000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Validate that you're setting the fee for an actual market manager.
        if (!isMarketManager[market]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config.
        protocolInterestFactor[market] = _bpToWad(value);

        emit InterestFeeSet(market, value);
    }

    /// @notice Sets the early unlock penalty value for when users want to
    ///         unlock their veCVE early.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be between 30% and 90%.
    ///      Emits a {MultiplierSet} event.
    /// @param value The new penalty on early expiring a vote escrowed
    ///              cve position, in `basis points`.
    function setEarlyUnlockPenaltyMultiplier(uint256 value) external {
        _checkElevatedPermissions();

        // Early unlock penalty cannot be more than 50%.
        if (value > 9000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Early unlock penalty cannot be less than 30%,
        // unless its being turned off.
        if (value < 3000 && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        earlyUnlockPenaltyMultiplier = value;

        emit MultiplierSet("Early Unlock Penalty", value);
    }

    /// @notice Sets the voting power boost received by locks using
    ///         Continuous Lock mode.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier.
    ///      Emits a {MultiplierSet} event.
    /// @param value The new voting power boost for continuous lock mode
    ///              vote escrowed cve positions, in `basis points`.
    function setVoteBoostMultiplier(uint256 value) external {
        _checkElevatedPermissions();

        // Voting power boost cannot be less than 1,
        // unless its being turned off.
        if (value < DENOMINATOR && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        voteBoostMultiplier = value;

        emit MultiplierSet("Vote Boost", value);
    }

    /// @notice Sets the emissions boost received by choosing
    ///         to lock emissions at veCVE.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier.
    ///      Emits a {MultiplierSet} event.
    /// @param value The new emissions boost for opting to take emissions
    ///              in a vote escrowed cve position instead of liquid CVE,
    ///              in `basis points`.
    function setLockBoostMultiplier(uint256 value) external {
        _checkElevatedPermissions();

        // Emissions boost cannot be less than 1, unless its being turned off.
        if (value < DENOMINATOR && value != 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        lockBoostMultiplier = value;

        emit MultiplierSet("Lock Boost", value);
    }

    /// USER DELEGATION MANAGEMENT ///

    /// @notice Increments a caller's approval index.
    /// @dev By incrementing their approval index, a user's delegates will all
    ///      have their delegation authority revoked across all Curvance
    ///      contracts.
    ///      Emits an {ApprovalIndexIncremented} event.
    function incrementApprovalIndex() external {
        uint256 newIndex = userApprovalIndex[msg.sender] + 1;
        userApprovalIndex[msg.sender] = newIndex;

        emit ApprovalIndexIncremented(msg.sender, newIndex);
    }

    /// @notice Sets a callers status for whether to allow new delegation
    ///         or not.
    /// @param delegable Whether caller wants to allow new delegation or not.
    ///      Emits a {DelegableStatusSet} event.
    function disableDelegable(bool delegable) external {
        delegatingDisabled[msg.sender] = delegable;

        emit DelegableStatusSet(msg.sender, delegable);
    }

    /// OWNERSHIP LOGIC

    /// @notice Sets DAO ownership to a new address.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {OwnershipTransferred} event.
    /// @param newDaoAddress The new DAO address.
    function transferDaoOwnership(address newDaoAddress) external {
        _checkElevatedPermissions();

        // Cache old dao address for event emission.
        address previousDaoAddress = daoAddress;
        daoAddress = newDaoAddress;

        // Delete permission data.
        delete hasDaoPermissions[previousDaoAddress];
        // Add new permission data.
        hasDaoPermissions[newDaoAddress] = true;
        emit OwnershipTransferred(previousDaoAddress, newDaoAddress);

        // Notify Timelock Controller of a DAO address update.
        if (timelock != address(0)) {
            if (
                ERC165Checker.supportsInterface(
                    timelock,
                    type(ITimelock).interfaceId
                )
            ) {
                ITimelock(timelock).updateDaoAddress();
            }
        }
    }

    /// @notice Sets timelock ownership to a new address.
    /// @dev Only callable by the Emergency Council.
    ///      Emits a {NewTimelockConfiguration} event.
    /// @param newTimelock The new timelock address.
    function migrateTimelockConfiguration(address newTimelock) external {
        _checkEmergencyCouncilPermissions();

        // Cache old timelock for event emission.
        address previousTimelock = timelock;
        timelock = newTimelock;

        // Delete permission data.
        delete hasDaoPermissions[previousTimelock];
        delete hasElevatedPermissions[previousTimelock];

        // Add new permission data.
        hasDaoPermissions[newTimelock] = true;
        hasElevatedPermissions[newTimelock] = true;

        emit NewTimelockConfiguration(previousTimelock, newTimelock);
    }

    /// @notice Sets emergency council ownership to a new address.
    /// @dev Only callable by the Emergency Council.
    ///      Emits a {NewTimelockConfiguration} event.
    /// @param newEmergencyCouncil The new emergency council address.
    function transferEmergencyCouncil(address newEmergencyCouncil) external {
        _checkEmergencyCouncilPermissions();

        // Cache old emergency council for event emission.
        address previousEmergencyCouncil = emergencyCouncil;
        emergencyCouncil = newEmergencyCouncil;

        // Delete permission data.
        delete hasDaoPermissions[previousEmergencyCouncil];
        delete hasElevatedPermissions[previousEmergencyCouncil];

        // Add new permission data.
        hasDaoPermissions[newEmergencyCouncil] = true;
        hasElevatedPermissions[newEmergencyCouncil] = true;

        emit EmergencyCouncilTransferred(
            previousEmergencyCouncil,
            newEmergencyCouncil
        );
    }

    /// MULTICHAIN SUPPORT LOGIC

    /// @notice Adds support for a new chain.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Emits a {NewChainAdded} event.
    /// @param newOmnichainOperator The address that will be the source
    ///                             address sending messaging to this chain
    ///                             for validation.
    /// @param messagingHub Contract address for new chains Messaging Hub.
    /// @param cveAddress CVE address on the chain.
    /// @param chainId GETH Chain ID where this address authorized.
    /// @param sourceAux Auxilliary data when the chain is source.
    /// @param destinationAux Auxilliary data when the chain is destination.
    /// @param messagingChainId Messaging Chain ID where this address authorized.
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

        // Validate Chain Operator has not been added already.
        if (
            omnichainOperators[newOmnichainOperator][chainId].isAuthorized == 2
        ) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Validate this "new" chain is not currently supported.
        if (supportedChainData[chainId].isSupported == 2) {
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

    /// @notice Removes support for a chain.
    /// @dev Callable by an address with DAO Authority or higher.
    ///      Emits a {RemovedChain} event.
    /// @param currentOmnichainOperator The current address that is the source
    ///                                 address sending messaging to this
    ///                                 chain for validation.
    /// @param chainId GETH Chain ID where `currentOmnichainOperator` is
    ///                authorized.
    function removeChainSupport(
        address currentOmnichainOperator,
        uint256 chainId
    ) external {
        // Lower permissioning on removing chains as it will reduce risk to
        // the system.
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

        // Remove chain support from protocol.
        supportedChainData[chainId].isSupported = 1;
        // Remove operator support from protocol.
        operatorToRemove.isAuthorized = 1;
        // Decrease supportedChains.
        supportedChains--;
        // Remove messagingChainId <> GETH chainId mapping table references.
        delete GETHToMessagingChainId[
            messagingToGETHChainId[operatorToRemove.messagingChainId]
        ];
        delete messagingToGETHChainId[operatorToRemove.messagingChainId];

        emit RemovedChain(chainId, currentOmnichainOperator);
    }

    /// CONTRACT MAPPING LOGIC

    /// @notice Sets an external calldata checker contract.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    /// @param target The target contract for external calldata
    ///               such as 1Inch V5.
    /// @param callDataChecker The contract that will check call data prior
    ///                        to execution in `target`.
    function setExternalCallDataChecker(
        address target,
        address callDataChecker
    ) external {
        _checkElevatedPermissions();

        externalCallDataChecker[target] = callDataChecker;
    }

    /// @notice Adds a Zapper contract for use in Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Cannot be a supported Zapper contract prior.
    ///      Emits a {NewCurvanceContract} event.
    /// @param newZapper The new Zapper contract to support for use
    ///                  in Curvance.
    function addZapper(address newZapper) external {
        _checkElevatedPermissions();

        // Validate `newZapper` is not currently supported.
        if (isZapper[newZapper]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isZapper[newZapper] = true;

        emit NewCurvanceContract("Zapper", newZapper);
    }

    /// @notice Removes a Zapper contract from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be a supported Zapper contract prior.
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentZapper The supported Zapper contract to remove from
    ///                      Curvance.
    function removeZapper(address currentZapper) external {
        _checkElevatedPermissions();

        // Validate `currentZapper` is currently supported.
        if (!isZapper[currentZapper]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isZapper[currentZapper];

        emit RemovedCurvanceContract("Zapper", currentZapper);
    }

    /// @notice Adds a Swapper contract for use in Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Cannot be a supported Swapper contract prior.
    ///      Emits a {NewCurvanceContract} event.
    /// @param newSwapper The new Swapper contract to support for use
    ///                   in Curvance.
    function addSwapper(address newSwapper) external {
        _checkElevatedPermissions();

        // Validate `newSwapper` is not currently supported.
        if (isSwapper[newSwapper]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isSwapper[newSwapper] = true;

        emit NewCurvanceContract("Swapper", newSwapper);
    }

    /// @notice Removes a Swapper contract from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be a supported Swapper contract prior.
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentSwapper The supported Swapper contract to remove from
    ///                       Curvance.
    function removeSwapper(address currentSwapper) external {
        _checkElevatedPermissions();

        // Validate `currentSwapper` is currently supported.
        if (!isSwapper[currentSwapper]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isSwapper[currentSwapper];

        emit RemovedCurvanceContract("Swapper", currentSwapper);
    }

    /// @notice Adds an approved VeCVE locker contract for use in Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Cannot be an approved VeCVE locker contract prior.
    ///      Emits a {NewCurvanceContract} event.
    /// @param newVeCVELocker The new VeCVE locker contract to approve for use
    ///                       in Curvance.
    function addVeCVELocker(address newVeCVELocker) external {
        _checkElevatedPermissions();

        // Validate `newVeCVELocker` is not currently supported.
        if (isVeCVELocker[newVeCVELocker]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isVeCVELocker[newVeCVELocker] = true;

        emit NewCurvanceContract("VeCVELocker", newVeCVELocker);
    }

    /// @notice Removes an approved VeCVE locker contract for use in Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be an approved VeCVE locker contract prior.
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentVeCVELocker The approved VeCVE locker contract to remove
    ///                           from Curvance.
    function removeVeCVELocker(address currentVeCVELocker) external {
        _checkElevatedPermissions();

        // Validate `currentVeCVELocker` is currently supported.
        if (!isVeCVELocker[currentVeCVELocker]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isVeCVELocker[currentVeCVELocker];

        emit RemovedCurvanceContract("VeCVELocker", currentVeCVELocker);
    }

    /// @notice Adds a Gauge Controller contract for use in Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Cannot be a supported Gauge Controller contract prior.
    ///      Emits a {NewCurvanceContract} event.
    /// @param newGaugeController The new Gauge Controller contract to support
    ///                           for use in Curvance.
    function addGaugeController(address newGaugeController) external {
        _checkElevatedPermissions();

        // Validate `newGaugeController` is not currently supported.
        if (isGaugeController[newGaugeController]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isGaugeController[newGaugeController] = true;

        emit NewCurvanceContract("Gauge Controller", newGaugeController);
    }

    /// @notice Removes a Gauge Controller contract from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be a supported Gauge Controller contract prior.
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentGaugeController The supported Gauge Controller contract
    ///                               to remove from Curvance.
    function removeGaugeController(address currentGaugeController) external {
        _checkElevatedPermissions();

        // Validate `currentGaugeController` is currently supported.
        if (!isGaugeController[currentGaugeController]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isGaugeController[currentGaugeController];

        emit RemovedCurvanceContract(
            "Gauge Controller",
            currentGaugeController
        );
    }

    /// @notice Adds a Harvester contract for use in Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Cannot be a supported Harvester contract prior.
    ///      Emits a {NewCurvanceContract} event.
    /// @param newHarvester The new Harvester contract to support for use
    ///                     in Curvance.
    function addHarvester(address newHarvester) external {
        _checkElevatedPermissions();

        // Validate `newHarvester` is not currently supported.
        if (isHarvester[newHarvester]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isHarvester[newHarvester] = true;

        emit NewCurvanceContract("Harvestor", newHarvester);
    }

    /// @notice Removes a Harvester contract from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be a supported Harvester contract prior.
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentHarvester The supported Harvester contract to remove
    ///                         from Curvance.
    function removeHarvester(address currentHarvester) external {
        _checkElevatedPermissions();

        // Validate `currentHarvester` is currently supported.
        if (!isHarvester[currentHarvester]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        delete isHarvester[currentHarvester];

        emit RemovedCurvanceContract("Harvestor", currentHarvester);
    }

    /// @notice Adds an Endpoint contract for use in Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Cannot be a supported Endpoint contract prior.
    ///      Emits a {NewCurvanceContract} event.
    /// @param newEndpoint The new Endpoint contract to support for use
    ///                    in Curvance.
    function addEndpoint(address newEndpoint) external {
        _checkElevatedPermissions();

        // Validate `newEndpoint` is not currently supported.
        if (isEndpoint[newEndpoint]) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isEndpoint[newEndpoint] = true;

        emit NewCurvanceContract("Endpoint", newEndpoint);
    }

    /// @notice Removes an Endpoint contract from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be a supported Endpoint contract prior.
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentEndpoint The supported Endpoint contract to remove
    ///                        from Curvance.
    function removeEndpoint(address currentEndpoint) external {
        _checkElevatedPermissions();

        // Validate `currentEndpoint` is currently supported.
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

    /// @notice Adds a new Market Manager and associated fee configurations.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 50% interest fee.
    ///      Cannot be a supported Market Manager contract prior.
    ///      Emits a {NewCurvanceContract} and {InterestFeeSet} events.
    /// @param newMarketManager The new Market Manager contract to support
    ///                         for use in Curvance.
    /// @param marketInterestFactor The interest factor associated with
    ///                             the market manager.
    function addMarketManager(
        address newMarketManager,
        uint256 marketInterestFactor
    ) public virtual {
        _checkElevatedPermissions();

        // Validate `newMarketManager` is not currently supported.
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

        /// Interest fee cannot be more than 50%.
        if (marketInterestFactor > 5000) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        isMarketManager[newMarketManager] = true;
        // We store supported markets semi redundantly for offchain querying.
        marketManagers.push(newMarketManager);
        // Convert interest factor parameter from basis points to `WAD`
        // for precision calculations.
        protocolInterestFactor[newMarketManager] = _bpToWad(
            marketInterestFactor
        );

        emit NewCurvanceContract("Market Manager", newMarketManager);
        emit InterestFeeSet(newMarketManager, marketInterestFactor);
    }

    /// @notice Removes a current market manager from Curvance.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be a supported Market Manager contract prior.
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentMarketManager The supported Market Manager contract
    ///                             to remove from Curvance.
    function removeMarketManager(
        address currentMarketManager
    ) public virtual {
        _checkElevatedPermissions();

        // Validate `currentMarketManager` is currently supported.
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

    /// PUBLIC FUNCTIONS ///

    /// @notice Returns true if this contract implements the interface defined
    ///         by `interfaceId`.
    /// @param interfaceId The interface to check for implementation.
    /// @return Whether `interfaceId` is implemented or not.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(ICentralRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Multiplies `value` by 1e14 to convert it from `basis points`
    ///         to WAD.
    /// @dev Internal helper function for easily converting between scalars.
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        return value * 1e14;
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
