// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/interfaces/ICentralRegistry.sol";

contract CentralRegistry is ICentralRegistry {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event newTimelockConfiguration(address indexed previousTimelock, address indexed newTimelock);
    event EmergencyCouncilTransferred(address indexed previousEmergencyCouncil, address indexed newEmergencyCouncil);

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

    // Add timelock?

    uint256 public constant DENOMINATOR = 10000;

    uint256 public immutable genesisEpoch;

    // DAO governance operators
    address public daoAddress;
    address public timelock;
    address public emergencyCouncil;

    // Token Contracts
    address public CVE;
    address public veCVE;
    address public callOptionCVE;

    address public cveLocker;

    address public protocolMessagingHub;
    address public priceRouter;
    address public depositRouter;
    address public zroAddress;
    address public feeHub;

    // Protocol Values
    uint256 public protocolYieldFee;
    uint256 public protocolLiquidationFee;
    uint256 public protocolLeverageFee;
    uint256 public voteBoostValue;
    uint256 public lockBoostValue;

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
        require(msg.sender == emergencyCouncil, "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyElevatedPermissions() {
        require(msg.sender == timelock || msg.sender == emergencyCouncil, "centralRegistry: UNAUTHORIZED");
        _;
    }

    /// CONSTRUCTOR

    constructor(address daoAddress_, address timelock_, address emergencyCouncil_, uint256 genesisEpoch_) {
        
        if (daoAddress_ == address(0)) {
            daoAddress_ = msg.sender;
        }

        if (timelock_ == address(0)) {
            timelock_ = msg.sender;
        }

        if (emergencyCouncil_ == address(0)) {
            emergencyCouncil_ = msg.sender;
        }

        daoAddress = daoAddress_;
        timelock = timelock_;
        emergencyCouncil = emergencyCouncil_;
        
        genesisEpoch = genesisEpoch_;
        emit OwnershipTransferred(address(0), daoAddress);
    }

    /// SETTER FUNCTIONS

    function setCVE(address newCVE) public onlyDaoManager {
        CVE = newCVE;
    }

    function setVeCVE(address newVeCVE) public onlyDaoManager {
        veCVE = newVeCVE;
    }

    function setCallOptionCVE(address newCallOptionCVE) public onlyDaoManager {
        callOptionCVE = newCallOptionCVE;
    }

    function setCVELocker(address newCVELocker) public onlyDaoManager {
        cveLocker = newCVELocker;
    }

    function setPriceRouter(address newPriceRouter) public onlyDaoManager {
        priceRouter = newPriceRouter;
    }

    function setDepositRouter(address newDepositRouter) public onlyDaoManager {
        depositRouter = newDepositRouter;
    }

    function setZroAddress(address newZroAddress) public onlyDaoManager {
        zroAddress = newZroAddress;
    }

    function setFeeHub(address newFeeHub) public onlyDaoManager {
        feeHub = newFeeHub;
    }

    function setProtocolYieldFee(uint256 value) public onlyDaoManager {
        require(
            value < 2000 || value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolYieldFee = value;
    }

    function setProtocolLiquidationFee(uint256 value) public onlyDaoManager {
        require(
            value < 500 || value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolLiquidationFee = value;
    }

    function setProtocolLeverageFee(uint256 value) public onlyDaoManager {
        require(
            value < 100 || value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolLeverageFee = value;
    }

    function setVoteBoostValue(uint256 value) public onlyDaoManager {
        require(
            value > DENOMINATOR || value == 0,
            "centralRegistry: invalid parameter"
        );
        voteBoostValue = value;
    }

    function setLockBoostValue(uint256 value) public onlyDaoManager {
        require(
            value > DENOMINATOR || value == 0,
            "centralRegistry: invalid parameter"
        );
        lockBoostValue = value;
    }

    /// OWNERSHIP LOGIC

    function transferDaoOwnership(address newDaoAddress) public onlyElevatedPermissions {
        address previousDaoAddress = daoAddress;
        daoAddress = newDaoAddress;
        emit OwnershipTransferred(previousDaoAddress, newDaoAddress);
    }

    function migrateTimelockConfiguration(address newTimelock) public onlyEmergencyCouncil {
        address previousTimelock = timelock;
        timelock = newTimelock;
        emit newTimelockConfiguration(previousTimelock, newTimelock);
    }

    function transferEmergencyCouncil(address newEmergencyCouncil) public onlyEmergencyCouncil {
        address previousEmergencyCouncil = emergencyCouncil;
        emergencyCouncil = newEmergencyCouncil;
        emit EmergencyCouncilTransferred(previousEmergencyCouncil, newEmergencyCouncil);
    }

    function addVeCVELocker(address newVeCVELocker) public onlyDaoManager {
        require(!approvedVeCVELocker[newVeCVELocker], "centralRegistry: already veCVELocker");

        approvedVeCVELocker[newVeCVELocker] = true;
        emit NewVeCVELocker(newVeCVELocker);
    }

    function removeVeCVELocker(
        address currentVeCVELocker
    ) public onlyDaoManager {
        require(approvedVeCVELocker[currentVeCVELocker], "centralRegistry: already not a veCVELocker");

        delete approvedVeCVELocker[currentVeCVELocker];
        emit VeCVELockerRemoved(currentVeCVELocker);
    }

    function addGaugeController(
        address newGaugeController
    ) public onlyDaoManager {
        require(!gaugeController[newGaugeController], "centralRegistry: already Gauge Controller");

        gaugeController[newGaugeController] = true;
        emit NewGaugeController(newGaugeController);
    }

    function removeGaugeController(
        address currentGaugeController
    ) public onlyDaoManager {
        require(gaugeController[currentGaugeController], "centralRegistry: not a Gauge Controller");

        delete gaugeController[currentGaugeController];
        emit GaugeControllerRemoved(currentGaugeController);
    }

    function addHarvester(address newHarvester) public onlyDaoManager {
        require(!harvester[newHarvester], "centralRegistry: already a Harvester");

        harvester[newHarvester] = true;
        emit NewHarvester(newHarvester);
    }

    function removeHarvester(address currentHarvester) public onlyDaoManager {
        require(harvester[currentHarvester], "centralRegistry: not a Harvester");

        delete harvester[currentHarvester];
        emit HarvesterRemoved(currentHarvester);
    }

    function addLendingMarket(address newLendingMarket) public onlyDaoManager {
        require(!lendingMarket[newLendingMarket], "centralRegistry: already Lending Market");

        lendingMarket[newLendingMarket] = true;
        emit NewLendingMarket(newLendingMarket);
    }

    function removeLendingMarket(
        address currentLendingMarket
    ) public onlyDaoManager {
        require(lendingMarket[currentLendingMarket], "centralRegistry: not a Lending Market");

        delete lendingMarket[currentLendingMarket];
        emit LendingMarketRemoved(currentLendingMarket);
    }

    function addFeeManager(address newFeeManager) public onlyDaoManager {
        require(!feeManager[newFeeManager], "centralRegistry: already a Fee Manager");

        feeManager[newFeeManager] = true;
        emit NewFeeManager(newFeeManager);
    }

    function removeFeeManager(
        address currentFeeManager
    ) public onlyDaoManager {
        require(feeManager[currentFeeManager], "centralRegistry: not a Fee Manager");

        delete feeManager[currentFeeManager];
        emit FeeManagerRemoved(currentFeeManager);
    }

    function addApprovedEndpoint(
        address newApprovedEndpoint
    ) public onlyDaoManager {
        require(!approvedEndpoint[newApprovedEndpoint], "centralRegistry: already an Endpoint");

        approvedEndpoint[newApprovedEndpoint] = true;
        emit NewApprovedEndpoint(newApprovedEndpoint);
    }

    function removeApprovedEndpoint(
        address currentApprovedEndpoint
    ) public onlyDaoManager {
        require(approvedEndpoint[currentApprovedEndpoint], "centralRegistry: not an Endpoint");

        delete approvedEndpoint[currentApprovedEndpoint];
        emit ApprovedEndpointRemoved(currentApprovedEndpoint);
    }
}
