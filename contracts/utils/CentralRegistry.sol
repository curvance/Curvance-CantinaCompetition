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

    address private _dao;
    address private _cveLocker;
    address private _CVE;
    address private _veCVE;
    address private _callOptionCVE;
    address private _votingHub;
    address private _priceRouter;
    address private _depositRouter;
    mapping (address => bool) private harvester;
    mapping (address => bool) private lendingMarket;

    modifier onlyDaoManager() {
        require(msg.sender == _dao, "UNAUTHORIZED");

        _;
    }

    modifier onlyHarvester() {
        require(isHarvester(msg.sender), "UNAUTHORIZED");

        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address dao_) {
        if (dao_ == address(0)){
            dao_ = msg.sender;
        }
        _dao = dao_;
        emit OwnershipTransferred(address(0), _dao);
    }

    /*//////////////////////////////////////////////////////////////
                             SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function cveLocker(address cveLocker_) public onlyDaoManager {
        _cveLocker = cveLocker_;
    }

    function setCVE(address CVE_) public onlyDaoManager {
        _CVE = CVE_;
    }

    function setVeCVE(address veCVE_) public onlyDaoManager {
        _veCVE = veCVE_;
    }

    function setCallOptionCVE(address callOptionCVE_) public onlyDaoManager {
        _callOptionCVE = callOptionCVE_;
    }

    function setVotingHub(address votingHub_) public onlyDaoManager {
        _votingHub = votingHub_;
    }

    function setPriceRouter(address priceRouter_) public onlyDaoManager {
        _priceRouter = priceRouter_;
    }

    function setDepositRouter(address depositRouter_) public onlyDaoManager {
        _depositRouter = depositRouter_;
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

    function daoAddress() public view returns (address) {
        return _dao;
    }

    function cveLocker() public view returns (address) {
        return _cveLocker;
    }

    function CVE() public view returns (address) {
        return _CVE;
    }

    function veCVE() public view returns (address) {
        return _veCVE;
    }

    function callOptionCVE() public view returns (address) {
        return _callOptionCVE;
    }

    function votingHub() public view returns (address) {
        return _votingHub;
    }

    function priceRouter() public view returns (address) {
        return _priceRouter;
    }

    function depositRouter() public view returns (address) {
        return _depositRouter;
    }

    /*//////////////////////////////////////////////////////////////
                             OWNERSHIP LOGIC
    //////////////////////////////////////////////////////////////*/

    function transferOwnership(address newDaoAddress) public onlyDaoManager {
        _dao = newDaoAddress;
        emit OwnershipTransferred(msg.sender, newDaoAddress);
    }

    function addHarvester(address newHarvester) public onlyDaoManager {
        require(!harvester[newHarvester], "Already Harvester");

        harvester[newHarvester] = true;
        emit NewHarvester(newHarvester);
    }

    function removeHarvester(address currentHarvester) public onlyDaoManager {
        require(harvester[currentHarvester], "Already Harvester");

        delete harvester[currentHarvester];
        emit HarvesterRemoved(currentHarvester);
    }

    function addLendingMarket(address newLendingMarket) public onlyDaoManager {
        require(!lendingMarket[newLendingMarket], "Already Harvester");

        lendingMarket[newLendingMarket] = true;
        emit NewLendingMarket(newLendingMarket);
    }

    function removeLendingMarket(address currentLendingMarket) public onlyDaoManager {
        require(lendingMarket[currentLendingMarket], "Already Harvester");

        delete lendingMarket[currentLendingMarket];
        emit LendingMarketRemoved(currentLendingMarket);
    }


}