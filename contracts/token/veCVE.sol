//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC20.sol";
import "../utils/SafeERC20.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/ICveLocker.sol";
import "../../interfaces/IDelegateRegistry.sol";
import "../../interfaces/ICentralRegistry.sol";

error nonTransferrable();
error continuousLock();
error notContinuousLock();
error invalidLock();
error veCVEShutdown();

contract veCVE is ERC20 {
    using SafeERC20 for IERC20;

    event Locked(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount, bool _relocked);
    event Unwrap(address indexed _to, uint256 _amount);
    event RewardPaid(address indexed _user, address indexed _rewardsToken, uint256 _amount);
    event KickReward(address indexed _user, address indexed _kicked, uint256 _amount);
    event FundedReward(address indexed _token, uint256 _amount);
    event RewardAdded(address token, uint256 amount);
    event TokenRecovered(address _token, address _to, uint256 _amount);

    struct userTokenData {
        uint256 lockedBalance;
        uint256 delegatedVotes;
        bool votesDelegated;
        uint16 locks;
    }

    struct Lock {
        uint216 amount;
        uint40 unlockTime;
    }

    uint40 public immutable genesisEpoch;
    ICentralRegistry public immutable centralRegistry;

    address public cveLocker;
    IDelegateRegistry public constant snapshot =
        IDelegateRegistry(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);
    bool public isShutdown;
    uint256 public CONTINUOUS_LOCK_BONUS = 11000;

    //Constants
    uint40 public constant CONTINUOUS_LOCK_VALUE = type(uint40).max;
    uint256 public constant EPOCH_DURATION = 2 weeks;
    uint256 public constant LOCK_DURATION_EPOCHS = 26;// in epochs
    uint256 public constant LOCK_DURATION = 52 weeks;// in seconds
    uint256 public constant DENOMINATOR = 10000;
    
    mapping(address => Lock[]) public userLocks;
    mapping(address => Lock) public investorLocks;

    //User => Epoch # => Tokens unlocked
    mapping(address => mapping(uint256 => uint256)) public userTokenUnlocksByEpoch;

    //What other chains are supported
    uint256[] public childChains;
    //Epoch # => ChainID => Tokens Locked in Epoch
    mapping(uint256 => mapping(uint256 => uint256)) public tokensLockedByChain;
    //Epoch # => Child Chains updated 
    mapping(uint256 => uint256) public childChainsUpdatedByEpoch;
    //Epoch # => Total Tokens Locked across all chains
    mapping(uint256 => uint256) public totalTokensLockedByEpoch;
    //Epoch # => Token unlocks on this chain
    mapping(uint256 => uint216) public totalUnlocksByEpoch;
    uint256 public dv;

    constructor(uint40 _genesisEpoch, ICentralRegistry _centralRegistry) ERC20("Vote Escrowed CVE", "veCVE"){
        genesisEpoch = _genesisEpoch;
        centralRegistry = _centralRegistry;
    }

    modifier onlyDaoManager () {
        require(msg.sender == centralRegistry.daoAddress(), "UNAUTHORIZED");
        _;
    }

    function currentEpoch(uint256 _time) public view returns (uint256){
        if (_time < genesisEpoch) return 0;
        return ((_time - genesisEpoch)/EPOCH_DURATION); 
    }

    function freshLockEpoch() public view returns(uint256) {
        return currentEpoch(block.timestamp) + LOCK_DURATION_EPOCHS;
    }

    function freshLockTimestamp() public view returns(uint40) {
        return uint40(genesisEpoch + (currentEpoch(block.timestamp) * EPOCH_DURATION) + LOCK_DURATION);
    }

    function lock (address _recipient, uint216 _amount, bool _continuousLock) public {
        if (isShutdown) revert veCVEShutdown();
        if (_amount == 0) revert invalidLock();

        IERC20(centralRegistry.CVE()).safeTransferFrom(msg.sender, address(this), _amount);

        _lock(_recipient, _amount, _continuousLock);
    }

    function extendLock(uint256 _lockIndex, bool _continuousLock) public {
        Lock[] storage _user = userLocks[msg.sender];
        uint40 unlockTimestamp = _user[_lockIndex].unlockTime;

        if (_lockIndex >= _user.length) revert invalidLock();// Length is index + 1 so has to be less than array length
        if (unlockTimestamp < genesisEpoch) revert invalidLock();
        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) revert continuousLock();

        uint216 tokenAmount = _user[_lockIndex].amount;
        uint256 unlockEpoch = freshLockEpoch();
        uint256 priorUnlockEpoch = currentEpoch(_user[_lockIndex].unlockTime);

        //Remove prior unlock data
        userTokenUnlocksByEpoch[msg.sender][priorUnlockEpoch] -= tokenAmount;
        totalUnlocksByEpoch[priorUnlockEpoch] -= tokenAmount;

        if (_continuousLock){
            _user[_lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE; 
        } else {
            _user[_lockIndex].unlockTime = freshLockTimestamp();

            //Add new unlock data
            userTokenUnlocksByEpoch[msg.sender][unlockEpoch] += tokenAmount;
            totalUnlocksByEpoch[unlockEpoch] += tokenAmount;
        }

        totalUnlocksByEpoch[unlockEpoch] -= tokenAmount;
    }

    function increaseAmountAndExtendLock(uint256 _amount, uint256 _lockIndex, bool _continuousLock) public {
        Lock[] storage _user = userLocks[msg.sender];

        if (isShutdown) revert veCVEShutdown();
        if (_lockIndex >= _user.length) revert invalidLock();// Length is index + 1 so has to be less than array length
        if (_amount == 0) revert invalidLock();

        IERC20(centralRegistry.CVE()).safeTransferFrom(msg.sender, address(this), _amount);

        uint40 unlockTimestamp = _user[_lockIndex].unlockTime;
        if (unlockTimestamp < genesisEpoch) revert invalidLock();
        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) revert continuousLock();

        uint216 tokenAmount = _user[_lockIndex].amount;
        uint256 unlockEpoch = freshLockEpoch();
        uint256 priorUnlockEpoch = currentEpoch(_user[_lockIndex].unlockTime);

        //Remove prior unlock data
        userTokenUnlocksByEpoch[msg.sender][priorUnlockEpoch] -= tokenAmount;
        totalUnlocksByEpoch[priorUnlockEpoch] -= tokenAmount;

        if (_continuousLock){
            _user[_lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE; 
        } else {
            _user[_lockIndex].unlockTime = freshLockTimestamp();

            //Add new unlock data if not continuous lock
            userTokenUnlocksByEpoch[msg.sender][unlockEpoch] += tokenAmount;
            totalUnlocksByEpoch[unlockEpoch] += tokenAmount;
        }

        totalUnlocksByEpoch[unlockEpoch] -= tokenAmount;
        _mint(msg.sender, _amount);
    }

    
    function combineAllLocks(bool _continuousLock) public {
        Lock[] storage _user = userLocks[msg.sender];
        uint256 locks = _user.length;
        if (locks < 2) revert invalidLock();

        uint216 lockAmount;
        uint256 priorUnlockEpoch;
        for(uint256 i; i < locks; ){
            if (_user[i].unlockTime != CONTINUOUS_LOCK_VALUE){
                priorUnlockEpoch = currentEpoch(_user[i].unlockTime);
                userTokenUnlocksByEpoch[msg.sender][priorUnlockEpoch] -= _user[i].amount;
                totalUnlocksByEpoch[priorUnlockEpoch] -= _user[i].amount;
            }
            unchecked {//Should never overflow as the total amount of tokens a user could ever lock is equal to the entire token supply
                lockAmount += _user[i++].amount;
            }
            
        }

        delete userLocks[msg.sender];
        if (_continuousLock){
            userLocks[msg.sender].push(Lock({amount: lockAmount, unlockTime: CONTINUOUS_LOCK_VALUE}));
        } else {
            userLocks[msg.sender].push(Lock({amount: lockAmount, unlockTime: freshLockTimestamp()}));
            uint256 unlockEpoch = freshLockEpoch();
            userTokenUnlocksByEpoch[msg.sender][unlockEpoch] += lockAmount;
            totalUnlocksByEpoch[unlockEpoch] += lockAmount;
        }

    }

    function processExpiredLock (address _recipient, uint256 _lockIndex) public {
        if (_lockIndex >= userLocks[msg.sender].length) revert invalidLock();// Length is index + 1 so has to be less than array length

        uint256 tokensToWithdraw = _processExpiredLock(msg.sender, _lockIndex);
        _burn(msg.sender, tokensToWithdraw);
        uint256 lockerRewards = ICveLocker(cveLocker).getRewards(msg.sender);

        // send process incentive
        if (lockerRewards > 0) {
            ICveLocker(cveLocker).claimRewards(msg.sender);
        }

        ICveLocker(cveLocker).withdrawFor(msg.sender, tokensToWithdraw);// Update deposit balance before sending funds in this call
        IERC20(centralRegistry.CVE()).safeTransfer(_recipient, tokensToWithdraw);

    }

    function disableContinuousLock(uint256 _lockIndex) public {
        Lock[] storage _user = userLocks[msg.sender];
        if (_lockIndex >= _user.length) revert invalidLock();// Length is index + 1 so has to be less than array length
        if (_user[_lockIndex].unlockTime != CONTINUOUS_LOCK_VALUE) revert notContinuousLock();

        uint216 tokenAmount = _user[_lockIndex].amount;
        uint256 unlockEpoch = freshLockEpoch();
        _user[_lockIndex].unlockTime = freshLockTimestamp();

        //Add new unlock data
        userTokenUnlocksByEpoch[msg.sender][unlockEpoch] += tokenAmount;
        totalUnlocksByEpoch[unlockEpoch] += tokenAmount;

    }

    ///////////////////////////////////////////
    ////////////// Investor Functions /////////
    ///////////////////////////////////////////

    function investorLock(address _recipient, uint216 _amount) public onlyDaoManager {
        if (isShutdown) revert veCVEShutdown();
        if (_amount == 0) revert invalidLock();
        if (investorLocks[_recipient].amount > 0) revert invalidLock(); 

        IERC20(centralRegistry.CVE()).safeTransferFrom(msg.sender, address(this), _amount);

        _investorLock(_recipient, _amount);
    }

    function processExpiredInvestorLock (address _recipient, bool rollover) public {
        Lock storage _investor = investorLocks[msg.sender];
        if (_investor.unlockTime == 0 || _investor.amount == 0) revert invalidLock();

        uint256 tokensToWithdraw = _processInvestorExpiredLock(msg.sender);
        _burn(msg.sender, tokensToWithdraw);
        uint256 lockerRewards = ICveLocker(cveLocker).getRewards(msg.sender);

        // send process incentive
        if (lockerRewards > 0) {
            ICveLocker(cveLocker).claimRewards(msg.sender);
        }

        if (rollover){
            _lock(_recipient, uint216(tokensToWithdraw), true);
        } else {

            ICveLocker(cveLocker).withdrawFor(msg.sender, tokensToWithdraw);// Update deposit balance before sending funds in this call
            IERC20(centralRegistry.CVE()).safeTransfer(_recipient, tokensToWithdraw);
        }
 
    }

    /**
     * @dev Recover token sent accidentally to contract or leftover rewards. Token shouldn't be staking token
     * @param _token token to recover
     * @param _to address to which recovered tokens are sent
     * @param _amount amount of tokens to recover
     */
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyDaoManager {
        require(_token != address(this), "cannot withdraw veCVE token");
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }
        IERC20(_token).safeTransfer(_to, _amount);

        emit TokenRecovered(_token, _to, _amount);
    }

    /**
     * @dev Shuts down the contract, unstakes all tokens, releases all locks
     */
    function shutdown() external onlyDaoManager {
        if (cveLocker != address(0)) {
            uint256 stakedBalance = ICveLocker(cveLocker).getBalance();
            ICveLocker(cveLocker).withdrawOnShutdown(stakedBalance);
        }
        isShutdown = true;
    }

    /**
     * @dev Set approvals for staking. Should be called immediately after deployment
     */
    function setStakingContractApproval() external onlyDaoManager {
        IERC20(centralRegistry.CVE()).safeIncreaseAllowance(cveLocker, type(uint256).max);
    }

    /// @notice Set the staking contract for the underlying CVE
    function setLockerContract(address _cveLocker) external onlyDaoManager {
        require(cveLocker == address(0), "already set");
        cveLocker = _cveLocker;
    }

    
    ///////////////////////////////////////////
    ////////////// Internal Functions /////////
    ///////////////////////////////////////////

    function _lock (address _recipient, uint216 _amount, bool _continuousLock) internal {

        if (_continuousLock){
            userLocks[_recipient].push(Lock({amount: _amount, unlockTime: CONTINUOUS_LOCK_VALUE}));
        } else {
            uint256 unlockEpoch = freshLockEpoch();
            userLocks[_recipient].push(Lock({amount: _amount, unlockTime: freshLockTimestamp()}));
            totalUnlocksByEpoch[unlockEpoch] += _amount;
            userTokenUnlocksByEpoch[_recipient][unlockEpoch] += _amount;
        }

        _mint(_recipient, _amount);
    }

    function _investorLock (address _recipient, uint216 _amount) internal {

        uint256 unlockEpoch = freshLockEpoch();
        investorLocks[_recipient] = Lock({amount: _amount, unlockTime: freshLockTimestamp()});
        totalUnlocksByEpoch[unlockEpoch] += _amount;
        userTokenUnlocksByEpoch[_recipient][unlockEpoch] += _amount;
        
        _mint(_recipient, _amount);
    }

    function _processExpiredLock (address _account, uint256 _lockIndex) internal returns (uint256 tokensRedeemed){
        Lock[] storage _user = userLocks[_account];
        require(block.timestamp >= _user[_lockIndex].unlockTime || isShutdown, "Lock has not expired");
        uint256 lastLockIndex = _user.length - 1;

        if (_lockIndex != lastLockIndex) {
            Lock memory tempValue = _user[_lockIndex];
            _user[_lockIndex] = _user[lastLockIndex];
            _user[lastLockIndex] = tempValue;
      }
        tokensRedeemed = _user[lastLockIndex].amount;
        _user.pop();
    }

    function _processInvestorExpiredLock (address _account) internal returns (uint256 tokensRedeemed){
        require(block.timestamp >= investorLocks[_account].unlockTime || isShutdown, "Lock has not expired");
        tokensRedeemed = investorLocks[_account].amount;
        delete investorLocks[_account];
    }

    function _OrganizeLockEntries(Lock[] memory _list, uint256 lockIndex) internal pure returns (Lock[] memory) {
      uint256 lastArrayIndex = _list.length - 1;

      if (lockIndex != lastArrayIndex) {
        Lock memory tempValue = _list[lockIndex];
        _list[lockIndex] = _list[lastArrayIndex];
        _list[lastArrayIndex] = tempValue;
      }

      return _list;
    }

    ///////////////////////////////////////////
    ////////////// View Functions /////////////
    ///////////////////////////////////////////

    function getVotes(address _user) public view returns (uint256) {
        //Todo Mai
    }

    function getVotesForSingleLock(address _user, uint256 _lockIndex) public view returns (uint256) {
        //Todo Mai
    }

    function getVotesForEpoch(address _user, uint256 _epoch) public view returns (uint256) {
        //Todo Mai
    }

    ///////////////////////////////////////////
    //////// Transfer Locked Functions ////////
    ///////////////////////////////////////////

    function transfer(address, uint256) public pure override returns (bool) {
        revert nonTransferrable(); 
    }

    function transferFrom (address, address, uint256) public pure override returns (bool) {
        revert nonTransferrable();
    }

}