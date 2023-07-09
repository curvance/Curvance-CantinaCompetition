// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/interfaces/ICentralRegistry.sol";

contract CentralRegistry is ICentralRegistry {
    event OwnershipTransferred(address indexed user, address indexed newOwner);

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
        require(msg.sender == daoAddress, "UNAUTHORIZED");
        _;
    }

    /// CONSTRUCTOR

    constructor(address daoAddress_, uint256 genesisEpoch_) {
        if (daoAddress_ == address(0)) {
            daoAddress_ = msg.sender;
        }
        daoAddress = daoAddress_;
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

    function transferOwnership(address newDaoAddress) public onlyDaoManager {
        daoAddress = newDaoAddress;
        emit OwnershipTransferred(msg.sender, newDaoAddress);
    }

    function addVeCVELocker(address newVeCVELocker) public onlyDaoManager {
        require(!approvedVeCVELocker[newVeCVELocker], "Already Harvester");

        approvedVeCVELocker[newVeCVELocker] = true;
        emit NewVeCVELocker(newVeCVELocker);
    }

    function removeVeCVELocker(
        address currentVeCVELocker
    ) public onlyDaoManager {
        require(approvedVeCVELocker[currentVeCVELocker], "Already Harvester");

        delete approvedVeCVELocker[currentVeCVELocker];
        emit VeCVELockerRemoved(currentVeCVELocker);
    }

    function addGaugeController(
        address newGaugeController
    ) public onlyDaoManager {
        require(!gaugeController[newGaugeController], "Already Harvester");

        gaugeController[newGaugeController] = true;
        emit NewGaugeController(newGaugeController);
    }

    function removeGaugeController(
        address currentGaugeController
    ) public onlyDaoManager {
        require(gaugeController[currentGaugeController], "Already Harvester");

        delete gaugeController[currentGaugeController];
        emit GaugeControllerRemoved(currentGaugeController);
    }

    function addHarvester(address newHarvester) public onlyDaoManager {
        require(!harvester[newHarvester], "Already Harvester");

        harvester[newHarvester] = true;
        emit NewHarvester(newHarvester);
    }

    function removeHarvester(address currentHarvester) public onlyDaoManager {
        require(harvester[currentHarvester], "Not a Harvester");

        delete harvester[currentHarvester];
        emit HarvesterRemoved(currentHarvester);
    }

    function addLendingMarket(address newLendingMarket) public onlyDaoManager {
        require(!lendingMarket[newLendingMarket], "Already Lending Market");

        lendingMarket[newLendingMarket] = true;
        emit NewLendingMarket(newLendingMarket);
    }

    function removeLendingMarket(
        address currentLendingMarket
    ) public onlyDaoManager {
        require(lendingMarket[currentLendingMarket], "Not a Lending Market");

        delete lendingMarket[currentLendingMarket];
        emit LendingMarketRemoved(currentLendingMarket);
    }

    function addFeeManager(address newFeeManager) public onlyDaoManager {
        require(!feeManager[newFeeManager], "Already a Fee Manager");

        feeManager[newFeeManager] = true;
        emit NewFeeManager(newFeeManager);
    }

    function removeFeeManager(
        address currentFeeManager
    ) public onlyDaoManager {
        require(feeManager[currentFeeManager], "Not a Fee Manager");

        delete feeManager[currentFeeManager];
        emit FeeManagerRemoved(currentFeeManager);
    }

    function addApprovedEndpoint(
        address newApprovedEndpoint
    ) public onlyDaoManager {
        require(!approvedEndpoint[newApprovedEndpoint], "Already an Endpoint");

        approvedEndpoint[newApprovedEndpoint] = true;
        emit NewApprovedEndpoint(newApprovedEndpoint);
    }

    function removeApprovedEndpoint(
        address currentApprovedEndpoint
    ) public onlyDaoManager {
        require(approvedEndpoint[currentApprovedEndpoint], "Not an Endpoint");

        delete approvedEndpoint[currentApprovedEndpoint];
        emit ApprovedEndpointRemoved(currentApprovedEndpoint);
    }
}
