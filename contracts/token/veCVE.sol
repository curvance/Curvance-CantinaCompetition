// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICveLocker, RewardsData } from "contracts/interfaces/ICveLocker.sol";
import { IDelegateRegistry } from "contracts/interfaces/IDelegateRegistry.sol";

contract veCVE is ERC20 {
    /// STRUCTS ///

    struct Lock {
        uint216 amount;
        uint40 unlockTime;
    }

    /// CONSTANTS ///

    IDelegateRegistry public constant snapshot =
        IDelegateRegistry(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);

    // Might be better to put this in a uint256 so it doesnt need to
    // convert to 256 for comparison, havent done gas check
    uint40 public constant CONTINUOUS_LOCK_VALUE = type(uint40).max;
    uint256 public constant EPOCH_DURATION = 2 weeks;
    uint256 public constant LOCK_DURATION_EPOCHS = 26; // in epochs
    uint256 public constant LOCK_DURATION = 52 weeks; // in seconds
    uint256 public constant DENOMINATOR = 10000;

    ICentralRegistry public immutable centralRegistry;

    address public immutable cve;

    ICveLocker public immutable cveLocker;

    uint256 public immutable genesisEpoch;

    uint256 public immutable continuousLockPointMultiplier;

    /// STORAGE ///
    string private _name;
    string private _symbol;
    bool public isShutdown;

    // User => Array of veCVE locks
    mapping(address => Lock[]) public userLocks;

    // User => Token Points
    mapping(address => uint256) public userTokenPoints;

    // User => Epoch # => Tokens unlocked
    mapping(address => mapping(uint256 => uint256))
        public userTokenUnlocksByEpoch;

    // Token Points on this chain
    uint256 public chainTokenPoints;

    // Epoch # => Token unlocks on this chain
    mapping(uint256 => uint256) public chainUnlocksByEpoch;

    /// EVENTS ///

    event Locked(address indexed user, uint256 amount);
    event Unlocked(address indexed user, uint256 amount);
    event UnlockedWithPenalty(
        address indexed user,
        uint256 amount,
        uint256 penaltyAmount
    );
    event TokenRecovered(address token, address to, uint256 amount);

    /// ERRORS ///

    error VeCVE_NonTransferrable();
    error VeCVE_ContinuousLock();
    error VeCVE_NotContinuousLock();
    error VeCVE_InvalidLock();
    error VeCVE_VeCVEShutdown();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "veCVE: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "veCVE: UNAUTHORIZED"
        );
        _;
    }

    constructor(
        ICentralRegistry centralRegistry_,
        uint256 continuousLockPointMultiplier_
    ) {
        _name = "Vote Escrowed CVE";
        _symbol = "veCVE";

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "veCVE: invalid central registry"
        );

        centralRegistry = centralRegistry_;
        genesisEpoch = centralRegistry.genesisEpoch();
        cve = centralRegistry.CVE();
        cveLocker = ICveLocker(centralRegistry.cveLocker());
        continuousLockPointMultiplier = continuousLockPointMultiplier_;
    }

    /// @dev Returns the name of the token
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the current epoch for the given time
    /// @param time The timestamp for which to calculate the epoch
    /// @return The current epoch
    function currentEpoch(uint256 time) public view returns (uint256) {
        if (time < genesisEpoch) {
            return 0;
        }

        return ((time - genesisEpoch) / EPOCH_DURATION);
    }

    /// @notice Returns the current epoch for the given time
    /// @return The current epoch
    function nextEpochStartTime() public view returns (uint256) {
        uint256 timestampOffset = (currentEpoch(block.timestamp) + 1) *
            EPOCH_DURATION;
        return (genesisEpoch + timestampOffset);
    }

    /// @notice Returns the epoch to lock until for a lock executed
    ///         at this moment
    /// @return The epoch
    function freshLockEpoch() public view returns (uint256) {
        return currentEpoch(block.timestamp) + LOCK_DURATION_EPOCHS;
    }

    /// @notice Returns the timestamp to lock until for a lock executed
    ///         at this moment
    /// @return The timestamp
    function freshLockTimestamp() public view returns (uint40) {
        return
            uint40(
                genesisEpoch +
                    (currentEpoch(block.timestamp) * EPOCH_DURATION) +
                    LOCK_DURATION
            );
    }

    /// @notice Locks a given amount of cve tokens and claims,
    ///         and processes any pending locker rewards
    /// @param amount The amount of tokens to lock
    /// @param continuousLock Indicator of whether the lock should be continuous
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function lock(
        uint256 amount,
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        if (isShutdown) {
            revert VeCVE_VeCVEShutdown();
        }
        if (amount == 0) {
            revert VeCVE_InvalidLock();
        }

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim pending locker rewards
        _claimRewards(msg.sender, rewardRecipient, rewardsData, params, aux);

        _lock(msg.sender, amount, continuousLock);

        emit Locked(msg.sender, amount);
    }

    /// @notice Locks a given amount of cve tokens on behalf of another user,
    ///         and processes any pending locker rewards
    /// @param recipient The address to lock tokens for
    /// @param amount The amount of tokens to lock
    /// @param continuousLock Indicator of whether the lock should be continuous
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function lockFor(
        address recipient,
        uint256 amount,
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        if (isShutdown) {
            revert VeCVE_VeCVEShutdown();
        }
        if (amount == 0) {
            revert VeCVE_InvalidLock();
        }
        if (!centralRegistry.approvedVeCVELocker(msg.sender)) {
            revert VeCVE_InvalidLock();
        }

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim pending locker rewards
        _claimRewards(recipient, rewardRecipient, rewardsData, params, aux);

        _lock(recipient, amount, continuousLock);

        emit Locked(recipient, amount);
    }

    /// @notice Extends a lock of cve tokens by a given index,
    ///         and processes any pending locker rewards
    /// @param lockIndex The index of the lock to extend
    /// @param continuousLock Indicator of whether the lock should be continuous
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function extendLock(
        uint256 lockIndex,
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        if (isShutdown) {
            revert VeCVE_VeCVEShutdown();
        }

        Lock[] storage locks = userLocks[msg.sender];
        uint40 unlockTimestamp = locks[lockIndex].unlockTime;

        // Length is index + 1 so has to be less than array length
        if (lockIndex >= locks.length) {
            revert VeCVE_InvalidLock();
        }
        if (unlockTimestamp < block.timestamp) {
            revert VeCVE_InvalidLock();
        }
        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) {
            revert VeCVE_ContinuousLock();
        }

        // Claim pending locker rewards
        _claimRewards(msg.sender, rewardRecipient, rewardsData, params, aux);

        uint216 tokenAmount = locks[lockIndex].amount;
        uint256 unlockEpoch = freshLockEpoch();
        uint256 priorUnlockEpoch = currentEpoch(locks[lockIndex].unlockTime);

        if (continuousLock) {
            locks[lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE;
            _updateTokenDataFromContinuousOn(
                msg.sender,
                priorUnlockEpoch,
                _getContinuousPointValue(tokenAmount),
                tokenAmount
            );
        } else {
            locks[lockIndex].unlockTime = freshLockTimestamp();
            // Updates unlock data for chain and user for new unlock time
            _updateTokenUnlockDataFromExtendedLock(
                msg.sender,
                priorUnlockEpoch,
                unlockEpoch,
                tokenAmount,
                tokenAmount
            );
        }
    }

    /// @notice Increases the locked amount and extends the lock
    ///         for the specified lock index, and processes any pending
    ///         locker rewards
    /// @param amount The amount to increase the lock by
    /// @param lockIndex The index of the lock to extend
    /// @param continuousLock Whether the lock should be continuous or not
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function increaseAmountAndExtendLock(
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        if (isShutdown) {
            revert VeCVE_VeCVEShutdown();
        }
        if (amount == 0) {
            revert VeCVE_InvalidLock();
        }

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim pending locker rewards
        _claimRewards(msg.sender, rewardRecipient, rewardsData, params, aux);

        _increaseAmountAndExtendLockFor(
            msg.sender,
            amount,
            lockIndex,
            continuousLock
        );
    }

    /// @notice Increases the locked amount and extends the lock
    ///         for the specified lock index, and processes any pending
    ///         locker rewards
    /// @param recipient The address to lock and extend tokens for
    /// @param amount The amount to increase the lock by
    /// @param lockIndex The index of the lock to extend
    /// @param continuousLock Whether the lock should be continuous or not
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function increaseAmountAndExtendLockFor(
        address recipient,
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        if (isShutdown) {
            revert VeCVE_VeCVEShutdown();
        }
        if (amount == 0) {
            revert VeCVE_InvalidLock();
        }
        if (!centralRegistry.approvedVeCVELocker(msg.sender)) {
            revert VeCVE_InvalidLock();
        }

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim pending locker rewards
        _claimRewards(recipient, rewardRecipient, rewardsData, params, aux);

        _increaseAmountAndExtendLockFor(
            recipient,
            amount,
            lockIndex,
            continuousLock
        );
    }

    /// @notice Disables a continuous lock for the user at the specified
    ///         lock index, and processes any pending locker rewards
    /// @param lockIndex The index of the lock to be disabled
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function disableContinuousLock(
        uint256 lockIndex,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length
        if (lockIndex >= locks.length) {
            revert VeCVE_InvalidLock();
        }
        if (locks[lockIndex].unlockTime != CONTINUOUS_LOCK_VALUE) {
            revert VeCVE_NotContinuousLock();
        }

        // Claim pending locker rewards
        _claimRewards(msg.sender, rewardRecipient, rewardsData, params, aux);

        uint216 tokenAmount = locks[lockIndex].amount;
        uint256 unlockEpoch = freshLockEpoch();
        locks[lockIndex].unlockTime = freshLockTimestamp();

        _reduceTokenData(
            msg.sender,
            unlockEpoch,
            _getContinuousPointValue(tokenAmount) - tokenAmount,
            tokenAmount
        );
    }

    /// @notice Combines all locks into a single lock,
    ///         and processes any pending locker rewards
    /// @param continuousLock Whether the combined lock should be continuous
    ///                       or not
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function combineLocks(
        uint256[] calldata lockIndexes,
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        // Claim pending locker rewards
        _claimRewards(msg.sender, rewardRecipient, rewardsData, params, aux);

        Lock[] storage locks = userLocks[msg.sender];
        uint256 lastLockIndex = locks.length - 1;
        uint256 locksToCombineIndex = lockIndexes.length - 1;

        // Check that theres are at least 2 locks to combine,
        // otherwise the inputs are misconfigured.
        // Check that the user has sufficient locks to combine,
        // then decrement 1 so we can use it to go through the lockIndexes
        // array backwards.
        if (locksToCombineIndex > 0 && locksToCombineIndex <= lastLockIndex) {
            revert VeCVE_InvalidLock();
        }

        uint256 lockAmount;
        Lock storage userLock;
        uint256 previousLockIndex;
        uint256 excessPoints;

        // Go backwards through the locks and validate that they are entered from smallest to largest index
        for (uint256 i = locksToCombineIndex; i > 0; ) {
            if (i != locksToCombineIndex) {
                // If this is the first iteration we do not need to check
                // for sorted lockIndexes
                require(
                    lockIndexes[i] < previousLockIndex,
                    "veCVE: lockIndexes misconfigured"
                );
            }

            previousLockIndex = lockIndexes[i];

            if (previousLockIndex != lastLockIndex) {
                Lock memory tempValue = locks[previousLockIndex];
                locks[previousLockIndex] = locks[lastLockIndex];
                locks[lastLockIndex] = tempValue;
            }

            userLock = locks[lastLockIndex];

            if (userLock.unlockTime != CONTINUOUS_LOCK_VALUE) {
                // Remove unlock data if there is any
                _reduceTokenUnlocks(
                    msg.sender,
                    currentEpoch(userLock.unlockTime),
                    userLock.amount
                );
            } else {
                unchecked {
                    excessPoints +=
                        _getContinuousPointValue(userLock.amount) -
                        userLock.amount;
                }
                // calculate and sum how many additional points they got
                // from their continuous lock
            }

            unchecked {
                // Should never overflow as the total amount of tokens a user
                // could ever lock is equal to the entire token supply
                // Decrement the array length since we need to pop the last entry
                lockAmount += locks[lastLockIndex--].amount;
                --i;
            }

            locks.pop();
        }

        if (excessPoints > 0) {
            _reduceTokenPoints(msg.sender, excessPoints);
        }

        userLock = locks[lockIndexes[0]]; // We will combine the deleted locks into the first lock in the array
        uint256 epoch;

        if (continuousLock) {
            if (userLock.unlockTime != CONTINUOUS_LOCK_VALUE) {
                // Finalize new combined lock amount
                lockAmount += userLock.amount;

                // Remove the previous unlock data
                epoch = currentEpoch(userLock.unlockTime);
                _reduceTokenUnlocks(msg.sender, epoch, userLock.amount);

                // Give the user extra token points from continuous lock
                // being enabled
                _incrementTokenPoints(
                    msg.sender,
                    _getContinuousPointValue(lockAmount) - lockAmount
                );

                // Assign new lock data
                userLock.amount = uint216(lockAmount);
                userLock.unlockTime = CONTINUOUS_LOCK_VALUE;
            } else {
                // Give the user extra token points from continuous lock
                // being enabled, but only from the other locks
                _incrementTokenPoints(
                    msg.sender,
                    _getContinuousPointValue(lockAmount) - lockAmount
                );

                // Finalize new combined lock amount
                lockAmount += userLock.amount;
                // Assign new lock data
                userLock.amount = uint216(lockAmount);
            }
        } else {
            require(
                userLock.unlockTime != CONTINUOUS_LOCK_VALUE,
                "veCVE: disable combined lock continuous mode first"
            );
            // Remove the previous unlock data
            _reduceTokenUnlocks(
                msg.sender,
                currentEpoch(userLock.unlockTime),
                userLock.amount
            );

            // Finalize new combined lock amount
            lockAmount += userLock.amount;
            // Assign new lock data
            userLock.amount = uint216(lockAmount);
            userLock.unlockTime = freshLockTimestamp();

            // Record the new unlock data
            _incrementTokenUnlocks(msg.sender, freshLockEpoch(), lockAmount);
        }
    }

    /// @notice Combines all locks into a single lock,
    ///         and processes any pending locker rewards
    /// @param continuousLock Whether the combined lock should be continuous
    ///                       or not
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function combineAllLocks(
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        // Claim pending locker rewards
        _claimRewards(msg.sender, rewardRecipient, rewardsData, params, aux);

        // Need to have this check after _claimRewards as the user could have
        // created a new lock with their pending rewards
        Lock[] storage locks = userLocks[msg.sender];
        uint256 numLocks = locks.length;

        if (numLocks < 2) {
            revert VeCVE_InvalidLock();
        }

        uint256 excessPoints;
        uint256 lockAmount;
        Lock storage userLock;

        for (uint256 i; i < numLocks; ) {
            userLock = locks[i];

            if (userLock.unlockTime != CONTINUOUS_LOCK_VALUE) {
                // Remove unlock data if there is any
                _reduceTokenUnlocks(
                    msg.sender,
                    currentEpoch(userLock.unlockTime),
                    userLock.amount
                );
            } else {
                unchecked {
                    excessPoints +=
                        _getContinuousPointValue(userLock.amount) -
                        userLock.amount;
                }
                // calculate and sum how many additional points they got
                // from their continuous lock
            }

            unchecked {
                // Should never overflow as the total amount of tokens a user
                // could ever lock is equal to the entire token supply
                lockAmount += locks[i++].amount;
            }
        }

        // Remove the users excess points from their continuous locks, if any
        if (excessPoints > 0) {
            _reduceTokenPoints(msg.sender, excessPoints);
        }
        // Remove the users locks
        delete userLocks[msg.sender];

        if (continuousLock) {
            userLocks[msg.sender].push(
                Lock({
                    amount: uint216(lockAmount),
                    unlockTime: CONTINUOUS_LOCK_VALUE
                })
            );
            // Give the user extra token points from continuous lock being enabled
            _incrementTokenPoints(
                msg.sender,
                _getContinuousPointValue(lockAmount) - lockAmount
            );
        } else {
            userLocks[msg.sender].push(
                Lock({
                    amount: uint216(lockAmount),
                    unlockTime: freshLockTimestamp()
                })
            );
            // Record the new unlock data
            _incrementTokenUnlocks(msg.sender, freshLockEpoch(), lockAmount);
        }
    }

    /// @notice Processes an expired lock for the specified lock index,
    ///         and processes any pending locker rewards
    /// @param recipient The address to send unlocked tokens to
    /// @param lockIndex The index of the lock to process
    /// @param relock Whether the expired lock should be relocked in a fresh lock
    /// @param continuousLock Whether the relocked fresh lock should be
    ///                       continuous or not
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function processExpiredLock(
        address recipient,
        uint256 lockIndex,
        bool relock,
        bool continuousLock,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length
        if (lockIndex >= locks.length) {
            revert VeCVE_InvalidLock();
        }

        require(
            block.timestamp >= locks[lockIndex].unlockTime || isShutdown,
            "veCVE: lock has not expired"
        );

        // Claim pending locker rewards
        _claimRewards(recipient, rewardRecipient, rewardsData, params, aux);

        uint256 lockAmount = locks[lockIndex].amount;

        if (relock) {
            // Token points will be caught up by _claimRewards call
            // so we can treat this as a fresh lock and increment rewards again
            _lock(recipient, lockAmount, continuousLock);
        } else {
            _burn(msg.sender, lockAmount);
            _removeLock(locks, lockIndex);

            // Transfer the recipient the unlocked CVE
            SafeTransferLib.safeTransferFrom(
                cve,
                address(this),
                recipient,
                lockAmount
            );

            emit Unlocked(msg.sender, lockAmount);

            /// Might be better gas to check if first user lock has amount == 0
            if (locks.length == 0) {
                cveLocker.resetUserClaimIndex(recipient);
            }
        }
    }

    /// @notice Processes an active lock as if its expired, for a penalty,
    ///         and processes any pending locker rewards
    /// @param recipient The address to receive the unlocked CVE
    /// @param lockIndex The index of the lock to process
    /// @param rewardRecipient Address to receive the reward tokens
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Parameters for rewards claim function
    /// @param aux Auxiliary data
    function earlyExpireLock(
        address recipient,
        uint256 lockIndex,
        address rewardRecipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) public {
        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length
        if (lockIndex >= locks.length) {
            revert VeCVE_InvalidLock();
        }

        uint256 penaltyValue = centralRegistry.earlyUnlockPenaltyValue();

        require(penaltyValue > 0, "veCVE: early unlocks disabled");

        // Claim pending locker rewards
        _claimRewards(recipient, rewardRecipient, rewardsData, params, aux);

        // Burn their veCVE and remove their lock
        uint256 lockAmount = locks[lockIndex].amount;
        _burn(msg.sender, lockAmount);
        _removeLock(locks, lockIndex);

        uint256 penaltyAmount = (lockAmount * penaltyValue) / DENOMINATOR;

        // Transfer the CVE penalty amount to Curvance DAO
        SafeTransferLib.safeTransferFrom(
            cve,
            address(this),
            centralRegistry.daoAddress(),
            penaltyAmount
        );

        // Transfer the remainder of the CVE to the recipient
        SafeTransferLib.safeTransferFrom(
            cve,
            address(this),
            recipient,
            lockAmount - penaltyAmount
        );

        emit UnlockedWithPenalty(msg.sender, lockAmount, penaltyAmount);

        /// Might be better gas to check if first user lock has amount == 0
        if (locks.length == 0) {
            cveLocker.resetUserClaimIndex(recipient);
        }
    }

    /// @notice Updates user points by reducing the amount that gets unlocked
    ///         in a specific epoch
    /// @param user The address of the user whose points are to be updated
    /// @param epoch The epoch from which the unlock amount will be reduced
    /// @dev This function is only called when
    ///      userTokenUnlocksByEpoch[user][epoch] > 0
    ///      so do not need to check here
    function updateUserPoints(address user, uint256 epoch) public {
        require(
            address(cveLocker) == msg.sender,
            "veCVE: only CVE Locker can update user points"
        );

        unchecked {
            userTokenPoints[user] -= userTokenUnlocksByEpoch[user][epoch];
        }
    }

    /// @notice Recover tokens sent accidentally to the contract
    ///         or leftover rewards (excluding veCVE tokens)
    /// @param token The address of the token to recover
    /// @param to The address to receive the recovered tokens
    /// @param amount The amount of tokens to recover
    function recoverToken(
        address token,
        address to,
        uint256 amount
    ) external onlyDaoPermissions {
        require(token != address(cve), "cannot withdraw cve token");

        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }

        SafeTransferLib.safeTransfer(token, to, amount);

        emit TokenRecovered(token, to, amount);
    }

    /// @notice Shuts down the contract, unstakes all tokens,
    ///         and releases all locks
    function shutdown() external onlyElevatedPermissions {
        isShutdown = true;
        cveLocker.notifyLockerShutdown();
    }

    /// View Functions ///

    /// @notice Calculates the total votes for a user based on their current locks
    /// @param user The address of the user to calculate votes for
    /// @return The total number of votes for the user
    function getVotes(address user) public view returns (uint256) {
        uint256 numLocks = userLocks[user].length;

        if (numLocks == 0) {
            return 0;
        }

        uint256 votes;

        for (uint256 i; i < numLocks; ) {
            // Based on CVE maximum supply this cannot overflow
            unchecked {
                votes += getVotesForSingleLockForTime(
                    user,
                    i++,
                    block.timestamp
                );
            }
        }

        return votes;
    }

    /// @notice Calculates the total votes for a user based
    ///         on their locks at a specific epoch
    /// @param user The address of the user to calculate votes for
    /// @param epoch The epoch for which the votes are calculated
    /// @return The total number of votes for the user at the specified epoch
    function getVotesForEpoch(
        address user,
        uint256 epoch
    ) public view returns (uint256) {
        uint256 numLocks = userLocks[user].length;

        if (numLocks == 0) {
            return 0;
        }

        uint256 timestamp = genesisEpoch + (EPOCH_DURATION * epoch);
        uint256 votes;

        for (uint256 i; i < numLocks; ) {
            // Based on CVE maximum supply this cannot overflow
            unchecked {
                votes += getVotesForSingleLockForTime(user, i++, timestamp);
            }
        }

        return votes;
    }

    /// @notice Calculates the votes for a single lock of a user based
    ///         on a specific timestamp
    /// @param user The address of the user whose lock is being used
    ///              for the calculation
    /// @param lockIndex The index of the lock to calculate votes for
    /// @param time The timestamp to use for the calculation
    /// @return The number of votes for the specified lock at the given timestamp
    function getVotesForSingleLockForTime(
        address user,
        uint256 lockIndex,
        uint256 time
    ) public view returns (uint256) {
        Lock storage userLock = userLocks[user][lockIndex];

        if (userLock.unlockTime == CONTINUOUS_LOCK_VALUE) {
            return _getContinuousVoteValue(userLock.amount);
        }
        if (userLock.unlockTime < time) {
            return 0;
        }

        // Equal to epochsLeft = (userLock.unlockTime - time) / EPOCH_DURATION
        // (userLock.amount * epochsLeft) / LOCK_DURATION_EPOCHS
        return
            (userLock.amount *
                ((userLock.unlockTime - time) / EPOCH_DURATION)) /
            LOCK_DURATION_EPOCHS;
    }

    /// Transfer Locked Functions ///

    /// @notice Overridden transfer function to prevent token transfers
    /// @dev This function always reverts, as the token is non-transferrable
    /// @return This function always reverts and does not return a value
    function transfer(address, uint256) public pure override returns (bool) {
        revert VeCVE_NonTransferrable();
    }

    /// @notice Overridden transferFrom function to prevent token transfers
    /// @dev This function always reverts, as the token is non-transferrable
    /// @return This function always reverts and does not return a value
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert VeCVE_NonTransferrable();
    }

    /// INTERNAL FUNCTIONS ///

    /// See claimRewardsFor in CVE Locker
    function _claimRewards(
        address user,
        address recipient,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) internal {
        uint256 epoches = cveLocker.epochsToClaim(user);
        if (epoches > 0) {
            cveLocker.claimRewardsFor(
                user,
                recipient,
                epoches,
                rewardsData,
                params,
                aux
            );
        }
    }

    /// @notice Internal function to lock tokens for a user
    /// @param recipient The address of the user receiving the lock
    /// @param amount The amount of tokens to lock
    /// @param continuousLock Whether the lock is continuous or not
    function _lock(
        address recipient,
        uint256 amount,
        bool continuousLock
    ) internal {
        /// Might be better gas to check if first user locker .amount == 0
        if (userLocks[recipient].length == 0) {
            cveLocker.updateUserClaimIndex(
                recipient,
                currentEpoch(block.timestamp)
            );
        }

        if (continuousLock) {
            userLocks[recipient].push(
                Lock({
                    amount: uint216(amount),
                    unlockTime: CONTINUOUS_LOCK_VALUE
                })
            );
            _incrementTokenPoints(recipient, _getContinuousPointValue(amount));
        } else {
            uint256 unlockEpoch = freshLockEpoch();
            userLocks[recipient].push(
                Lock({
                    amount: uint216(amount),
                    unlockTime: freshLockTimestamp()
                })
            );
            _incrementTokenData(recipient, unlockEpoch, amount);
        }

        _mint(recipient, amount);
    }

    /// @notice Internal function to handle whenever a user needs an increase
    ///         to a locked amount and extended lock
    /// @param recipient The address to lock and extend tokens for
    /// @param amount The amount to increase the lock by
    /// @param lockIndex The index of the lock to extend
    /// @param continuousLock Whether the lock should be continuous or not
    function _increaseAmountAndExtendLockFor(
        address recipient,
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock
    ) internal {
        Lock[] storage user = userLocks[recipient];

        // Length is index + 1 so has to be less than array length
        if (lockIndex >= user.length) {
            revert VeCVE_InvalidLock();
        }

        uint40 unlockTimestamp = user[lockIndex].unlockTime;

        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) {
            // Increment the chain and user token point balance
            _incrementTokenPoints(recipient, _getContinuousPointValue(amount));
            // Update the lock value to include the new locked tokens
            user[lockIndex].amount = uint216(user[lockIndex].amount + amount);
        } else {
            // User was not continuous locked prior so we will need
            // to clean up their unlock data
            if (unlockTimestamp < block.timestamp) {
                revert VeCVE_InvalidLock();
            }

            uint256 previousTokenAmount = user[lockIndex].amount;
            uint256 newTokenAmount = previousTokenAmount + amount;
            uint256 priorUnlockEpoch = currentEpoch(
                user[lockIndex].unlockTime
            );

            if (continuousLock) {
                user[lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE;
                // Decrement their previous non-continuous lock value
                // and increase points by the continuous lock value
                _updateTokenDataFromContinuousOn(
                    recipient,
                    priorUnlockEpoch,
                    _getContinuousPointValue(newTokenAmount) -
                        previousTokenAmount,
                    previousTokenAmount
                );
            } else {
                user[lockIndex].unlockTime = freshLockTimestamp();
                uint256 unlockEpoch = freshLockEpoch();
                // Update unlock data removing the old lock amount
                // from old epoch and add the new lock amount to the new epoch
                _updateTokenUnlockDataFromExtendedLock(
                    recipient,
                    priorUnlockEpoch,
                    unlockEpoch,
                    previousTokenAmount,
                    newTokenAmount
                );

                // Increment the chain and user token point balance
                _incrementTokenPoints(recipient, amount);
            }

            user[lockIndex].amount = uint216(newTokenAmount);
        }

        _mint(msg.sender, amount);

        emit Locked(recipient, amount);
    }

    /// @notice Removes a lock from `user`
    /// @param user An array of locks for `user`
    /// @param lockIndex The index of the lock to be removed
    function _removeLock(Lock[] storage user, uint256 lockIndex) internal {
        uint256 lastLockIndex = user.length - 1;

        if (lockIndex != lastLockIndex) {
            Lock memory tempValue = user[lockIndex];
            user[lockIndex] = user[lastLockIndex];
            user[lastLockIndex] = tempValue;
        }

        user.pop();
    }

    /// @notice Increment token data
    /// @dev Increments both the token points and token unlocks for the chain
    ///      and user. Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param points The number of points to add
    function _incrementTokenData(
        address user,
        uint256 epoch,
        uint256 points
    ) internal {
        // only modified on locking/unlocking veCVE and we know theres never
        // more than 420m so this should never over/underflow
        unchecked {
            chainTokenPoints += points;
            chainUnlocksByEpoch[epoch] += points;
            userTokenPoints[user] += points;
            userTokenUnlocksByEpoch[user][epoch] += points;
        }
    }

    /// @notice Reduce token data
    /// @dev Reduces both the token points and token unlocks for the chain and
    ///      user for a given epoch. Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param epoch The epoch to reduce the data
    /// @param tokenPoints The token points to reduce
    /// @param tokenUnlocks The token unlocks to reduce
    function _reduceTokenData(
        address user,
        uint256 epoch,
        uint256 tokenPoints,
        uint256 tokenUnlocks
    ) internal {
        // only modified on locking/unlocking veCVE and we know theres never
        // more than 420m so this should never over/underflow
        unchecked {
            chainTokenPoints -= tokenPoints;
            chainUnlocksByEpoch[epoch] -= tokenUnlocks;
            userTokenPoints[user] -= tokenPoints;
            userTokenUnlocksByEpoch[user][epoch] -= tokenUnlocks;
        }
    }

    /// @notice Increment token points
    /// @dev Increments the token points of the chain and user.
    ///      Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param points The number of points to add
    function _incrementTokenPoints(address user, uint256 points) internal {
        // We know theres never more than 420m
        // so this should never over/underflow
        unchecked {
            chainTokenPoints += points;
            userTokenPoints[user] += points;
        }
    }

    /// @notice Reduce token points
    /// @dev Reduces the token points of the chain and user.
    ///      Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param points The number of points to reduce
    function _reduceTokenPoints(address user, uint256 points) internal {
        // We know theres never more than 420m
        // so this should never over/underflow
        unchecked {
            chainTokenPoints -= points;
            userTokenPoints[user] -= points;
        }
    }

    /// @notice Increment token unlocks
    /// @dev Increments the token unlocks of the chain and user
    ///      for a given epoch. Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param epoch The epoch to add the unlocks
    /// @param points The number of points to add
    function _incrementTokenUnlocks(
        address user,
        uint256 epoch,
        uint256 points
    ) internal {
        // might not need token unlock functions
        // We know theres never more than 420m
        // so this should never over/underflow
        unchecked {
            chainUnlocksByEpoch[epoch] += points;
            userTokenUnlocksByEpoch[user][epoch] += points;
        }
    }

    /// @notice Reduce token unlocks
    /// @dev Reduces the token unlocks of the chain and user
    ///      for a given epoch. Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param epoch The epoch to reduce the unlocks
    /// @param points The number of points to reduce
    function _reduceTokenUnlocks(
        address user,
        uint256 epoch,
        uint256 points
    ) internal {
        // We know theres never more than 420m
        // so this should never over/underflow
        unchecked {
            chainUnlocksByEpoch[epoch] -= points;
            userTokenUnlocksByEpoch[user][epoch] -= points;
        }
    }

    /// @notice Update token unlock data from an extended lock that
    ///         is not continuous
    /// @dev Updates the token points and token unlocks for the chain
    ///      and user from a continuous lock for a given epoch.
    ///      Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param previousEpoch The previous unlock epoch
    /// @param epoch The new unlock epoch
    /// @param previousPoints The previous points to remove
    ///                        from the old unlock time
    /// @param points The new token points to add for the new unlock time
    function _updateTokenUnlockDataFromExtendedLock(
        address user,
        uint256 previousEpoch,
        uint256 epoch,
        uint256 previousPoints,
        uint256 points
    ) internal {
        // We know theres never more than 420m
        // so this should never over/underflow
        unchecked {
            chainUnlocksByEpoch[previousEpoch] -= previousPoints;
            userTokenUnlocksByEpoch[user][previousEpoch] -= previousPoints;
            chainUnlocksByEpoch[epoch] += points;
            userTokenUnlocksByEpoch[user][epoch] += points;
        }
    }

    /// @notice Update token data from continuous lock on
    /// @dev Updates the token points and token unlocks for the chain
    ///      and user from a continuous lock for a given epoch.
    ///      Can only be called by the VeCVE contract
    /// @param user The address of the user
    /// @param epoch The epoch to update the data
    /// @param tokenPoints The token points to add
    /// @param tokenUnlocks The token unlocks to reduce
    function _updateTokenDataFromContinuousOn(
        address user,
        uint256 epoch,
        uint256 tokenPoints,
        uint256 tokenUnlocks
    ) internal {
        // We know theres never more than 420m
        // so this should never over/underflow
        unchecked {
            chainTokenPoints += tokenPoints;
            chainUnlocksByEpoch[epoch] -= tokenUnlocks;
            userTokenPoints[user] += tokenPoints;
            userTokenUnlocksByEpoch[user][epoch] -= tokenUnlocks;
        }
    }

    /// @notice Calculates the continuous lock token point value for basePoints
    /// @param basePoints The token points to be used in the calculation
    /// @return The calculated continuous lock token point value
    function _getContinuousPointValue(
        uint256 basePoints
    ) internal view returns (uint256) {
        unchecked {
            return ((basePoints * continuousLockPointMultiplier) /
                DENOMINATOR);
        }
    }

    /// @notice Calculates the continuous lock gauge voting power value
    ///         for basePoints
    /// @param basePoints The token points to be used in the calculation
    /// @return The calculated continuous lock gauge voting power value
    function _getContinuousVoteValue(
        uint256 basePoints
    ) internal view returns (uint256) {
        unchecked {
            return ((basePoints * centralRegistry.voteBoostValue()) /
                DENOMINATOR);
        }
    }
}
