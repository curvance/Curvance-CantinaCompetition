// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICVELocker, RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { IProtocolMessagingHub } from "contracts/interfaces/IProtocolMessagingHub.sol";

contract VeCVE is ERC20, ERC165, ReentrancyGuard {
    /// TYPES ///

    struct Lock {
        /// @notice The amount of underlying CVE associated with the lock.
        uint216 amount;
        /// @notice The unix timestamp when the associated lock will unlock.
        uint40 unlockTime;
    }

    /// CONSTANTS ///

    /// @notice Timestamp `unlockTime` will be set to when a lock
    //          is on continuous lock (CL) mode.
    uint40 public constant CONTINUOUS_LOCK_VALUE = type(uint40).max;
    /// @notice Protocol epoch length.
    uint256 public constant EPOCH_DURATION = 2 weeks;
    /// @notice in # of epochs.
    uint256 public constant LOCK_DURATION_EPOCHS = 26;
    /// @notice in # of seconds.
    uint256 public constant LOCK_DURATION = 52 weeks;
    /// @notice Point multiplier for a continuous lock. 2 = 200%.
    uint256 public constant CL_POINT_MULTIPLIER = 2;

    /// @dev `bytes4(keccak256(bytes("VeCVE__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x32c4d25d;
    /// @dev `bytes4(keccak256(bytes("VeCVE__InvalidLock()")))`
    uint256 internal constant _INVALID_LOCK_SELECTOR = 0x21d223d9;
    /// @dev `bytes4(keccak256(bytes("VeCVE__VeCVEShutdown()")))`
    uint256 internal constant _VECVE_SHUTDOWN_SELECTOR = 0x3ad2450b;

    /// @notice CVE contract address.
    address public immutable cve;
    /// @notice CVE Locker contract address.
    ICVELocker public immutable cveLocker;
    /// @notice Genesis Epoch timestamp.
    uint256 public immutable genesisEpoch;
    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice token name metadata.
    bytes32 private immutable _name;
    /// @notice token symbol metadata.
    bytes32 private immutable _symbol;

    /// STORAGE ///

    /// @notice Token Points on this chain.
    uint256 public chainPoints;
    ///  @notice 1 = active; 2 = shutdown.
    uint256 public isShutdown = 1;

    /// @notice User => Array of VeCVE locks.
    mapping(address => Lock[]) public userLocks;
    /// @notice User => Token Points.
    mapping(address => uint256) public userPoints;
    /// @notice User => Epoch # => Tokens unlocked.
    mapping(address => mapping(uint256 => uint256)) public userUnlocksByEpoch;
    /// @notice Epoch # => Token unlocks on this chain.
    mapping(uint256 => uint256) public chainUnlocksByEpoch;

    /// EVENTS ///

    event Locked(address indexed user, uint256 amount);
    event Unlocked(address indexed user, uint256 amount);
    event UnlockedWithPenalty(
        address indexed user,
        uint256 amount,
        uint256 penaltyAmount
    );

    /// ERRORS ///

    error VeCVE__Unauthorized();
    error VeCVE__NonTransferrable();
    error VeCVE__LockTypeMismatch();
    error VeCVE__InvalidLock();
    error VeCVE__VeCVEShutdown();
    error VeCVE__ParametersAreInvalid();

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        _name = "Vote Escrowed CVE";
        _symbol = "veCVE";

        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert VeCVE__ParametersAreInvalid();
        }

        centralRegistry = centralRegistry_;
        genesisEpoch = centralRegistry.genesisEpoch();
        cve = centralRegistry.cve();
        cveLocker = ICVELocker(centralRegistry.cveLocker());
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Used for frontend, needed due to array of structs.
    /// @param user The user to query veCVE locks for.
    /// @return Unwrapped user lock information.
    function queryUserLocks(
        address user
    ) external view returns (uint256[] memory, uint256[] memory) {
        uint256 numLocks = userLocks[user].length;
        Lock[] memory locks = userLocks[user];
        Lock memory lock;
        uint256[] memory lockAmounts = new uint256[](numLocks);
        uint256[] memory lockTimestamps = new uint256[](numLocks);

        for (uint256 i; i < numLocks; ++i) {
            lock = locks[i];
            lockAmounts[i] = lock.amount;
            lockTimestamps[i] = lock.unlockTime;
        }

        return (lockAmounts, lockTimestamps);
    }

    /// @notice Used for fuzzing.
    function getUnlockTime(
        address user,
        uint256 lockIndex
    ) public view returns (uint40) {
        return userLocks[user][lockIndex].unlockTime;
    }

    /// @notice Used for frontend, needed due to array of structs.
    function queryUserLocksLength(address user) external view returns (uint) {
        return userLocks[user].length;
    }

    /// @notice Rescue any token sent by mistake.
    /// @param token token to rescue.
    /// @param amount amount of `token` to rescue, 0 indicates to rescue all.
    function rescueToken(address token, uint256 amount) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (amount == 0) {
                amount = address(this).balance;
            }

            SafeTransferLib.forceSafeTransferETH(daoOperator, amount);
        } else {
            if (token == address(cve)) {
                revert VeCVE__NonTransferrable();
            }

            if (amount == 0) {
                amount = IERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// @notice Shuts down the contract, unstakes all tokens,
    ///         and releases all locks.
    function shutdown() external {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        isShutdown = 2;
        cveLocker.notifyLockerShutdown();
    }

    /// @notice Locks a given amount of cve tokens and claims,
    ///         and processes any pending locker rewards.
    /// @param amount The amount of tokens to lock.
    /// @param continuousLock Indicator of whether the lock should be continuous.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function createLock(
        uint256 amount,
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        _canLock(amount);

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        _lock(msg.sender, amount, continuousLock);

        emit Locked(msg.sender, amount);
    }

    /// @notice Locks a given amount of cve tokens on behalf of another user,
    ///         and processes any pending locker rewards.
    /// @param recipient The address to lock tokens for.
    /// @param amount The amount of tokens to lock.
    /// @param continuousLock Indicator of whether the lock should be continuous.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function createLockFor(
        address recipient,
        uint256 amount,
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        _canLock(amount);

        if (
            !centralRegistry.isVeCVELocker(msg.sender) &&
            !centralRegistry.isGaugeController(msg.sender)
        ) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim any pending locker rewards.
        _claimRewards(recipient, rewardsData, params, aux);

        _lock(recipient, amount, continuousLock);

        emit Locked(recipient, amount);
    }

    /// @notice Extends a lock of cve tokens by a given index,
    ///         and processes any pending locker rewards.
    /// @param lockIndex The index of the lock to extend.
    /// @param continuousLock Indicator of whether the lock should be continuous.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function extendLock(
        uint256 lockIndex,
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        if (isShutdown == 2) {
            _revert(_VECVE_SHUTDOWN_SELECTOR);
        }

        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length.
        if (lockIndex >= locks.length) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        uint40 unlockTimestamp = locks[lockIndex].unlockTime;

        if (unlockTimestamp < block.timestamp) {
            _revert(_INVALID_LOCK_SELECTOR);
        }
        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) {
            revert VeCVE__LockTypeMismatch();
        }

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        uint216 amount = locks[lockIndex].amount;
        uint256 epoch = freshLockEpoch();
        uint256 priorEpoch = currentEpoch(locks[lockIndex].unlockTime);

        if (continuousLock) {
            locks[lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE;
            _updateDataToContinuousOn(
                msg.sender,
                priorEpoch,
                _getCLPoints(amount) - amount,
                amount
            );
        } else {
            locks[lockIndex].unlockTime = freshLockTimestamp();
            // Updates unlock data for chain and user for new unlock time.
            _updateUnlockDataToExtendedLock(
                msg.sender,
                priorEpoch,
                epoch,
                amount,
                amount
            );
        }
    }

    /// @notice Increases the locked amount and extends the lock
    ///         for the specified lock index, and processes any pending
    ///         locker rewards.
    /// @param amount The amount to increase the lock by.
    /// @param lockIndex The index of the lock to extend.
    /// @param continuousLock Whether the lock should be continuous or not.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function increaseAmountAndExtendLock(
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        _canLock(amount);

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        _increaseAmountAndExtendLockFor(
            msg.sender,
            amount,
            lockIndex,
            continuousLock
        );
    }

    /// @notice Increases the locked amount and extends the lock
    ///         for the specified lock index, and processes any pending
    ///         locker rewards.
    /// @param recipient The address to lock and extend tokens for.
    /// @param amount The amount to increase the lock by.
    /// @param lockIndex The index of the lock to extend.
    /// @param continuousLock Whether the lock should be continuous or not.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function increaseAmountAndExtendLockFor(
        address recipient,
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        _canLock(amount);

        if (
            !centralRegistry.isVeCVELocker(msg.sender) &&
            !centralRegistry.isGaugeController(msg.sender)
        ) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        SafeTransferLib.safeTransferFrom(
            cve,
            msg.sender,
            address(this),
            amount
        );

        // Claim any pending locker rewards.
        _claimRewards(recipient, rewardsData, params, aux);

        _increaseAmountAndExtendLockFor(
            recipient,
            amount,
            lockIndex,
            continuousLock
        );
    }

    /// @notice Disables a continuous lock for the user at the specified
    ///         lock index, and processes any pending locker rewards.
    /// @param lockIndex The index of the lock to be disabled.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function disableContinuousLock(
        uint256 lockIndex,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length.
        if (lockIndex >= locks.length) {
            _revert(_INVALID_LOCK_SELECTOR);
        }
        if (locks[lockIndex].unlockTime != CONTINUOUS_LOCK_VALUE) {
            revert VeCVE__LockTypeMismatch();
        }

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        uint216 amount = locks[lockIndex].amount;
        uint256 epoch = freshLockEpoch();
        locks[lockIndex].unlockTime = freshLockTimestamp();

        // Remove their continuous lock bonus and
        // document that they have tokens unlocking in a year.
        _reducePoints(msg.sender, _getCLPoints(amount) - amount);
        _incrementTokenUnlocks(msg.sender, epoch, amount);
    }

    /// @notice Combines all locks into a single lock,
    ///         and processes any pending locker rewards.
    /// @param continuousLock Whether the combined lock should be continuous
    ///                       or not.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function combineAllLocks(
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        if (isShutdown == 2) {
            _revert(_VECVE_SHUTDOWN_SELECTOR);
        }

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        // Need to have this check after _claimRewards as the user could have
        // created a new lock with their pending rewards.
        Lock[] storage locks = userLocks[msg.sender];
        uint256 numLocks = locks.length;

        if (numLocks < 2) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        uint256 priorCLPoints;
        uint256 amount;
        Lock storage lock;

        for (uint256 i; i < numLocks; ) {
            lock = locks[i];

            if (lock.unlockTime != CONTINUOUS_LOCK_VALUE) {
                // Remove unlock data if there is any.
                _reduceTokenUnlocks(
                    msg.sender,
                    currentEpoch(lock.unlockTime),
                    lock.amount
                );
            } else {
                // Sums how much veCVE is continuous locked.
                unchecked {
                    priorCLPoints += lock.amount;
                }
            }
            unchecked {
                // Should never overflow as the total amount of tokens a user
                // could ever lock is equal to the entire token supply.
                amount += locks[i++].amount;
            }
        }

        // Remove the users locks.
        delete userLocks[msg.sender];

        if (continuousLock) {
            userLocks[msg.sender].push(
                Lock({
                    amount: uint216(amount),
                    unlockTime: CONTINUOUS_LOCK_VALUE
                })
            );

            // If not all locks combined were continuous, we will need to
            // increment points by the difference between the terminal boosted
            // points minus current `priorCLPoints`, because continuous lock
            // bonus is 100%, we can use amount as the excess points to be
            // received from continuous lock.
            uint256 netIncrease = amount - priorCLPoints;
            if (netIncrease > 0) {
                _incrementPoints(msg.sender, netIncrease);
            }
        } else {
            userLocks[msg.sender].push(
                Lock({
                    amount: uint216(amount),
                    unlockTime: freshLockTimestamp()
                })
            );

            // Remove caller `priorCLPoints` from their continuous locks,
            // if any.
            if (priorCLPoints > 0) {
                _reducePoints(msg.sender, priorCLPoints);
            }
            // Record the new unlock data.
            _incrementTokenUnlocks(msg.sender, freshLockEpoch(), amount);
        }
    }

    /// @notice Processes an expired lock for the specified lock index,
    ///         and processes any pending locker rewards.
    /// @param lockIndex The index of the lock to process.
    /// @param relock Whether the expired lock should be relocked in a fresh lock.
    /// @param continuousLock Whether the relocked fresh lock should be
    ///                       continuous or not.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function processExpiredLock(
        uint256 lockIndex,
        bool relock,
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length.
        if (lockIndex >= locks.length) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        if (block.timestamp < locks[lockIndex].unlockTime && isShutdown != 2) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        Lock memory lock = locks[lockIndex];
        uint256 amount = lock.amount;

        // If the locker is shutdown, do not allow them to relock,
        // we'd want them to exit locked positions.
        if (isShutdown == 2) {
            relock = false;
            // Update their points to reflect the removed lock
            _updateDataFromEarlyUnlock(msg.sender, amount, lock.unlockTime);
        }

        if (relock) {
            // Token points will be caught up by _claimRewards call so we can
            // treat this as a fresh lock and increment points.
            if (continuousLock) {
                // If the relocked lock is continuous update `unlockTime`
                // to continuous lock value and increase points.
                locks[lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE;
                _incrementPoints(msg.sender, _getCLPoints(amount));
            } else {
                // If the relocked lock is a standard lock `unlockTime`
                // to a fresh lock timestamp and increase points
                // and set unlock schedule.
                locks[lockIndex].unlockTime = freshLockTimestamp();
                _incrementPoints(msg.sender, amount);
                _incrementTokenUnlocks(msg.sender, freshLockEpoch(), amount);
            }
        } else {
            _burn(msg.sender, amount);
            _removeLock(locks, lockIndex);

            // Transfer the user the unlocked CVE
            SafeTransferLib.safeTransfer(cve, msg.sender, amount);

            emit Unlocked(msg.sender, amount);

            // Check whether the user has no remaining locks and reset their
            // index, that way if in the future they create a new lock,
            // they do not need to claim epochs they have no rewards for.
            if (locks.length == 0 && isShutdown != 2) {
                cveLocker.resetUserClaimIndex(msg.sender);
            }
        }
    }

    /// @notice Moves a lock from this chain to `dstChainId`,
    ///         and processes any pending locker rewards.
    /// @param lockIndex The index of the lock to bridge.
    /// @param dstChainId The Chain ID of the desired destination chain.
    /// @param continuousLock Whether the bridged lock should be continuous
    ///                       or not.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function bridgeVeCVELock(
        uint256 lockIndex,
        uint256 dstChainId,
        bool continuousLock,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external payable nonReentrant returns (uint64 sequence) {
        if (isShutdown == 2) {
            _revert(_VECVE_SHUTDOWN_SELECTOR);
        }

        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length.
        if (lockIndex >= locks.length) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        // Check if the user is trying to early expire an expired lock.
        if (block.timestamp >= locks[lockIndex].unlockTime) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        Lock memory lock = locks[lockIndex];
        uint256 amount = lock.amount;

        // Update their points to reflect the removed lock.
        _updateDataFromEarlyUnlock(msg.sender, amount, lock.unlockTime);

        // Burn their VeCVE.
        _burn(msg.sender, amount);
        // Remove their lock entry.
        _removeLock(locks, lockIndex);
        // Burn the CVE for bridged lock.
        ICVE(cve).burnVeCVELock(amount);

        address messagingHub = centralRegistry.protocolMessagingHub();

        sequence = IProtocolMessagingHub(messagingHub).bridgeVeCVELock{
            value: msg.value
        }(dstChainId, msg.sender, amount, continuousLock);

        // Check whether the user has no remaining locks and reset their
        // index, that way if in the future they create a new lock,
        // they do not need to claim epochs they have no rewards for.
        if (locks.length == 0 && isShutdown != 2) {
            cveLocker.resetUserClaimIndex(msg.sender);
        }
    }

    /// @notice Processes an active lock as if its expired, for a penalty,
    ///         and processes any pending locker rewards.
    /// @param lockIndex The index of the lock to process.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function earlyExpireLock(
        uint256 lockIndex,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        Lock[] storage locks = userLocks[msg.sender];

        // Length is index + 1 so has to be less than array length.
        if (lockIndex >= locks.length) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        // Check if the user is trying to early expire an expired lock.
        if (block.timestamp >= locks[lockIndex].unlockTime) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        uint256 penalty = centralRegistry.earlyUnlockPenaltyMultiplier();

        // If penalty == 0, then the early expiry feature is inactive.
        if (penalty == 0) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        // Claim any pending locker rewards.
        _claimRewards(msg.sender, rewardsData, params, aux);

        Lock memory lock = locks[lockIndex];
        uint256 amount = lock.amount;

        // Update their points to reflect the removed lock.
        _updateDataFromEarlyUnlock(msg.sender, amount, lock.unlockTime);

        // Burn their VeCVE and remove their lock.
        _burn(msg.sender, amount);
        _removeLock(locks, lockIndex);

        // Penalty value = lock amount * penalty multiplier, in `WAD`,
        // linearly scaled down as `unlockTime` scales from `LOCK_DURATION`
        // down to 0.
        uint256 penaltyAmount = _getUnlockPenalty(
            amount,
            penalty,
            lock.unlockTime
        );

        // Transfer the CVE penalty amount to Curvance DAO.
        SafeTransferLib.safeTransfer(
            cve,
            centralRegistry.daoAddress(),
            penaltyAmount
        );

        // Transfer the remainder of the CVE.
        SafeTransferLib.safeTransfer(cve, msg.sender, amount - penaltyAmount);

        emit UnlockedWithPenalty(msg.sender, amount, penaltyAmount);

        // Check whether the user has no remaining locks and reset their index,
        // that way if in the future they create a new lock, they do not need
        // to claim a bunch of epochs they have no rewards for.
        if (locks.length == 0 && isShutdown != 2) {
            cveLocker.resetUserClaimIndex(msg.sender);
        }
    }

    /// @notice Updates user points by reducing the amount that gets unlocked
    ///         in a specific epoch.
    /// @param user The address of the user whose points are to be updated.
    /// @param epoch The epoch from which the unlock amount will be reduced.
    /// @dev This function is only called when
    ///      userUnlocksByEpoch[user][epoch] > 0
    ///      so we do not need to check here.
    function updateUserPoints(address user, uint256 epoch) external {
        address _cveLocker = address(cveLocker);
        assembly {
            if iszero(eq(caller(), _cveLocker)) {
                mstore(0x00, _UNAUTHORIZED_SELECTOR)
                revert(0x1c, 0x04)
            }
        }

        unchecked {
            userPoints[user] =
                userPoints[user] -
                userUnlocksByEpoch[user][epoch];
        }
    }

    /// @notice Calculates the total votes for a user based on their current locks.
    /// @param user The address of the user to calculate votes for.
    /// @return The total number of votes for the user.
    function getVotes(address user) external view returns (uint256) {
        uint256 numLocks = userLocks[user].length;

        if (numLocks == 0) {
            return 0;
        }

        uint256 currentLockBoost = centralRegistry.voteBoostMultiplier();
        uint256 votes;

        for (uint256 i; i < numLocks; ) {
            // Based on CVE maximum supply this cannot overflow.
            unchecked {
                votes += getVotesForSingleLockForTime(
                    user,
                    i++,
                    block.timestamp,
                    currentLockBoost
                );
            }
        }

        return votes;
    }

    /// @notice Calculates the total votes for a user based
    ///         on their locks at a specific epoch.
    /// @param user The address of the user to calculate votes for.
    /// @param epoch The epoch for which the votes are calculated.
    /// @return The total number of votes for the user at the specified epoch.
    function getVotesForEpoch(
        address user,
        uint256 epoch
    ) external view returns (uint256) {
        uint256 numLocks = userLocks[user].length;

        if (numLocks == 0) {
            return 0;
        }

        uint256 timestamp = genesisEpoch + (EPOCH_DURATION * epoch);
        uint256 currentLockBoost = centralRegistry.voteBoostMultiplier();
        uint256 votes;

        for (uint256 i; i < numLocks; ) {
            // Based on CVE maximum supply this cannot overflow.
            unchecked {
                votes += getVotesForSingleLockForTime(
                    user,
                    i++,
                    timestamp,
                    currentLockBoost
                );
            }
        }

        return votes;
    }

    /// PUBLIC FUNCTIONS ///

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return string(abi.encodePacked(_name));
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return string(abi.encodePacked(_symbol));
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IVeCVE).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Returns the current epoch for the given time.
    /// @param time The timestamp for which to calculate the epoch.
    /// @return The current epoch.
    function currentEpoch(uint256 time) public view returns (uint256) {
        if (time < genesisEpoch) {
            return 0;
        }

        // Rounds down intentionally.
        return ((time - genesisEpoch) / EPOCH_DURATION);
    }

    /// @notice Returns the timestamp of when the next epoch begins.
    /// @return The calculated next epoch start timestamp.
    function nextEpochStartTime() public view returns (uint256) {
        uint256 timestampOffset = (currentEpoch(block.timestamp) + 1) *
            EPOCH_DURATION;
        return (genesisEpoch + timestampOffset);
    }

    /// @notice Returns the epoch to lock until for a lock executed
    ///         at this moment.
    /// @return The calculated epoch.
    function freshLockEpoch() public view returns (uint256) {
        return currentEpoch(block.timestamp) + LOCK_DURATION_EPOCHS;
    }

    /// @notice Returns the timestamp to lock until for a lock executed
    ///         at this moment.
    /// @return The calculated timestamp.
    function freshLockTimestamp() public view returns (uint40) {
        return
            uint40(
                genesisEpoch +
                    (currentEpoch(block.timestamp) * EPOCH_DURATION) +
                    LOCK_DURATION
            );
    }

    /// View Functions ///

    /// @notice Calculates the votes for a single lock of a user based
    ///         on a specific timestamp.
    /// @param user The address of the user whose lock is being used
    ///              for the calculation.
    /// @param lockIndex The index of the lock to calculate votes for.
    /// @param time The timestamp to use for the calculation.
    /// @param currentLockBoost The current voting boost a lock gets for being continuous.
    /// @return The number of votes for the specified lock at the given timestamp.
    function getVotesForSingleLockForTime(
        address user,
        uint256 lockIndex,
        uint256 time,
        uint256 currentLockBoost
    ) public view returns (uint256) {
        Lock storage lock = userLocks[user][lockIndex];

        if (lock.unlockTime < time) {
            return 0;
        }

        if (lock.unlockTime == CONTINUOUS_LOCK_VALUE) {
            unchecked {
                return ((lock.amount * currentLockBoost) / 10000);
            }
        }

        // Equal to epochsLeft = (lock.unlockTime - time) / EPOCH_DURATION
        // (lock.amount * epochsLeft) / LOCK_DURATION_EPOCHS.
        return
            (lock.amount * ((lock.unlockTime - time) / EPOCH_DURATION)) /
            LOCK_DURATION_EPOCHS;
    }

    /// @notice Calculates the penalty to `lockIndex`'s underlying CVE
    ///         position for an immediate lock unlock.
    /// @param user The address of the user whose lock is being used
    ///              for the calculation.
    /// @param lockIndex The index of the lock to calculate penalty for.
    /// @return The penalty associated with immediately unlocking `lockIndex`,
    ///         in `WAD`.
    function getUnlockPenalty(
        address user,
        uint256 lockIndex
    ) public view returns (uint256) {
        Lock[] storage locks = userLocks[user];

        // Length is index + 1 so has to be less than array length.
        if (lockIndex >= locks.length) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        // Check if the user is trying to early expire an expired lock.
        if (block.timestamp >= locks[lockIndex].unlockTime) {
            return 0;
        }

        uint256 penalty = centralRegistry.earlyUnlockPenaltyMultiplier();

        if (penalty == 0) {
            return 0;
        }

        Lock memory lock = locks[lockIndex];
        return _getUnlockPenalty(lock.amount, penalty, lock.unlockTime);
    }

    /// Transfer Locked Functions ///

    /// @notice Overridden transfer function to prevent token transfers.
    /// @dev This function always reverts, as the token is non-transferrable.
    /// @return This function always reverts and does not return a value.
    function transfer(address, uint256) public pure override returns (bool) {
        revert VeCVE__NonTransferrable();
    }

    /// @notice Overridden transferFrom function to prevent token transfers.
    /// @dev This function always reverts, as the token is non-transferrable.
    /// @return This function always reverts and does not return a value.
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert VeCVE__NonTransferrable();
    }

    /// INTERNAL FUNCTIONS ///

    /// See claimRewardsFor in CVELocker.
    function _claimRewards(
        address user,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) internal {
        uint256 epochs = cveLocker.epochsToClaim(user);
        if (epochs > 0) {
            cveLocker.claimRewardsFor(user, epochs, rewardsData, params, aux);
        }
    }

    /// @notice Internal function to lock tokens for a user.
    /// @param recipient The address of the user receiving the lock.
    /// @param amount The amount of tokens to lock.
    /// @param continuousLock Whether the lock is continuous or not.
    function _lock(
        address recipient,
        uint256 amount,
        bool continuousLock
    ) internal {
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
            // Increment `recipient` data.
            _incrementPoints(recipient, _getCLPoints(amount));
        } else {
            userLocks[recipient].push(
                Lock({
                    amount: uint216(amount),
                    unlockTime: freshLockTimestamp()
                })
            );
            // Increment `recipient` data.
            _incrementPoints(recipient, amount);
            _incrementTokenUnlocks(recipient, freshLockEpoch(), amount);
        }

        _mint(recipient, amount);
    }

    /// @notice Internal function to handle whenever a user needs an increase
    ///         to a locked amount and extended lock.
    /// @param recipient The address to lock and extend tokens for.
    /// @param amount The amount to increase the lock by.
    /// @param lockIndex The index of the lock to extend.
    /// @param continuousLock Whether the lock should be continuous or not.
    function _increaseAmountAndExtendLockFor(
        address recipient,
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock
    ) internal {
        Lock[] storage user = userLocks[recipient];

        // Length is index + 1 so has to be less than array length.
        if (lockIndex >= user.length) {
            _revert(_INVALID_LOCK_SELECTOR);
        }

        uint40 unlockTimestamp = user[lockIndex].unlockTime;

        if (unlockTimestamp == CONTINUOUS_LOCK_VALUE) {
            if (!continuousLock) {
                _revert(_INVALID_LOCK_SELECTOR);
            }

            // Increment the chain and user token point balance.
            _incrementPoints(recipient, _getCLPoints(amount));

            // Update the lock value to include the new locked tokens.
            user[lockIndex].amount = uint216(user[lockIndex].amount + amount);
        } else {
            // User was not continuous locked prior so we will need
            // to clean up their unlock data.
            if (unlockTimestamp < block.timestamp) {
                _revert(_INVALID_LOCK_SELECTOR);
            }

            uint256 previousAmount = user[lockIndex].amount;
            uint256 newAmount = previousAmount + amount;
            uint256 priorEpoch = currentEpoch(user[lockIndex].unlockTime);

            if (continuousLock) {
                user[lockIndex].unlockTime = CONTINUOUS_LOCK_VALUE;

                // Decrement their previous non-continuous lock value
                // and increase points by the continuous lock value.
                _updateDataToContinuousOn(
                    recipient,
                    priorEpoch,
                    _getCLPoints(newAmount) - previousAmount,
                    previousAmount
                );
            } else {
                user[lockIndex].unlockTime = freshLockTimestamp();

                // Update unlock data removing the old lock amount from
                // old epoch and add the new lock amount to the new epoch.
                _updateUnlockDataToExtendedLock(
                    recipient,
                    priorEpoch,
                    freshLockEpoch(),
                    previousAmount,
                    newAmount
                );

                // Increment the chain and user token point balance.
                _incrementPoints(recipient, amount);
            }

            user[lockIndex].amount = uint216(newAmount);
        }

        _mint(recipient, amount);

        emit Locked(recipient, amount);
    }

    /// @notice Removes a lock from `user`.
    /// @param user An array of locks for `user`.
    /// @param lockIndex The index of the lock to be removed.
    function _removeLock(Lock[] storage user, uint256 lockIndex) internal {
        uint256 lastLockIndex = user.length - 1;

        if (lockIndex != lastLockIndex) {
            Lock memory lock = user[lockIndex];
            user[lockIndex] = user[lastLockIndex];
            user[lastLockIndex] = lock;
        }

        user.pop();
    }

    /// @notice Increment token points.
    /// @dev Increments the token points of the chain and user.
    /// @param user The address of the user.
    /// @param points The number of points to add.
    function _incrementPoints(address user, uint256 points) internal {
        // We know theres never more than 420m
        // so this should never over/underflow.
        unchecked {
            chainPoints = chainPoints + points;
            userPoints[user] = userPoints[user] + points;
        }
    }

    /// @notice Reduce token points.
    /// @dev Reduces the token points of the chain and user.
    /// @param user The address of the user.
    /// @param points The number of points to reduce.
    function _reducePoints(address user, uint256 points) internal {
        // We know theres never more than 420m
        // so this should never over/underflow.
        unchecked {
            chainPoints = chainPoints - points;
            userPoints[user] = userPoints[user] - points;
        }
    }

    /// @notice Increment token unlocks.
    /// @dev Increments the token unlocks of the chain and user
    ///      for a given epoch.
    /// @param user The address of the user.
    /// @param epoch The epoch to add the unlocks.
    /// @param points The number of points to add.
    function _incrementTokenUnlocks(
        address user,
        uint256 epoch,
        uint256 points
    ) internal {
        // We know theres never more than 420m
        // so this should never over/underflow.
        unchecked {
            chainUnlocksByEpoch[epoch] = chainUnlocksByEpoch[epoch] + points;
            userUnlocksByEpoch[user][epoch] =
                userUnlocksByEpoch[user][epoch] +
                points;
        }
    }

    /// @notice Reduce token unlocks.
    /// @dev Reduces the token unlocks of the chain and user
    ///      for a given epoch.
    /// @param user The address of the user.
    /// @param epoch The epoch to reduce the unlocks.
    /// @param points The number of points to reduce.
    function _reduceTokenUnlocks(
        address user,
        uint256 epoch,
        uint256 points
    ) internal {
        // We know theres never more than 420m
        // so this should never over/underflow.
        unchecked {
            chainUnlocksByEpoch[epoch] = chainUnlocksByEpoch[epoch] - points;
            userUnlocksByEpoch[user][epoch] =
                userUnlocksByEpoch[user][epoch] -
                points;
        }
    }

    /// @notice Update token unlock data from an extended lock that
    ///         is not continuous.
    /// @dev Updates the token points and token unlocks for the chain
    ///      and user from a continuous lock for a given epoch.
    /// @param user The address of the user.
    /// @param previousEpoch The previous unlock epoch.
    /// @param epoch The new unlock epoch.
    /// @param previousPoints The previous points to remove
    ///                        from the old unlock time.
    /// @param points The new token points to add for the new unlock time.
    function _updateUnlockDataToExtendedLock(
        address user,
        uint256 previousEpoch,
        uint256 epoch,
        uint256 previousPoints,
        uint256 points
    ) internal {
        // We know theres never more than 420m
        // so this should never over/underflow.
        unchecked {
            chainUnlocksByEpoch[previousEpoch] =
                chainUnlocksByEpoch[previousEpoch] -
                previousPoints;
            userUnlocksByEpoch[user][previousEpoch] =
                userUnlocksByEpoch[user][previousEpoch] -
                previousPoints;
            chainUnlocksByEpoch[epoch] = chainUnlocksByEpoch[epoch] + points;
            userUnlocksByEpoch[user][epoch] =
                userUnlocksByEpoch[user][epoch] +
                points;
        }
    }

    /// @notice Update token data from continuous lock on.
    /// @dev Updates the token points and token unlocks for the chain
    ///      and user from a continuous lock for a given epoch.
    /// @param user The address of the user.
    /// @param epoch The epoch to update the data.
    /// @param points The token points to add.
    /// @param unlocks The token unlocks to reduce.
    function _updateDataToContinuousOn(
        address user,
        uint256 epoch,
        uint256 points,
        uint256 unlocks
    ) internal {
        // We know theres never more than 420m
        // so this should never over/underflow.
        unchecked {
            chainPoints = chainPoints + points;
            chainUnlocksByEpoch[epoch] = chainUnlocksByEpoch[epoch] - unlocks;
            userPoints[user] = userPoints[user] + points;
            userUnlocksByEpoch[user][epoch] =
                userUnlocksByEpoch[user][epoch] -
                unlocks;
        }
    }

    /// @notice Update token data from an early expired lock.
    /// @dev Updates the token points and token unlocks for the chain
    ///      and user from an early expired lock for a given time.
    /// @param user The address of the user.
    /// @param points The token points to reduce.
    /// @param unlockTime The timestamp to update the data.
    function _updateDataFromEarlyUnlock(
        address user,
        uint256 points,
        uint256 unlockTime
    ) internal {
        if (unlockTime == CONTINUOUS_LOCK_VALUE) {
            _reducePoints(user, _getCLPoints(points));
        } else {
            _reducePoints(user, points);
            _reduceTokenUnlocks(user, currentEpoch(unlockTime), points);
        }
    }

    /// @notice Calculates the continuous lock token point value for basePoints.
    /// @param basePoints The token points to be used in the calculation.
    /// @return The calculated continuous lock token point value.
    function _getCLPoints(uint256 basePoints) internal pure returns (uint256) {
        return CL_POINT_MULTIPLIER * basePoints;
    }

    /// @notice Calculates the current unlock penalty for early unlocking
    ///         a lock expiring at `unlockTime`
    /// @param amount The token amount to calculate the penalty against.
    /// @param penalty The current early unlock penalty,
    ///                for full length locks, in `WAD`.
    /// @param unlockTime The unlock timestamp to calculate the penalty for.
    /// @return The early unlock penalty for a `amount` lock,
    ///         unlocking at `unlockTime`.
    function _getUnlockPenalty(
        uint256 amount,
        uint256 penalty,
        uint256 unlockTime
    ) internal view returns (uint256) {
        // Penalty value = lock amount * penalty multiplier, in `WAD`,
        // linearly scaled down as `unlockTime` scales from `LOCK_DURATION`
        // down to 0.
        return
            (amount *
                ((penalty * (LOCK_DURATION - (unlockTime - block.timestamp))) /
                    LOCK_DURATION)) / WAD;
    }

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    /// @dev Internal helper for checking whether a lock is allowed.
    ///      Requires a minimum lock size of 1 CVE, in `WAD`.
    function _canLock(uint256 amount) internal view {
        assembly {
            if lt(amount, WAD) {
                mstore(0x0, _INVALID_LOCK_SELECTOR)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }

        if (isShutdown == 2) {
            _revert(_VECVE_SHUTDOWN_SELECTOR);
        }
    }
}
