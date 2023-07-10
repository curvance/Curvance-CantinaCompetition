// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/libraries/ERC20.sol";
import "../interfaces/ICveLocker.sol";
import "../interfaces/IDelegateRegistry.sol";
import "contracts/interfaces/ICentralRegistry.sol";

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

    string private _name;
    string private _symbol;

    ICentralRegistry public immutable centralRegistry;

    IERC20 public immutable cve;
    ICveLocker public immutable cveLocker;
    uint256 public immutable genesisEpoch;
    uint256 public immutable continuousLockPointMultiplier;

    
    IDelegateRegistry public constant snapshot =
        IDelegateRegistry(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);
    bool public isShutdown;

    // Constants
    // Might be better to put this in a uint256 so it doesnt need to convert to 256 for comparison, havent done gas check
    uint40 public constant CONTINUOUS_LOCK_VALUE = type(uint40).max;
    uint256 public constant EPOCH_DURATION = 2 weeks;
    uint256 public constant LOCK_DURATION_EPOCHS = 26; // in epochs
    uint256 public constant LOCK_DURATION = 52 weeks; // in seconds
    uint256 public constant DENOMINATOR = 10000;

    // User => Array of veCVE locks
    mapping(address => Lock[]) public userLocks;

    // User => Token Points
    mapping(address => uint256) public userTokenPoints;

    // User => Epoch # => Tokens unlocked
    mapping(address => mapping(uint256 => uint256))
        public userTokenUnlocksByEpoch;

    // Token Points on this chain
    uint256 chainTokenPoints;
    // Epoch # => Token unlocks on this chain
    mapping(uint256 => uint256) public chainUnlocksByEpoch;

    constructor(ICentralRegistry _centralRegistry, uint256 _continuousLockPointMultiplier) {
        _name = "Vote Escrowed CVE";
        _symbol = "veCVE";
        centralRegistry = _centralRegistry;
        genesisEpoch = centralRegistry.genesisEpoch();
        cve = IERC20(centralRegistry.CVE());
        cveLocker = ICveLocker(centralRegistry.cveLocker());
        continuousLockPointMultiplier = _continuousLockPointMultiplier;
    }

    modifier onlyDaoManager() {
        require(msg.sender == centralRegistry.daoAddress(), "UNAUTHORIZED");
        _;
    }

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Returns the current epoch for the given time
     * @param _time The timestamp for which to calculate the epoch
     * @return The current epoch
     */
    function currentEpoch(uint256 _time) public view returns (uint256) {
        if (_time < genesisEpoch) return 0;
        return ((_time - genesisEpoch) / EPOCH_DURATION);
    }

    /**
     * @notice Returns the epoch to lock until for a lock executed at this moment
     * @return The epoch
     */
    function freshLockEpoch() public view returns (uint256) {
        return currentEpoch(block.timestamp) + LOCK_DURATION_EPOCHS;
    }

    /**
     * @notice Returns the timestamp to lock until for a lock executed at this moment
     * @return The timestamp
     */
    function freshLockTimestamp() public view returns (uint40) {
        return
            uint40(
                genesisEpoch +
                    (currentEpoch(block.timestamp) * EPOCH_DURATION) +
                    LOCK_DURATION
            );
    }

    /**
    * @notice Locks a given amount of cve tokens and claims, and processes any pending locker rewards.
    * @param _amount The amount of tokens to lock.
    * @param _continuousLock Indicator of whether the lock should be continuous.
    * @param _rewardRecipient Address to receive the reward tokens.
    * @param _rewardsData Rewards data for CVE rewards locker
    * @param _params Parameters for rewards claim function.
    * @param _aux Auxiliary data.
    */
    function lock(uint256 _amount, 
                  bool _continuousLock,
                  address _rewardRecipient,
                  rewardsData memory _rewardsData,
                  bytes memory _params,
                  uint256 _aux
                  ) public {
        if (isShutdown) revert veCVEShutdown();
        if (_amount == 0) revert invalidLock();

        cve.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Claim pending locker rewards
        _claimRewards(msg.sender, _rewardRecipient, _rewardsData, _params, _aux);

        _lock(msg.sender, _amount, _continuousLock);

        emit Locked(msg.sender, _amount);
    }

    /**
    * @notice Locks a given amount of cve tokens on behalf of another user, and processes any pending locker rewards.
    * @param _recipient The address to lock tokens for.
    * @param _amount The amount of tokens to lock.
    * @param _continuousLock Indicator of whether the lock should be continuous.
    * @param _rewardRecipient Address to receive the reward tokens.
    * @param _rewardsData Rewards data for CVE rewards locker
    * @param _params Parameters for rewards claim function.
    * @param _aux Auxiliary data.
    */
    function lockFor(
        address _recipient,
        uint256 _amount,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {
        if (isShutdown) revert veCVEShutdown();
        if (_amount == 0) revert invalidLock();
        if (!centralRegistry.approvedVeCVELocker(msg.sender)) revert invalidLock();

        cve.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Claim pending locker rewards
        _claimRewards(_recipient, _rewardRecipient, _rewardsData, _params, _aux);

        _lock(_recipient, _amount, _continuousLock);

        emit Locked(_recipient, _amount);
    }

    /**
    * @notice Extends a lock of cve tokens by a given index, and processes any pending locker rewards.
    * @param _lockIndex The index of the lock to extend.
    * @param _continuousLock Indicator of whether the lock should be continuous.
    * @param _rewardRecipient Address to receive the reward tokens.
    * @param _rewardsData Rewards data for CVE rewards locker
    * @param _params Parameters for rewards claim function.
    * @param _aux Auxiliary data.
    */
    function extendLock(
        uint256 _lockIndex,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {

        if (isShutdown) revert veCVEShutdown();
        Lock[] storage _user = userLocks[msg.sender];
        uint40 unlockTimestamp = _user[_lockIndex].unlockTime;

        if (_lockIndex >= _user.length) revert invalidLock(); // Length is index + 1 so has to be less than array length
        if (unlockTimestamp < block.timestamp) revert invalidLock();
        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) revert continuousLock();

        // Claim pending locker rewards
        _claimRewards(msg.sender, _rewardRecipient, _rewardsData, _params, _aux);

        uint216 tokenAmount = _user[_lockIndex].amount;
        uint256 unlockEpoch = freshLockEpoch();
        uint256 priorUnlockEpoch = currentEpoch(_user[_lockIndex].unlockTime);

        if (_continuousLock) {
            _user[_lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE;
            _updateTokenDataFromContinuousOn(msg.sender, priorUnlockEpoch, _getContinuousPointValue(tokenAmount), tokenAmount);

        } else {
            _user[_lockIndex].unlockTime = freshLockTimestamp();
            // Updates unlock data for chain and user for new unlock time
            _updateTokenUnlockDataFromExtendedLock(msg.sender, priorUnlockEpoch, unlockEpoch, tokenAmount, tokenAmount);
        }

    }

    /**
     * @notice Increases the locked amount and extends the lock for the specified lock index,
     *         and processes any pending locker rewards.
     * @param _amount The amount to increase the lock by
     * @param _lockIndex The index of the lock to extend
     * @param _continuousLock Whether the lock should be continuous or not
     * @param _rewardRecipient Address to receive the reward tokens.
     * @param _rewardsData Rewards data for CVE rewards locker
     * @param _params Parameters for rewards claim function.
     * @param _aux Auxiliary data.
     */
    function increaseAmountAndExtendLock(
        uint256 _amount,
        uint256 _lockIndex,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {

        if (isShutdown) revert veCVEShutdown();
        if (_amount == 0) revert invalidLock();

        cve.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Claim pending locker rewards
        _claimRewards(msg.sender, _rewardRecipient, _rewardsData, _params, _aux);

        _increaseAmountAndExtendLockFor(msg.sender, _amount, _lockIndex, _continuousLock);

        emit Locked(msg.sender, _amount);
    }

    /**
     * @notice Increases the locked amount and extends the lock for the specified lock index,
     *         and processes any pending locker rewards.
     * @param _recipient The address to lock and extend tokens for
     * @param _amount The amount to increase the lock by
     * @param _lockIndex The index of the lock to extend
     * @param _continuousLock Whether the lock should be continuous or not
     * @param _rewardRecipient Address to receive the reward tokens.
     * @param _rewardsData Rewards data for CVE rewards locker
     * @param _params Parameters for rewards claim function.
     * @param _aux Auxiliary data.
     */
    function increaseAmountAndExtendLockFor(
        address _recipient,
        uint256 _amount,
        uint256 _lockIndex,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {
        if (isShutdown) revert veCVEShutdown();
        if (_amount == 0) revert invalidLock();
        if (!centralRegistry.approvedVeCVELocker(msg.sender)) revert invalidLock();

        cve.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Claim pending locker rewards
        _claimRewards(_recipient, _rewardRecipient, _rewardsData, _params, _aux);

        _increaseAmountAndExtendLockFor(_recipient, _amount, _lockIndex, _continuousLock);

        emit Locked(_recipient, _amount);

    }

        /**
     * @notice Disables a continuous lock for the user at the specified lock index,
     *         and processes any pending locker rewards.
     * @param _lockIndex The index of the lock to be disabled
     * @param _rewardRecipient Address to receive the reward tokens.
     * @param _rewardsData Rewards data for CVE rewards locker
     * @param _params Parameters for rewards claim function.
     * @param _aux Auxiliary data.
     */
    function disableContinuousLock(
        uint256 _lockIndex,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {
        Lock[] storage _user = userLocks[msg.sender];
        if (_lockIndex >= _user.length) revert invalidLock(); // Length is index + 1 so has to be less than array length
        if (_user[_lockIndex].unlockTime != CONTINUOUS_LOCK_VALUE)
            revert notContinuousLock();

        // Claim pending locker rewards
        _claimRewards(msg.sender, _rewardRecipient, _rewardsData, _params, _aux);

        uint216 tokenAmount = _user[_lockIndex].amount;
        uint256 unlockEpoch = freshLockEpoch();
        _user[_lockIndex].unlockTime = freshLockTimestamp();

        _reduceTokenData(
            msg.sender, unlockEpoch,  _getContinuousPointValue(tokenAmount) - tokenAmount, tokenAmount);

    }

    /**
     * @notice Combines all locks into a single lock,
     *         and processes any pending locker rewards.
     * @param _continuousLock Whether the combined lock should be continuous or not
     * @param _rewardRecipient Address to receive the reward tokens.
     * @param _rewardsData Rewards data for CVE rewards locker
     * @param _params Parameters for rewards claim function.
     * @param _aux Auxiliary data.
     */
    function combineLocks(
        uint256[] calldata lockIndexes,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {
        
        // Claim pending locker rewards
        _claimRewards(msg.sender, _rewardRecipient, _rewardsData, _params, _aux);

        Lock[] storage _user = userLocks[msg.sender];
        uint256 lastLockIndex = _user.length - 1;
        uint256 locksToCombineIndex = lockIndexes.length - 1;

        // check that theres are at least 2 locks to combine, otherwise the inputs are misconfigured
        // check that the user has sufficient locks to combine, then decrement 1 so we can use it to go through the lockIndexes array backwards
        if (locksToCombineIndex > 0 && locksToCombineIndex <= lastLockIndex) revert invalidLock();

        
        uint256 lockAmount;
        Lock storage userLock;
        uint256 previousLockIndex;
        uint256 excessPoints;

        for (uint256 i = locksToCombineIndex; i > 0;) {

            if (i != locksToCombineIndex){ // If this is the first iteration we do not need to check for sorted lockIndexes 
                require (lockIndexes[i] < previousLockIndex, "veCVE: lockIndexes misconfigured");
            }

            previousLockIndex = lockIndexes[i];

            if (previousLockIndex != lastLockIndex) {
                Lock memory tempValue = _user[previousLockIndex];
                _user[previousLockIndex] = _user[lastLockIndex];
                _user[lastLockIndex] = tempValue;
            }

            userLock = _user[lastLockIndex];

            if (userLock.unlockTime != CONTINUOUS_LOCK_VALUE) {
                // Remove unlock data if there is any
                _reduceTokenUnlocks(msg.sender, currentEpoch(userLock.unlockTime), userLock.amount);
            } else {
                unchecked {
                    excessPoints += _getContinuousPointValue(userLock.amount) - userLock.amount;
                } // calculate and sum how many additional points they got from their continuous lock 
            }

            unchecked {// Should never overflow as the total amount of tokens a user could ever lock is equal to the entire token supply
                // decrement the array length since we need to pop the last entry
                lockAmount += _user[lastLockIndex--].amount;
                i--;
            }

            _user.pop();

        }

        if (excessPoints > 0) _reduceTokenPoints(msg.sender, excessPoints);
        

        userLock = _user[lockIndexes[0]];// We will combine the deleted locks into the first lock in the array
        uint256 epoch;

        if (_continuousLock) {
            
            if (userLock.unlockTime != CONTINUOUS_LOCK_VALUE) {
                // Finalize new combined lock amount
                lockAmount += userLock.amount;
                
                // Remove the previous unlock data 
                epoch = currentEpoch(userLock.unlockTime);
                _reduceTokenUnlocks(msg.sender, epoch, userLock.amount);

                // Give the user extra token points from continuous lock being enabled
                _incrementTokenPoints(msg.sender, _getContinuousPointValue(lockAmount) - lockAmount);

                // Assign new lock data
                userLock.amount = uint216(lockAmount);
                userLock.unlockTime = CONTINUOUS_LOCK_VALUE;
                 
            } else {
                // Give the user extra token points from continuous lock being enabled, but only from the other locks
                _incrementTokenPoints(msg.sender, _getContinuousPointValue(lockAmount) - lockAmount);

                // Finalize new combined lock amount
                lockAmount += userLock.amount;
                // Assign new lock data
                userLock.amount = uint216(lockAmount);
            }
            
        } else {

            require(userLock.unlockTime != CONTINUOUS_LOCK_VALUE, "veCVE: Disable combined lock continuous mode first");
            // Remove the previous unlock data 
            _reduceTokenUnlocks(msg.sender, currentEpoch(userLock.unlockTime), userLock.amount);

            // Finalize new combined lock amount
            lockAmount += userLock.amount;
            // Assign new lock data
            userLock.amount = uint216(lockAmount);
            userLock.unlockTime = freshLockTimestamp();

            // Record the new unlock data
            _incrementTokenUnlocks(msg.sender, freshLockEpoch(), lockAmount);

        }

    }

    /**
     * @notice Combines all locks into a single lock,
     *         and processes any pending locker rewards.
     * @param _continuousLock Whether the combined lock should be continuous or not
     * @param _rewardRecipient Address to receive the reward tokens.
     * @param _rewardsData Rewards data for CVE rewards locker
     * @param _params Parameters for rewards claim function.
     * @param _aux Auxiliary data.
     */
    function combineAllLocks(
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {
        // Claim pending locker rewards
        _claimRewards(msg.sender, _rewardRecipient, _rewardsData, _params, _aux);

        // Need to have this check after _claimRewards as the user could have created a new lock with their pending rewards
        Lock[] storage _user = userLocks[msg.sender];
        uint256 locks = _user.length;
        if (locks < 2) revert invalidLock();

        uint256 excessPoints;
        uint256 lockAmount;
        Lock storage userLock;

        for (uint256 i; i < locks; ) {
            userLock = _user[i];

            if (userLock.unlockTime != CONTINUOUS_LOCK_VALUE) {
                // Remove unlock data if there is any
                _reduceTokenUnlocks(msg.sender, currentEpoch(userLock.unlockTime), userLock.amount);
            } else {
                unchecked {
                    excessPoints += _getContinuousPointValue(userLock.amount) - userLock.amount;
                } // calculate and sum how many additional points they got from their continuous lock 
            }

            unchecked {
                // Should never overflow as the total amount of tokens a user could ever lock is equal to the entire token supply
                lockAmount += _user[i++].amount;
            }
        }

        // Remove the users excess points from their continuous locks, if any
        if (excessPoints > 0) _reduceTokenPoints(msg.sender, excessPoints);
        // Remove the users locks
        delete userLocks[msg.sender];

        if (_continuousLock) {
            userLocks[msg.sender].push(
                Lock({ amount: uint216(lockAmount), unlockTime: CONTINUOUS_LOCK_VALUE })
            );
            // Give the user extra token points from continuous lock being enabled
            _incrementTokenPoints(msg.sender, _getContinuousPointValue(lockAmount) - lockAmount);
            
        } else {
            userLocks[msg.sender].push(
                Lock({ amount: uint216(lockAmount), unlockTime: freshLockTimestamp() })
            );
            // Record the new unlock data
            _incrementTokenUnlocks(msg.sender, freshLockEpoch(), lockAmount);
            
        }
    }



    /**
     * @notice Processes an expired lock for the specified lock index
     * @param _recipient The address to send unlocked tokens to
     * @param _lockIndex The index of the lock to process
     * @param _relock Whether the expired lock should be relocked in a fresh lock
     * @param _continuousLock Whether the relocked fresh lock should be continuous or not
     * @param _rewardRecipient Address to receive the reward tokens.
     * @param _rewardsData Rewards data for CVE rewards locker
     * @param _params Parameters for rewards claim function.
     * @param _aux Auxiliary data.
     */
    function processExpiredLock(
        address _recipient,
        uint256 _lockIndex,
        bool _relock,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) public {
        if (_lockIndex >= userLocks[msg.sender].length) revert invalidLock(); // Length is index + 1 so has to be less than array length
        Lock[] storage _user = userLocks[msg.sender];
        require(
            block.timestamp >= _user[_lockIndex].unlockTime || isShutdown,
            "veCVE: Lock has not expired"
        );

        // Claim pending locker rewards
        _claimRewards(_recipient, _rewardRecipient, _rewardsData, _params, _aux);

        uint256 lockAmount = _user[_lockIndex].amount;

        if (_relock) {
            // Token points will be caught up by _claimRewards call so we can treat this as a fresh lock and increment rewards again
            _lock(_recipient, lockAmount, _continuousLock);
        } else {

            _burn(msg.sender, lockAmount);
            _processExpiredLock(_user, _lockIndex);

            cve.safeTransferFrom(
                address(this),
                msg.sender,
                lockAmount
            );
            
            emit Unlocked(msg.sender, lockAmount);
        }

    }

    /**
    * @notice Updates user points by reducing the amount that gets unlocked in a specific epoch.
    * @param _user The address of the user whose points are to be updated.
    * @param _epoch The epoch from which the unlock amount will be reduced.
    * @dev This function is only called when userTokenUnlocksByEpoch[_user][_epoch] > 0 so do not need to check here
    */
    function updateUserPoints(address _user, uint256 _epoch) public {
        require(address(cveLocker) == msg.sender, "veCVE: only CVE Locker can update user points");

        unchecked {
            userTokenPoints[_user] -= userTokenUnlocksByEpoch[_user][_epoch];
        } 
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
        require(
            _token != address(cve),
            "cannot withdraw cve token"
        );
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
        isShutdown = true;
        // notify cveLocker of shutdown
    }

    ///////////////////////////////////////////
    ////////////// Internal Functions /////////
    ///////////////////////////////////////////

    /// See claimRewardsFor in CVE Locker
    function _claimRewards(
        address _user, 
        address _recipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux) internal {
            uint256 epoches = cveLocker.epochsToClaim(_user);
            if (epoches > 0) {
                cveLocker.claimRewardsFor(_user, _recipient, epoches, _rewardsData, _params, _aux);
            }
        }

    /**
     * @notice Internal function to lock tokens for a user
     * @param _recipient The address of the user receiving the lock
     * @param _amount The amount of tokens to lock
     * @param _continuousLock Whether the lock is continuous or not
     */
    function _lock(
        address _recipient,
        uint256 _amount,
        bool _continuousLock
    ) internal {
        if (_continuousLock) {
            userLocks[_recipient].push(
                Lock({
                    amount: uint216(_amount),
                    unlockTime: CONTINUOUS_LOCK_VALUE
                })
            );
            _incrementTokenPoints(_recipient, _getContinuousPointValue(_amount));
        } else {
            uint256 unlockEpoch = freshLockEpoch();
            userLocks[_recipient].push(
                Lock({
                    amount: uint216(_amount),
                    unlockTime: freshLockTimestamp()
                })
            );
            _incrementTokenData(_recipient, unlockEpoch, _amount);

        }

        _mint(_recipient, _amount);
    }

    /**
     * @notice Internal function to handle whenever a user needs an increase to a locked amount and extended lock
     * @param _recipient The address to lock and extend tokens for
     * @param _amount The amount to increase the lock by
     * @param _lockIndex The index of the lock to extend
     * @param _continuousLock Whether the lock should be continuous or not
     */
    function _increaseAmountAndExtendLockFor(
        address _recipient,
        uint256 _amount,
        uint256 _lockIndex,
        bool _continuousLock
    ) internal {

        Lock[] storage _user = userLocks[_recipient];
        if (_lockIndex >= _user.length) revert invalidLock(); // Length is index + 1 so has to be less than array length

        uint40 unlockTimestamp = _user[_lockIndex].unlockTime;
        
        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) {

            // Increment the chain and user token point balance 
            _incrementTokenPoints(_recipient, _getContinuousPointValue(_amount));
            // Update the lock value to include the new locked tokens
            _user[_lockIndex].amount = uint216(_user[_lockIndex].amount + _amount);

        } else {// User was not continuous locked prior so we will need to clean up their unlock data
            if (unlockTimestamp < block.timestamp) revert invalidLock();

            uint256 previousTokenAmount = _user[_lockIndex].amount;
            uint256 newTokenAmount = previousTokenAmount + _amount;
            uint256 priorUnlockEpoch = currentEpoch(_user[_lockIndex].unlockTime);

            if (_continuousLock) {
            _user[_lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE;
            // Decrement their previous non-continuous lock value and increase points by the continuous lock value 
            _updateTokenDataFromContinuousOn(_recipient, 
            priorUnlockEpoch, _getContinuousPointValue(newTokenAmount) - previousTokenAmount, previousTokenAmount);

            } else {
                _user[_lockIndex].unlockTime = freshLockTimestamp();
                uint256 unlockEpoch = freshLockEpoch();
                // Update unlock data removing the old lock amount from old epoch and add the new lock amount to the new epoch
                _updateTokenUnlockDataFromExtendedLock(_recipient, priorUnlockEpoch, unlockEpoch, previousTokenAmount, newTokenAmount);
                
                // Increment the chain and user token point balance 
                _incrementTokenPoints(_recipient, _amount);

            }

            _user[_lockIndex].amount = uint216(newTokenAmount);
        }

        _mint(msg.sender, _amount);
    }

    /**
     * @notice Processes the expired lock for a user
     * @param _user An array of locks for the user whose expired lock is being processed
     * @param _lockIndex The index of the lock to be processed
     */
    function _processExpiredLock(
        Lock[] storage _user,
        uint256 _lockIndex
    ) internal {
        
        uint256 lastLockIndex = _user.length - 1;

        if (_lockIndex != lastLockIndex) {
            Lock memory tempValue = _user[_lockIndex];
            _user[_lockIndex] = _user[lastLockIndex];
            _user[lastLockIndex] = tempValue;
        }
        _user.pop();

    }


        /**
     * @notice Increment token data
     * @dev Increments both the token points and token unlocks for the chain and user. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _points The number of points to add.
     */
    function _incrementTokenData(
        address _user,
        uint256 _epoch,
        uint256 _points
    ) internal {
        unchecked {
            chainTokenPoints += _points;
            chainUnlocksByEpoch[_epoch] += _points;
            userTokenPoints[_user] += _points;
            userTokenUnlocksByEpoch[_user][_epoch] += _points;
        } // only modified on locking/unlocking veCVE and we know theres never more than 420m so this should never over/underflow
    }

    /**
     * @notice Reduce token data
     * @dev Reduces both the token points and token unlocks for the chain and user for a given epoch. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _epoch The epoch to reduce the data.
     * @param _tokenPoints The token points to reduce.
     * @param _tokenUnlocks The token unlocks to reduce.
     */
    function _reduceTokenData(
        address _user,
        uint256 _epoch,
        uint256 _tokenPoints,
        uint256 _tokenUnlocks
    ) internal {
        unchecked {
            chainTokenPoints -= _tokenPoints;
            chainUnlocksByEpoch[_epoch] -= _tokenUnlocks;
            userTokenPoints[_user] -= _tokenPoints;
            userTokenUnlocksByEpoch[_user][_epoch] -= _tokenUnlocks;
        } // only modified on locking/unlocking veCVE and we know theres never more than 420m so this should never over/underflow
    }

    /**
     * @notice Increment token points
     * @dev Increments the token points of the chain and user. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _points The number of points to add.
     */
    function _incrementTokenPoints(
        address _user,
        uint256 _points
    ) internal {
        unchecked {
            chainTokenPoints += _points;
            userTokenPoints[_user] += _points;
        } // We know theres never more than 420m so this should never over/underflow
    }

/**
     * @notice Reduce token points
     * @dev Reduces the token points of the chain and user. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _points The number of points to reduce.
     */
    function _reduceTokenPoints(
        address _user,
        uint256 _points
    ) internal {
        unchecked {
            chainTokenPoints -= _points;
            userTokenPoints[_user] -= _points;
        } // We know theres never more than 420m so this should never over/underflow
    }

    /**
     * @notice Increment token unlocks
     * @dev Increments the token unlocks of the chain and user for a given epoch. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _epoch The epoch to add the unlocks.
     * @param _points The number of points to add.
     */
    function _incrementTokenUnlocks(
        address _user,
        uint256 _epoch,
        uint256 _points
    ) internal {
        // might not need token unlock functions
        unchecked {
            chainUnlocksByEpoch[_epoch] += _points;
            userTokenUnlocksByEpoch[_user][_epoch] += _points;
        } // We know theres never more than 420m so this should never over/underflow
    }

    /**
     * @notice Reduce token unlocks
     * @dev Reduces the token unlocks of the chain and user for a given epoch. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _epoch The epoch to reduce the unlocks.
     * @param _points The number of points to reduce.
     */
    function _reduceTokenUnlocks(
        address _user,
        uint256 _epoch,
        uint256 _points
    ) internal {
        unchecked {
            chainUnlocksByEpoch[_epoch] -= _points;
            userTokenUnlocksByEpoch[_user][_epoch] -= _points;
        } // We know theres never more than 420m so this should never over/underflow
    }

    /**
     * @notice Update token unlock data from an extended lock that is not continuous
     * @dev Updates the token points and token unlocks for the chain and user from a continuous lock for a given epoch. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _previousEpoch The previous unlock epoch.
     * @param _epoch The new unlock epoch.
     * @param _previousPoints The previous points to remove from the old unlock time.
     * @param _points The new token points to add for the new unlock time.
     */
    function _updateTokenUnlockDataFromExtendedLock(
        address _user,
        uint256 _previousEpoch,
        uint256 _epoch,
        uint256 _previousPoints,
        uint256 _points
    ) internal {
        unchecked {
            chainUnlocksByEpoch[_previousEpoch] -= _previousPoints;
            userTokenUnlocksByEpoch[_user][_previousEpoch] -= _previousPoints;
            chainUnlocksByEpoch[_epoch] += _points;
            userTokenUnlocksByEpoch[_user][_epoch] += _points;
        } // We know theres never more than 420m so this should never over/underflow
    }

    /**
     * @notice Update token data from continuous lock on
     * @dev Updates the token points and token unlocks for the chain and user from a continuous lock for a given epoch. Can only be called by the VeCVE contract.
     * @param _user The address of the user.
     * @param _epoch The epoch to update the data.
     * @param _tokenPoints The token points to add.
     * @param _tokenUnlocks The token unlocks to reduce.
     */
    function _updateTokenDataFromContinuousOn(
        address _user,
        uint256 _epoch,
        uint256 _tokenPoints,
        uint256 _tokenUnlocks
    ) internal {
        unchecked {
            chainTokenPoints += _tokenPoints;
            chainUnlocksByEpoch[_epoch] -= _tokenUnlocks;
            userTokenPoints[_user] += _tokenPoints;
            userTokenUnlocksByEpoch[_user][_epoch] -= _tokenUnlocks;
        } // We know theres never more than 420m so this should never over/underflow
    }

    /**
    * @notice Calculates the continuous lock token point value for _basePoints.
    * @param _basePoints The token points to be used in the calculation.
    * @return The calculated continuous lock token point value.
    */
    function _getContinuousPointValue(uint256 _basePoints) internal view returns (uint256) {
        unchecked {
            return ((_basePoints * continuousLockPointMultiplier) / DENOMINATOR);
        } 
    }

    /**
    * @notice Calculates the continuous lock gauge voting power value for _basePoints.
    * @param _basePoints The token points to be used in the calculation.
    * @return The calculated continuous lock gauge voting power value.
    */
    function _getContinuousVoteValue(uint256 _basePoints) internal view returns (uint256) {
        unchecked {
            return ((_basePoints * centralRegistry.voteBoostValue()) / DENOMINATOR);
        } 
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
        for (uint256 i; i < locks; ) {
            unchecked {
                votes += getVotesForSingleLockForTime(_user, i++, block.timestamp);
            } // Based on CVE maximum supply this cannot overflow
        }

        return votes;
    }

    /**
     * @notice Calculates the total votes for a user based on their locks at a specific epoch
     * @param _user The address of the user to calculate votes for
     * @param _epoch The epoch for which the votes are calculated
     * @return The total number of votes for the user at the specified epoch
     */
    function getVotesForEpoch(
        address _user,
        uint256 _epoch
    ) public view returns (uint256) {
        uint256 locks = userLocks[_user].length;
        if (locks == 0) return 0;
        if (_epoch == 0) return 0;

        uint256 timestamp = genesisEpoch + (EPOCH_DURATION * (_epoch - 1));
        uint256 votes;
        for (uint256 i; i < locks; ) {
            unchecked {
                votes += getVotesForSingleLockForTime(_user, i++, timestamp);
            } // Based on CVE maximum supply this cannot overflow
        }

        return votes;
    }

    /**
     * @notice Calculates the votes for a single lock of a user based on a specific timestamp
     * @param _user The address of the user whose lock is being used for the calculation
     * @param _lockIndex The index of the lock to calculate votes for
     * @param _time The timestamp to use for the calculation
     * @return The number of votes for the specified lock at the given timestamp
     */
    function getVotesForSingleLockForTime(
        address _user,
        uint256 _lockIndex,
        uint256 _time
    ) public view returns (uint256) {
        Lock storage userLock = userLocks[_user][_lockIndex];
        if (userLock.unlockTime == CONTINUOUS_LOCK_VALUE)
            return _getContinuousVoteValue(userLock.amount);
        if (userLock.unlockTime < _time) return 0;

        // Equal to epochsLeft = (userLock.unlockTime - _time) / EPOCH_DURATION
        // (userLock.amount * epochsLeft) / LOCK_DURATION_EPOCHS
        return (userLock.amount * ((userLock.unlockTime - _time) / EPOCH_DURATION)) / LOCK_DURATION_EPOCHS;

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
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert nonTransferrable();
    }
}
