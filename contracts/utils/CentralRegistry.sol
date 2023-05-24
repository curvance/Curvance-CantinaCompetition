// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

/// @notice Simple single central authorization mixin.
/// @author Mai
abstract contract CentralRegistry {

    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event NewHarvester(address indexed harvester);
    event HarvesterRemoved(address indexed harvester);
    event NewLendingMarket(address indexed lendingMarket);
    event LendingMarketRemoved(address indexed lendingMarket);
    event NewFeeManager(address indexed feeManager);
    event FeeManagerRemoved(address indexed feeManager);
    event NewApprovedEndpoint(address indexed approvedEndpoint);
    event ApprovedEndpointRemoved(address indexed approvedEndpoint);

    uint256 public constant DENOMINATOR = 10000;

    uint256 public immutable genesisEpoch;
    address public dao;
    address public cveLocker;

    address public CVE;
    address public veCVE;
    address public callOptionCVE;

    address public gaugeController;
    address public votingHub;
    address public priceRouter;
    address public depositRouter;
    address public zroAddress;
    address public feeHub;//Add setter
    address public feeRouting;//Add setter

    uint256 public protocolYieldFee;//Add setter
    uint256 public protocolLiquidationFee;//Add setter
    uint256 public lockBoostValue;
    bool    public isBoostingActive;
    
    mapping (address => bool) private harvester;
    mapping (address => bool) private lendingMarket;
    mapping (address => bool) private feeManager;
    mapping (address => bool) private approvedEndpoint;

    modifier onlyDaoManager() {
        require(msg.sender == dao, "UNAUTHORIZED");

        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address dao_, uint256 genesisEpoch_) {
        if (dao_ == address(0)){
            dao_ = msg.sender;
        }
        dao = dao_;
        genesisEpoch = genesisEpoch_;
        emit OwnershipTransferred(address(0), dao);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function isHarvester (address _address) public view returns (bool){
        return harvester[_address];
    }

    function isLendingMarket (address _address) public view returns (bool){
        return lendingMarket[_address];
    }

    function isFeeManager (address _address) public view returns (bool){
        return feeManager[_address];
    }

    function isApprovedEndpoint (address _address) public view returns (bool){
        return approvedEndpoint[_address];
    }

    /*//////////////////////////////////////////////////////////////
                             SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setCVELocker(address cveLocker_) public onlyDaoManager {
        cveLocker = cveLocker_;
    }

    function setCVE(address CVE_) public onlyDaoManager {
        CVE = CVE_;
    }

    function setVeCVE(address veCVE_) public onlyDaoManager {
        veCVE = veCVE_;
    }

    function setCallOptionCVE(address callOptionCVE_) public onlyDaoManager {
        callOptionCVE = callOptionCVE_;
    }

    function setGaugeController(address gaugeController_) public onlyDaoManager {
        gaugeController = gaugeController_;
    }

    function setVotingHub(address votingHub_) public onlyDaoManager {
        votingHub = votingHub_;
    }

    function setPriceRouter(address priceRouter_) public onlyDaoManager {
        priceRouter = priceRouter_;
    }

    function setDepositRouter(address depositRouter_) public onlyDaoManager {
        depositRouter = depositRouter_;
    }

    function setZroAddress(address zroAddress_) public onlyDaoManager {
        zroAddress = zroAddress_;
    }

    function setBoostingStatus(bool isBoostingActive_) public onlyDaoManager {
        isBoostingActive = isBoostingActive_;
    }

    function setBoostingValue(uint256 lockBoostValue_) public onlyDaoManager {
        require(lockBoostValue_ > DENOMINATOR, "Boosting value cannot be negative");
        lockBoostValue = lockBoostValue_;
    }

    /*//////////////////////////////////////////////////////////////
                             OWNERSHIP LOGIC
    //////////////////////////////////////////////////////////////*/

    function transferOwnership(address newDaoAddress) public onlyDaoManager {
        dao = newDaoAddress;
        emit OwnershipTransferred(msg.sender, newDaoAddress);
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

    function removeLendingMarket(address currentLendingMarket) public onlyDaoManager {
        require(lendingMarket[currentLendingMarket], "Not a Lending Market");

        delete lendingMarket[currentLendingMarket];
        emit LendingMarketRemoved(currentLendingMarket);
    }

    function addFeeManager(address newFeeManager) public onlyDaoManager {
        require(!feeManager[newFeeManager], "Already a Fee Manager");

        feeManager[newFeeManager] = true;
        emit NewFeeManager(newFeeManager);
    }

    function removeFeeManager(address currentFeeManager) public onlyDaoManager {
        require(feeManager[currentFeeManager], "Not a Fee Manager");

        delete feeManager[currentFeeManager];
        emit FeeManagerRemoved(currentFeeManager);
    }

    function addApprovedEndpoint(address newApprovedEndpoint) public onlyDaoManager {
        require(!approvedEndpoint[newApprovedEndpoint], "Already an Endpoint");

        approvedEndpoint[newApprovedEndpoint] = true;
        emit NewApprovedEndpoint(newApprovedEndpoint);
    }

    function removeApprovedEndpoint(address currentApprovedEndpoint) public onlyDaoManager {
        require(approvedEndpoint[currentApprovedEndpoint], "Not an Endpoint");

        delete approvedEndpoint[currentApprovedEndpoint];
        emit ApprovedEndpointRemoved(currentApprovedEndpoint);
    }

}