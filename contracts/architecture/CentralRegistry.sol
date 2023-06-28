// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/interfaces/ICentralRegistry.sol";

/// @notice Simple single central authorization mixin.
/// @author Mai
abstract contract CentralRegistry is ICentralRegistry {
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event NewHarvester(address indexed harvester);
    event HarvesterRemoved(address indexed harvester);
    event NewLendingMarket(address indexed lendingMarket);
    event LendingMarketRemoved(address indexed lendingMarket);
    event NewFeeManager(address indexed feeManager);
    event FeeManagerRemoved(address indexed feeManager);
    event NewApprovedEndpoint(address indexed approvedEndpoint);
    event ApprovedEndpointRemoved(address indexed approvedEndpoint);
    //Add timelock?

    uint256 public constant DENOMINATOR = 10000;

    uint256 public immutable genesisEpoch;
    address public daoAddress;
    address public timelock;

    address public CVE;
    address public veCVE;
    address public callOptionCVE;

    uint256 public hubChain; // Separate into fee hub vs voting hub since cveETH would be on eth mainnet whereas voting hub probably shouldnt be on eth

    address public cveLocker;
    address public gaugeController;
    address public votingHub;
    address public priceRouter;
    address public depositRouter;
    address public zroAddress;
    address public feeHub;
    address public feeRouter;

    uint256 public protocolYieldFee;
    uint256 public protocolLiquidationFee;
    uint256 public protocolLeverageFee;
    uint256 public lockBoostValue;

    mapping(address => bool) private harvester;
    mapping(address => bool) private lendingMarket;
    mapping(address => bool) private feeManager;
    mapping(address => bool) private approvedEndpoint;

    modifier onlyDaoManager() {
        require(msg.sender == daoAddress, "UNAUTHORIZED");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address dao_,
        uint256 genesisEpoch_,
        uint256 hubChain_
    ) {
        if (dao_ == address(0)) {
            dao_ = msg.sender;
        }
        daoAddress = dao_;
        genesisEpoch = genesisEpoch_;
        hubChain = hubChain_;
        emit OwnershipTransferred(address(0), daoAddress);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function isHarvester(address _address) public view returns (bool) {
        return harvester[_address];
    }

    function isLendingMarket(address _address) public view returns (bool) {
        return lendingMarket[_address];
    }

    function isFeeManager(address _address) public view returns (bool) {
        return feeManager[_address];
    }

    function isApprovedEndpoint(address _address) public view returns (bool) {
        return approvedEndpoint[_address];
    }

    function isHubChain() public view returns (bool) {
        return hubChain == block.chainid;
    }

    /*//////////////////////////////////////////////////////////////
                             SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setCVE(address CVE_) public onlyDaoManager {
        CVE = CVE_;
    }

    function setVeCVE(address veCVE_) public onlyDaoManager {
        veCVE = veCVE_;
    }

    function setCallOptionCVE(address _address) public onlyDaoManager {
        callOptionCVE = _address;
    }

    function setHubChain(address _address) public onlyDaoManager {
        //TODO
        //check for layerzero endpoint and what chain its from and message caller being authorized
        //
    }

    function setCVELocker(address _address) public onlyDaoManager {
        cveLocker = _address;
    }

    function setGaugeController(address _address) public onlyDaoManager {
        gaugeController = _address;
    }

    function setVotingHub(address _address) public onlyDaoManager {
        votingHub = _address;
    }

    function setPriceRouter(address _address) public onlyDaoManager {
        priceRouter = _address;
    }

    function setDepositRouter(address _address) public onlyDaoManager {
        depositRouter = _address;
    }

    function setZroAddress(address _address) public onlyDaoManager {
        zroAddress = _address;
    }

    function setFeeHub(address _address) public onlyDaoManager {
        feeHub = _address;
    }

    function setFeeRouter(address _address) public onlyDaoManager {
        feeRouter = _address;
    }

    function setProtocolYieldFee(uint256 _value) public onlyDaoManager {
        require(
            _value < 2000 || _value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolLiquidationFee = _value;
    }

    function setProtocolLiquidationFee(uint256 _value) public onlyDaoManager {
        require(
            _value < 500 || _value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolLiquidationFee = _value;
    }

    function setProtocolLeverageFee(uint256 _value) public onlyDaoManager {
        require(
            _value < 100 || _value == 0,
            "centralRegistry: invalid parameter"
        );
        protocolLeverageFee = _value;
    }

    function setLockBoostValue(uint256 _value) public onlyDaoManager {
        require(
            _value > DENOMINATOR || _value == 0,
            "centralRegistry: invalid parameter"
        );
        lockBoostValue = _value;
    }

    /*//////////////////////////////////////////////////////////////
                             OWNERSHIP LOGIC
    //////////////////////////////////////////////////////////////*/

    function transferOwnership(address newDaoAddress) public onlyDaoManager {
        daoAddress = newDaoAddress;
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

    function removeLendingMarket(address currentLendingMarket)
        public
        onlyDaoManager
    {
        require(lendingMarket[currentLendingMarket], "Not a Lending Market");

        delete lendingMarket[currentLendingMarket];
        emit LendingMarketRemoved(currentLendingMarket);
    }

    function addFeeManager(address newFeeManager) public onlyDaoManager {
        require(!feeManager[newFeeManager], "Already a Fee Manager");

        feeManager[newFeeManager] = true;
        emit NewFeeManager(newFeeManager);
    }

    function removeFeeManager(address currentFeeManager)
        public
        onlyDaoManager
    {
        require(feeManager[currentFeeManager], "Not a Fee Manager");

        delete feeManager[currentFeeManager];
        emit FeeManagerRemoved(currentFeeManager);
    }

    function addApprovedEndpoint(address newApprovedEndpoint)
        public
        onlyDaoManager
    {
        require(!approvedEndpoint[newApprovedEndpoint], "Already an Endpoint");

        approvedEndpoint[newApprovedEndpoint] = true;
        emit NewApprovedEndpoint(newApprovedEndpoint);
    }

    function removeApprovedEndpoint(address currentApprovedEndpoint)
        public
        onlyDaoManager
    {
        require(approvedEndpoint[currentApprovedEndpoint], "Not an Endpoint");

        delete approvedEndpoint[currentApprovedEndpoint];
        emit ApprovedEndpointRemoved(currentApprovedEndpoint);
    }
}
