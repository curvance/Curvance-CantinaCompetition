// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "contracts/interfaces/ICentralRegistry.sol";

contract CentralRegistry is ICentralRegistry, ERC165 {

    /// PROTOCOL EVENTS ///
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

    /// CONSTANTS ///
    uint256 public constant DENOMINATOR = 10000;
    uint256 public immutable genesisEpoch;

    /// DAO GOVERNANCE OPERATORS ///

    /// DAO multisig, for day to day operations
    address public daoAddress;
    /// DAO multisig, on a time delay for dangerous permissions
    address public timelock;
    /// Multi-protocol multisig, only to be used during protocol threatening emergencies
    address public emergencyCouncil;

    /// CURVANCE TOKEN CONTRACTS ///
    address public CVE;
    address public veCVE;
    address public callOptionCVE;

    /// DAO CONTRACTS DATA ///
    address public cveLocker;
    address public protocolMessagingHub;
    address public priceRouter;
    address public depositRouter;
    address public zroAddress;
    address public feeHub;

    /// PROTOCOL VALUES ///
    uint256 public protocolYieldFee;
    uint256 public protocolLiquidationFee;
    uint256 public protocolLeverageFee;
    uint256 public voteBoostValue;
    uint256 public lockBoostValue;

    /// DAO PERMISSION DATA ///
    mapping(address => bool) public hasDaoPermissions;
    mapping(address => bool) public hasElevatedPermissions;

    /// DAO CONTRACT MAPPINGS ///
    mapping(address => bool) public approvedVeCVELocker;
    mapping(address => bool) public gaugeController;
    mapping(address => bool) public harvester;
    mapping(address => bool) public lendingMarket;
    mapping(address => bool) public feeManager;
    mapping(address => bool) public approvedEndpoint;

    modifier onlyDaoManager() {
        require(msg.sender == daoAddress, "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyTimelock() {
        require(msg.sender == timelock, "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyEmergencyCouncil() {
        require(
            msg.sender == emergencyCouncil,
            "centralRegistry: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyDaoPermissions() {
        require(
            hasDaoPermissions[msg.sender],
            "centralRegistry: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            hasElevatedPermissions[msg.sender],
            "centralRegistry: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR

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

        emit OwnershipTransferred(address(0), daoAddress);
        emit newTimelockConfiguration(address(0), timelock);
        emit EmergencyCouncilTransferred(address(0), emergencyCouncil);

        genesisEpoch = genesisEpoch_;
    }

    /// SETTER FUNCTIONS

    function setCVE(address newCVE) public onlyElevatedPermissions {
        CVE = newCVE;
    }

    function setVeCVE(address newVeCVE) public onlyElevatedPermissions {
        veCVE = newVeCVE;
    }

    function setCallOptionCVE(address newCallOptionCVE) public onlyDaoPermissions {
        callOptionCVE = newCallOptionCVE;
    }

    function setCVELocker(
        address newCVELocker
    ) public onlyElevatedPermissions {
        cveLocker = newCVELocker;
    }

    function setPriceRouter(
        address newPriceRouter
    ) public onlyElevatedPermissions {
        priceRouter = newPriceRouter;
    }

    function setDepositRouter(
        address newDepositRouter
    ) public onlyElevatedPermissions {
        depositRouter = newDepositRouter;
    }

    function setZroAddress(
        address newZroAddress
    ) public onlyElevatedPermissions {
        zroAddress = newZroAddress;
    }

    function setFeeHub(address newFeeHub) public onlyElevatedPermissions {
        feeHub = newFeeHub;
    }

    function setProtocolYieldFee(
        uint256 value
    ) public onlyElevatedPermissions {
        require(
            value <= 2000 || value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolYieldFee = value;
    }

    function setProtocolLiquidationFee(
        uint256 value
    ) public onlyElevatedPermissions {
        require(
            value <= 500 || value == 0,
            "centralRegistry: invalid parameter"
        );
        /// Liquidation fee is represented as 1e16 format
        /// So we need to multiply by 1e15 to format properly from basis points to %
        protocolLiquidationFee = value * 1e15;
    }

    function setProtocolLeverageFee(
        uint256 value
    ) public onlyElevatedPermissions {
        require(
            value <= 100 || value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolLeverageFee = value;
    }

    function setVoteBoostValue(uint256 value) public onlyElevatedPermissions {
        require(
            value > DENOMINATOR || value == 0,
            "centralRegistry: invalid parameter"
        );
        voteBoostValue = value;
    }

    function setLockBoostValue(uint256 value) public onlyElevatedPermissions {
        require(
            value > DENOMINATOR || value == 0,
            "centralRegistry: invalid parameter"
        );
        lockBoostValue = value;
    }

    /// OWNERSHIP LOGIC

    function transferDaoOwnership(
        address newDaoAddress
    ) public onlyElevatedPermissions {
        address previousDaoAddress = daoAddress;
        daoAddress = newDaoAddress;
        delete hasDaoPermissions[previousDaoAddress];
        hasDaoPermissions[newDaoAddress] = true;

        emit OwnershipTransferred(previousDaoAddress, newDaoAddress);
    }

    function migrateTimelockConfiguration(
        address newTimelock
    ) public onlyEmergencyCouncil {
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
    ) public onlyEmergencyCouncil {
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

    function addVeCVELocker(
        address newVeCVELocker
    ) public onlyElevatedPermissions {
        require(
            !approvedVeCVELocker[newVeCVELocker],
            "centralRegistry: already veCVELocker"
        );

        approvedVeCVELocker[newVeCVELocker] = true;
        emit NewVeCVELocker(newVeCVELocker);
    }

    function removeVeCVELocker(
        address currentVeCVELocker
    ) public onlyElevatedPermissions {
        require(
            approvedVeCVELocker[currentVeCVELocker],
            "centralRegistry: already not a veCVELocker"
        );

        delete approvedVeCVELocker[currentVeCVELocker];
        emit VeCVELockerRemoved(currentVeCVELocker);
    }

    function addGaugeController(
        address newGaugeController
    ) public onlyElevatedPermissions {
        require(
            !gaugeController[newGaugeController],
            "centralRegistry: already Gauge Controller"
        );

        gaugeController[newGaugeController] = true;
        emit NewGaugeController(newGaugeController);
    }

    function removeGaugeController(
        address currentGaugeController
    ) public onlyElevatedPermissions {
        require(
            gaugeController[currentGaugeController],
            "centralRegistry: not a Gauge Controller"
        );

        delete gaugeController[currentGaugeController];
        emit GaugeControllerRemoved(currentGaugeController);
    }

    function addHarvester(
        address newHarvester
    ) public onlyElevatedPermissions {
        require(
            !harvester[newHarvester],
            "centralRegistry: already a Harvester"
        );

        harvester[newHarvester] = true;
        emit NewHarvester(newHarvester);
    }

    function removeHarvester(
        address currentHarvester
    ) public onlyElevatedPermissions {
        require(
            harvester[currentHarvester],
            "centralRegistry: not a Harvester"
        );

        delete harvester[currentHarvester];
        emit HarvesterRemoved(currentHarvester);
    }

    function addLendingMarket(
        address newLendingMarket
    ) public onlyElevatedPermissions {
        require(
            !lendingMarket[newLendingMarket],
            "centralRegistry: already Lending Market"
        );

        lendingMarket[newLendingMarket] = true;
        emit NewLendingMarket(newLendingMarket);
    }

    function removeLendingMarket(
        address currentLendingMarket
    ) public onlyElevatedPermissions {
        require(
            lendingMarket[currentLendingMarket],
            "centralRegistry: not a Lending Market"
        );

        delete lendingMarket[currentLendingMarket];
        emit LendingMarketRemoved(currentLendingMarket);
    }

    function addFeeManager(
        address newFeeManager
    ) public onlyElevatedPermissions {
        require(
            !feeManager[newFeeManager],
            "centralRegistry: already a Fee Manager"
        );

        feeManager[newFeeManager] = true;
        emit NewFeeManager(newFeeManager);
    }

    function removeFeeManager(
        address currentFeeManager
    ) public onlyElevatedPermissions {
        require(
            feeManager[currentFeeManager],
            "centralRegistry: not a Fee Manager"
        );

        delete feeManager[currentFeeManager];
        emit FeeManagerRemoved(currentFeeManager);
    }

    function addApprovedEndpoint(
        address newApprovedEndpoint
    ) public onlyElevatedPermissions {
        require(
            !approvedEndpoint[newApprovedEndpoint],
            "centralRegistry: already an Endpoint"
        );

        approvedEndpoint[newApprovedEndpoint] = true;
        emit NewApprovedEndpoint(newApprovedEndpoint);
    }

    function removeApprovedEndpoint(
        address currentApprovedEndpoint
    ) public onlyElevatedPermissions {
        require(
            approvedEndpoint[currentApprovedEndpoint],
            "centralRegistry: not an Endpoint"
        );

        delete approvedEndpoint[currentApprovedEndpoint];
        emit ApprovedEndpointRemoved(currentApprovedEndpoint);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ICentralRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
