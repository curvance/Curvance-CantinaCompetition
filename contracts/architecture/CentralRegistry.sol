// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165 } from "contracts/libraries/ERC165.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CentralRegistry is ICentralRegistry, ERC165 {
    /// CONSTANTS ///

    uint256 public constant DENOMINATOR = 10000; // Scalar for math
    uint256 public immutable genesisEpoch; // Genesis Epoch timestamp

    /// STORAGE ///

    // DAO GOVERNANCE OPERATORS
    address public daoAddress; // DAO multisig
    address public timelock; // DAO multisig, with time delay
    address public emergencyCouncil; // Multi-protocol multisig, for emergencies

    // CURVANCE TOKEN CONTRACTS
    address public CVE; // CVE contract address
    address public veCVE; // veCVE contract address
    address public callOptionCVE; // CVE Call Option contract address

    // DAO CONTRACTS DATA
    address public cveLocker; // CVE Locker contract address
    address public protocolMessagingHub; // Protocol Messaging Hub contract address
    address public priceRouter; // Price Router contract address
    address public zroAddress; // ZRO contract address for layerzero
    address public feeAccumulator; // Fee Accumulator contract address
    address public feeHub; // Fee Hub contract address

    // PROTOCOL VALUES in `DENOMINATOR`
    uint256 public protocolCompoundFee = 100 * 1e14; // Fee for compounding position vaults
    uint256 public protocolYieldFee = 1500 * 1e14; // Fee on yield in position vaults
    // Joint fee so that we can minimize an external call in position vault contracts
    uint256 public protocolHarvestFee = protocolCompoundFee + protocolYieldFee;
    uint256 public protocolLiquidationFee = 250; // Protocol Reserve Share on liquidation
    uint256 public protocolLeverageFee; // Protocol Fee on leveraging
    uint256 public protocolInterestRateFee; // Protocol Reserve Share on Interest Rates
    uint256 public earlyUnlockPenaltyValue; // Penalty Fee for unlocking from veCVE early
    uint256 public voteBoostValue; // Voting power bonus for Continuous Lock Mode
    uint256 public lockBoostValue; // Rewards bonus for Continuous Lock Mode
    

    // DAO PERMISSION DATA
    mapping(address => bool) public hasDaoPermissions;
    mapping(address => bool) public hasElevatedPermissions;

    // DAO CONTRACT MAPPINGS
    mapping(address => bool) public approvedZapper;
    mapping(address => bool) public approvedSwapper;
    mapping(address => bool) public approvedVeCVELocker;
    mapping(address => bool) public gaugeController;
    mapping(address => bool) public harvester;
    mapping(address => bool) public lendingMarket;
    mapping(address => bool) public feeManager;
    mapping(address => bool) public approvedEndpoint;

    /// EVENTS ///

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event newTimelockConfiguration(
        address indexed previousTimelock,
        address indexed newTimelock
    );
    event EmergencyCouncilTransferred(
        address indexed previousEmergencyCouncil,
        address indexed newEmergencyCouncil
    );

    event NewApprovedZapper(address indexed zapper);
    event approvedZapperRemoved(address indexed zapper);

    event NewApprovedSwapper(address indexed swapper);
    event approvedSwapperRemoved(address indexed swapper);

    event NewVeCVELocker(address indexed veCVELocker);
    event VeCVELockerRemoved(address indexed veCVELocker);

    event NewGaugeController(address indexed gaugeController);
    event GaugeControllerRemoved(address indexed gaugeController);

    event NewHarvester(address indexed harvester);
    event HarvesterRemoved(address indexed harvester);

    event NewLendingMarket(address indexed lendingMarket);
    event LendingMarketRemoved(address indexed lendingMarket);

    event NewFeeManager(address indexed feeManager);
    event FeeManagerRemoved(address indexed feeManager);

    event NewApprovedEndpoint(address indexed approvedEndpoint);
    event ApprovedEndpointRemoved(address indexed approvedEndpoint);

    /// MODIFIERS ///

    modifier onlyDaoManager() {
        require(msg.sender == daoAddress, "CentralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyTimelock() {
        require(msg.sender == timelock, "CentralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyEmergencyCouncil() {
        require(
            msg.sender == emergencyCouncil,
            "CentralRegistry: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyDaoPermissions() {
        require(
            hasDaoPermissions[msg.sender],
            "CentralRegistry: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            hasElevatedPermissions[msg.sender],
            "CentralRegistry: UNAUTHORIZED"
        );
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
        emit newTimelockConfiguration(address(0), timelock_);
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
    function setFeeHub(address newFeeHub) external onlyElevatedPermissions {
        feeHub = newFeeHub;
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
        require(value <= 500, "CentralRegistry: invalid parameter");
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
        require(value <= 2000, "CentralRegistry: invalid parameter");
        /// YieldFee is represented in 1e16 format
        /// So we need to multiply by 1e14 to format properly
        /// from basis points to %
        protocolYieldFee = value * 1e14;

        /// Update vault harvest fee with new yield fee
        protocolHarvestFee = (value * 1e14) + protocolCompoundFee;
    }

    /// @notice Sets the fee taken by Curvance DAO on liquidation
    ///         of collateral assets
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 5%
    function setProtocolLiquidationFee(
        uint256 value
    ) external onlyElevatedPermissions {
        require(value <= 500, "CentralRegistry: invalid parameter");
        /// Liquidation fee is represented as 1e16 format
        /// So we need to multiply by 1e14 to format properly
        /// from basis points to %
        protocolLiquidationFee = value * 1e14;
    }

    /// @notice Sets the fee taken by Curvance DAO on leverage/deleverage
    ///         via position folding
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 1%
    function setProtocolLeverageFee(
        uint256 value
    ) external onlyElevatedPermissions {
        require(value <= 100, "CentralRegistry: invalid parameter");
        protocolLeverageFee = value;
    }

    /// @notice Sets the fee taken by Curvance DAO from interest generated
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 30%
    function setProtocolInterestRateFee(
        uint256 value
    ) external onlyElevatedPermissions {
        require(value <= 3000, "CentralRegistry: invalid parameter");
        /// Interest Rate fee is represented as 1e16 format
        /// So we need to multiply by 1e14 to format properly
        /// from basis points to %
        protocolInterestRateFee = value * 1e14;
    }

    /// @notice Sets the early unlock penalty value for when users want to
    ///         unlock their veCVE early
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be between 30% and 90%
    function setEarlyUnlockPenaltyValue(
        uint256 value
    ) external onlyElevatedPermissions {
        require(
            (value >= 3000 && value <= 9000) || value == 0,
            "CentralRegistry: invalid parameter"
        );
        earlyUnlockPenaltyValue = value;
    }

    /// @notice Sets the voting power boost received by locks using
    ///         Continuous Lock mode
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier
    function setVoteBoostValue(
        uint256 value
    ) external onlyElevatedPermissions {
        require(
            value > DENOMINATOR || value == 0,
            "CentralRegistry: invalid parameter"
        );
        voteBoostValue = value;
    }

    /// @notice Sets the emissions boost received by choosing
    ///         to lock emissions at veCVE
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      must be a positive boost i.e. > 1.01 or greater multiplier
    function setLockBoostValue(
        uint256 value
    ) external onlyElevatedPermissions {
        require(
            value > DENOMINATOR || value == 0,
            "CentralRegistry: invalid parameter"
        );
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

        emit newTimelockConfiguration(previousTimelock, newTimelock);
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

    /// CONTRACT MAPPING LOGIC

    function addApprovedZapper(
        address newApprovedZapper
    ) external onlyElevatedPermissions {
        require(
            !approvedZapper[newApprovedZapper],
            "CentralRegistry: already approved zapper"
        );

        approvedZapper[newApprovedZapper] = true;

        emit NewApprovedZapper(newApprovedZapper);
    }

    function removeApprovedZapper(
        address currentApprovedZapper
    ) external onlyElevatedPermissions {
        require(
            approvedZapper[currentApprovedZapper],
            "CentralRegistry: not approved zapper"
        );

        delete approvedZapper[currentApprovedZapper];

        emit approvedZapperRemoved(currentApprovedZapper);
    }

    function addApprovedSwapper(
        address newApprovedSwapper
    ) external onlyElevatedPermissions {
        require(
            !approvedSwapper[newApprovedSwapper],
            "CentralRegistry: already approved swapper"
        );

        approvedSwapper[newApprovedSwapper] = true;

        emit NewApprovedSwapper(newApprovedSwapper);
    }

    function removeApprovedSwapper(
        address currentApprovedSwapper
    ) external onlyElevatedPermissions {
        require(
            approvedSwapper[currentApprovedSwapper],
            "CentralRegistry: not approved swapper"
        );

        delete approvedSwapper[currentApprovedSwapper];

        emit approvedSwapperRemoved(currentApprovedSwapper);
    }

    function addVeCVELocker(
        address newVeCVELocker
    ) external onlyElevatedPermissions {
        require(
            !approvedVeCVELocker[newVeCVELocker],
            "CentralRegistry: already veCVELocker"
        );

        approvedVeCVELocker[newVeCVELocker] = true;

        emit NewVeCVELocker(newVeCVELocker);
    }

    function removeVeCVELocker(
        address currentVeCVELocker
    ) external onlyElevatedPermissions {
        require(
            approvedVeCVELocker[currentVeCVELocker],
            "CentralRegistry: not veCVELocker"
        );

        delete approvedVeCVELocker[currentVeCVELocker];

        emit VeCVELockerRemoved(currentVeCVELocker);
    }

    function addGaugeController(
        address newGaugeController
    ) external onlyElevatedPermissions {
        require(
            !gaugeController[newGaugeController],
            "CentralRegistry: already gauge controller"
        );

        gaugeController[newGaugeController] = true;

        emit NewGaugeController(newGaugeController);
    }

    function removeGaugeController(
        address currentGaugeController
    ) external onlyElevatedPermissions {
        require(
            gaugeController[currentGaugeController],
            "CentralRegistry: not gauge controller"
        );

        delete gaugeController[currentGaugeController];

        emit GaugeControllerRemoved(currentGaugeController);
    }

    function addHarvester(
        address newHarvester
    ) external onlyElevatedPermissions {
        require(
            !harvester[newHarvester],
            "CentralRegistry: already harvester"
        );

        harvester[newHarvester] = true;

        emit NewHarvester(newHarvester);
    }

    function removeHarvester(
        address currentHarvester
    ) external onlyElevatedPermissions {
        require(harvester[currentHarvester], "CentralRegistry: not harvester");

        delete harvester[currentHarvester];

        emit HarvesterRemoved(currentHarvester);
    }

    function addLendingMarket(
        address newLendingMarket
    ) external onlyElevatedPermissions {
        require(
            !lendingMarket[newLendingMarket],
            "CentralRegistry: already lending market"
        );

        lendingMarket[newLendingMarket] = true;

        emit NewLendingMarket(newLendingMarket);
    }

    function removeLendingMarket(
        address currentLendingMarket
    ) external onlyElevatedPermissions {
        require(
            lendingMarket[currentLendingMarket],
            "CentralRegistry: not lending market"
        );

        delete lendingMarket[currentLendingMarket];

        emit LendingMarketRemoved(currentLendingMarket);
    }

    function addFeeManager(
        address newFeeManager
    ) external onlyElevatedPermissions {
        require(
            !feeManager[newFeeManager],
            "CentralRegistry: already fee manager"
        );

        feeManager[newFeeManager] = true;

        emit NewFeeManager(newFeeManager);
    }

    function removeFeeManager(
        address currentFeeManager
    ) external onlyElevatedPermissions {
        require(
            feeManager[currentFeeManager],
            "CentralRegistry: not fee manager"
        );

        delete feeManager[currentFeeManager];

        emit FeeManagerRemoved(currentFeeManager);
    }

    function addApprovedEndpoint(
        address newApprovedEndpoint
    ) external onlyElevatedPermissions {
        require(
            !approvedEndpoint[newApprovedEndpoint],
            "CentralRegistry: already endpoint"
        );

        approvedEndpoint[newApprovedEndpoint] = true;

        emit NewApprovedEndpoint(newApprovedEndpoint);
    }

    function removeApprovedEndpoint(
        address currentApprovedEndpoint
    ) external onlyElevatedPermissions {
        require(
            approvedEndpoint[currentApprovedEndpoint],
            "CentralRegistry: not endpoint"
        );

        delete approvedEndpoint[currentApprovedEndpoint];

        emit ApprovedEndpointRemoved(currentApprovedEndpoint);
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
