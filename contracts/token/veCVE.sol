//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC20.sol";
import "../interfaces/ICveLocker.sol";
import "../interfaces/IDelegateRegistry.sol";
import "../interfaces/ICentralRegistry.sol";

error nonTransferrable();
error continuousLock();
error notContinuousLock();
error invalidLock();
error veCVEShutdown();

contract veCVE is ERC20 {
    using SafeERC20 for IERC20;

    event Locked(address indexed _user, uint256 _amount);
    event Unlocked(address indexed _user, uint256 _amount);
    event TokenRecovered(address _token, address _to, uint256 _amount);

    struct Lock {
        uint216 amount;
        uint40 unlockTime;
    }

    uint256 public immutable genesisEpoch;
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
        //MoveHelpers to Central Registry
    mapping(address => bool) public authorizedHelperContract;

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
    mapping(uint256 => uint256) public totalUnlocksByEpoch;

    constructor(ICentralRegistry _centralRegistry) ERC20("Vote Escrowed CVE", "veCVE"){
        centralRegistry = _centralRegistry;
        genesisEpoch = centralRegistry.genesisEpoch();
    }

    modifier onlyDaoManager () {
        require(msg.sender == centralRegistry.daoAddress(), "UNAUTHORIZED");
        _;
    }

    /**
     * @notice Returns the current epoch for the given time
     * @param _time The timestamp for which to calculate the epoch
     * @return The current epoch
     */
    function currentEpoch(uint256 _time) public view returns (uint256){
        if (_time < genesisEpoch) return 0;
        return ((_time - genesisEpoch)/EPOCH_DURATION); 
    }

    /**
     * @notice Returns the epoch to lock until for a lock executed at this moment
     * @return The epoch
     */
    function freshLockEpoch() public view returns(uint256) {
        return currentEpoch(block.timestamp) + LOCK_DURATION_EPOCHS;
    }

     /**
     * @notice Returns the timestamp to lock until for a lock executed at this moment
     * @return The timestamp
     */
    function freshLockTimestamp() public view returns(uint40) {
        return uint40(genesisEpoch + (currentEpoch(block.timestamp) * EPOCH_DURATION) + LOCK_DURATION);
    }

    /**
     * @notice Locks the specified amount of CVE tokens for the recipient
     * @param _amount The amount of tokens to lock
     * @param _continuousLock Whether the lock should be continuous or not
     */
    function lock (uint216 _amount, bool _continuousLock) public {
        if (isShutdown) revert veCVEShutdown();
        if (_amount == 0) revert invalidLock();

        IERC20(centralRegistry.CVE()).safeTransferFrom(msg.sender, address(this), _amount);

        _lock(msg.sender, _amount, _continuousLock);
    }

    /**
     * @notice Locks the specified amount of CVE tokens for the recipient
     * @param _recipient The address to lock tokens for
     * @param _amount The amount of tokens to lock
     * @param _continuousLock Whether the lock should be continuous or not
     */
    function lockFor (address _recipient, uint256 _amount, bool _continuousLock) public {
        if (isShutdown) revert veCVEShutdown();
        if (!authorizedHelperContract[msg.sender]) revert invalidLock();
        if (_amount == 0) revert invalidLock();

        IERC20(centralRegistry.CVE()).safeTransferFrom(msg.sender, address(this), _amount);

        _lock(_recipient, _amount, _continuousLock);
    }

    /**
     * @notice Extends the lock for the specified lock index
     * @param _lockIndex The index of the lock to extend
     * @param _continuousLock Whether the lock should be continuous or not
     */
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

        //totalUnlocksByEpoch[unlockEpoch] -= tokenAmount;
    }

    /**
     * @notice Increases the locked amount and extends the lock for the specified lock index
     * @param _amount The amount to increase the lock by
     * @param _lockIndex The index of the lock to extend
     * @param _continuousLock Whether the lock should be continuous or not
     */
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

        //totalUnlocksByEpoch[unlockEpoch] -= tokenAmount;
        _mint(msg.sender, _amount);
    }

    /**
     * @notice Increases the locked amount and extends the lock for the specified lock index
     * @param _recipient The address to lock and extend tokens for
     * @param _amount The amount to increase the lock by
     * @param _lockIndex The index of the lock to extend
     * @param _continuousLock Whether the lock should be continuous or not
     */
    function increaseAmountAndExtendLockFor(address _recipient, uint256 _amount, uint256 _lockIndex, bool _continuousLock) public {
        Lock[] storage _user = userLocks[_recipient];

        if (isShutdown) revert veCVEShutdown();
        if (!authorizedHelperContract[msg.sender]) revert invalidLock();
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
        userTokenUnlocksByEpoch[_recipient][priorUnlockEpoch] -= tokenAmount;
        totalUnlocksByEpoch[priorUnlockEpoch] -= tokenAmount;

        if (_continuousLock){
            _user[_lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE; 
        } else {
            _user[_lockIndex].unlockTime = freshLockTimestamp();

            //Add new unlock data if not continuous lock
            userTokenUnlocksByEpoch[_recipient][unlockEpoch] += tokenAmount;
            totalUnlocksByEpoch[unlockEpoch] += tokenAmount;
        }

        //totalUnlocksByEpoch[unlockEpoch] -= tokenAmount;
        _mint(_recipient, _amount);
    }

    /**
     * @notice Combines all locks into a single lock
     * @param _continuousLock Whether the combined lock should be continuous or not
     */
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

    /**
     * @notice Processes an expired lock for the specified lock index
     * @param _recipient The address to send unlocked tokens to
     * @param _lockIndex The index of the lock to process
     */
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
        emit Unlocked(msg.sender, tokensToWithdraw);
    }

    /**
    * @notice Disables a continuous lock for the user at the specified lock index
    * @param _lockIndex The index of the lock to be disabled
    */
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

    /**
    * @notice Recover tokens sent accidentally to the contract or leftover rewards (excluding veCVE tokens)
    * @param _token The address of the token to recover
    * @param _to The address to receive the recovered tokens
    * @param _amount The amount of tokens to recover
    */
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyDaoManager {
        require(_token != centralRegistry.CVE(), "cannot withdraw veCVE token");
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }
        IERC20(_token).safeTransfer(_to, _amount);

        emit TokenRecovered(_token, _to, _amount);
    }

    /**
    * @notice Shuts down the contract, unstakes all tokens, and releases all locks
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

    /**
    * @notice Sets the locker contract for the underlying CVE tokens
    * @param _cveLocker The address of the locker contract to be set
    */
    function setLockerContract(address _cveLocker) external onlyDaoManager {
        require(cveLocker == address(0), "already set");
        cveLocker = _cveLocker;
    }

    /**
    * @notice Adds an address as an authorized helper contract
    * @param _helper The address of the locker contract to be set
    */
    function addAuthorizedHelper(address _helper) external onlyDaoManager {
        require(_helper != address(0), "Invalid Helper Address");
        require(!authorizedHelperContract[_helper], "Invalid Operation");
        authorizedHelperContract[_helper] = true;
    }

    /**
    * @notice Removes an address as an authorized helper contract
    * @param _helper The address of the locker contract to be set
    */
    function removeAuthorizedHelper(address _helper) external onlyDaoManager {
        require(_helper != address(0), "Invalid Helper Address");
        require(authorizedHelperContract[_helper], "Invalid Operation");
        delete authorizedHelperContract[_helper];
    }

    
    ///////////////////////////////////////////
    ////////////// Internal Functions /////////
    ///////////////////////////////////////////

    /**
     * @notice Internal function to lock tokens for a user
     * @param _recipient The address of the user receiving the lock
     * @param _amount The amount of tokens to lock
     * @param _continuousLock Whether the lock is continuous or not
     */
    function _lock (address _recipient, uint256 _amount, bool _continuousLock) internal {

        if (_continuousLock){
            userLocks[_recipient].push(Lock({amount: uint216(_amount), unlockTime: CONTINUOUS_LOCK_VALUE}));
        } else {
            uint256 unlockEpoch = freshLockEpoch();
            userLocks[_recipient].push(Lock({amount: uint216(_amount), unlockTime: freshLockTimestamp()}));
            totalUnlocksByEpoch[unlockEpoch] += _amount;
            userTokenUnlocksByEpoch[_recipient][unlockEpoch] += _amount;
        }

        _mint(_recipient, _amount);
    }

    /**
    * @notice Processes the expired lock for a user and returns the number of tokens redeemed
    * @param _account The address of the user whose lock is being processed
    * @param _lockIndex The index of the lock to be processed
    * @return tokensRedeemed The number of tokens redeemed from the expired lock
    */
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

    /**
    * @notice Reorganizes lock entries in the given lock array by swapping the lock at the specified index with the last lock
    * @param _list The array of lock entries to be reorganized
    * @param lockIndex The index of the lock to be swapped with the last lock in the array
    * @return The reorganized lock array
    */
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

    /**
    * @notice Calculates the total votes for a user based on their current locks
    * @param _user The address of the user to calculate votes for
    * @return The total number of votes for the user
    */
    function getVotes(address _user) public view returns (uint256) {
        uint256 locks = userLocks[_user].length;
        if (locks == 0) return 0;

        uint256 votes;
        for(uint256 i; i < locks; ){
            votes += getVotesForSingleLock(_user, i++);
        
        }

        return votes;
    }

    /**
    * @notice Calculates the total votes for a user based on their locks at a specific epoch
    * @param _user The address of the user to calculate votes for
    * @param _epoch The epoch for which the votes are calculated
    * @return The total number of votes for the user at the specified epoch
    */
    function getVotesForEpoch(address _user, uint256 _epoch) public view returns (uint256) {
        uint256 locks = userLocks[_user].length;
        if (locks == 0) return 0;
        if (_epoch == 0) return 0;

        uint256 timestamp = genesisEpoch + (EPOCH_DURATION * (_epoch - 1));
        uint256 votes;
        for(uint256 i; i < locks; ){
            votes += getVotesForSingleLockForTime(_user, i++, timestamp);
        }

        return votes;
    }

    /**
    * @notice Calculates the votes for a single lock of a user based on the current timestamp
    * @param _user The address of the user whose lock is being used for the calculation
    * @param _lockIndex The index of the lock to calculate votes for
    * @return The number of votes for the specified lock
    */
    function getVotesForSingleLock(address _user, uint256 _lockIndex) public view returns (uint256) {
        Lock storage userLock = userLocks[_user][_lockIndex];
        if (userLock.unlockTime == CONTINUOUS_LOCK_VALUE) return (userLock.amount * 11000)/DENOMINATOR;
        if (userLock.unlockTime < block.timestamp) return 0;

        uint256 epochsLeft = (userLock.unlockTime - block.timestamp)/EPOCH_DURATION;
        return (userLock.amount * epochsLeft)/LOCK_DURATION_EPOCHS;
    }

    /**
    * @notice Calculates the votes for a single lock of a user based on a specific timestamp
    * @param _user The address of the user whose lock is being used for the calculation
    * @param _lockIndex The index of the lock to calculate votes for
    * @param _time The timestamp to use for the calculation
    * @return The number of votes for the specified lock at the given timestamp
    */
    function getVotesForSingleLockForTime(address _user, uint256 _lockIndex, uint256 _time) public view returns (uint256) {
        Lock storage userLock = userLocks[_user][_lockIndex];
        if (userLock.unlockTime == CONTINUOUS_LOCK_VALUE) return (userLock.amount * 11000)/DENOMINATOR;
        if (userLock.unlockTime < _time) return 0;

        uint256 epochsLeft = (userLock.unlockTime - _time)/EPOCH_DURATION;
        return (userLock.amount * epochsLeft)/LOCK_DURATION_EPOCHS;
    }

    

    ///////////////////////////////////////////
    //////// Transfer Locked Functions ////////
    ///////////////////////////////////////////

    /**
    * @notice Overridden transfer function to prevent token transfers
    * @dev This function always reverts, as the token is non-transferrable
    * @return This function always reverts and does not return a value
    */
    function transfer(address, uint256) public pure override returns (bool) {
        revert nonTransferrable(); 
    }

    /**
    * @notice Overridden transferFrom function to prevent token transfers
    * @dev This function always reverts, as the token is non-transferrable
    * @return This function always reverts and does not return a value
    */
    function transferFrom (address, address, uint256) public pure override returns (bool) {
        revert nonTransferrable();
    }

}