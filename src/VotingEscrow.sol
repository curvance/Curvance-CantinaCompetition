//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/ICveCVE.sol";
import "./interfaces/IStakingProxy.sol";

contract VotingEscrow is Ownable {
    using SafeERC20 for IERC20;

    event Locked(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount, bool _relocked);
    event Unwrap(address indexed _to, uint256 _amount);
    event RewardPaid(address indexed _user, address indexed _rewardsToken, uint256 _amount);
    event KickReward(address indexed _user, address indexed _kicked, uint256 _amount);
    event FundedReward(address indexed _token, uint256 _amount);
    event RewardAdded(address token, uint256 amount);
    event TokenRecovered(address _token, address _to, uint256 _amount);

    struct Balance {
        uint224 amount;
        /// @dev Tracks the first unexpired lock
        uint32 nextUnlockIndex;
    }
    struct Lock {
        uint224 amount;
        uint32 unlockTime;
    }
    struct Reward {
        uint40 periodFinish;
        uint216 rewardRate;
        uint40 lastUpdateTime;
        uint216 rewardPerTokenStored;
    }

    IERC20 public immutable cve;
    address public immutable wrapper;
    uint32 public firstEpochStartTime;

    address public staking;
    bool public isShutdown;
    uint8 public immutable decimals;

    uint256 public constant stakeOffsetOnLock = 500;

    uint256 public delegatedVotes;

    address[] public rewardTokens;

    uint256 public totalLockedSupply;

    uint256 public constant REWARDS_DURATION = 86_400 * 7;
    uint256 public constant LOCK_DURATION = REWARDS_DURATION * 52;

    uint256 public constant DENOMINATOR = 10_000;
    uint256 public kickRewardPerEpoch = 100;
    uint256 public gracePeriod = REWARDS_DURATION * 4;

    mapping(uint256 => uint256) public totalSupplyPerEpoch;
    mapping(address => Reward) public rewardData;
    mapping(address => mapping(address => uint256)) public claimableRewards;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    /// @dev reward token -> distributor -> is approved to add rewards
    mapping(address => mapping(address => bool)) public rewardDistributors;

    mapping(address => Balance) public userBalances;
    mapping(address => Lock[]) public userLocks;

    string public name;
    string public symbol;

    /// @dev Owner should be the Curvance team's multisig
    constructor(IERC20 _cve, address _wrapper) Ownable() {
        name = "Vote Escrow Curvance Token";
        symbol = "veCVE";
        decimals = 18;

        cve = _cve;
        wrapper = _wrapper;

        // first epoch start period. will be used for view functions
        firstEpochStartTime = uint32(block.timestamp);
    }

    /**
     * @notice deposit cve for CVECVE for an account
     * @param _account the account for whom to wrap cve
     * @param _amount amount of cve tokens to wrap
     */
    function deposit(address _account, uint256 _amount) external {
        updateReward(_account);

        cve.safeTransferFrom(msg.sender, address(this), _amount);

        totalLockedSupply += _amount;
        /// @dev Delegates votes to the team multisig
        delegatedVotes += _amount;

        ICveCVE(wrapper).mint(_account, _amount);
        // stake directly
        cve.safeIncreaseAllowance(address(staking), _amount);
        IStakingProxy(staking).stake(_amount);
    }

    /**
     * @dev Set kick incentive
     * @param _rate rate per epoch
     * @param _delay grace period factor
     */
    function setKickIncentive(uint256 _rate, uint256 _delay) external onlyOwner {
        require(_rate <= 500, "over max rate"); /// @dev Max 5% per epoch
        require(_delay >= 2, "min delay"); /// @dev Minimum 2 weeks of grace
        kickRewardPerEpoch = _rate;
        gracePeriod = REWARDS_DURATION * _delay;
    }

    /**
     * @dev Shuts down the contract, unstakes all tokens, releases all locks
     */
    function shutdown() external onlyOwner {
        if (staking != address(0)) {
            uint256 stakedBalance = IStakingProxy(staking).getBalance();
            IStakingProxy(staking).withdraw(stakedBalance);
        }
        isShutdown = true;
    }

    /**
     * @dev Set approvals for staking. Should be called immediately after deployment
     */
    function setApprovals() external onlyOwner {
        cve.safeIncreaseAllowance(staking, type(uint256).max);
    }

    /// @notice Set the staking contract for the underlying CVE
    function setStakingContract(address _staking) external onlyOwner {
        // TODO: 0xhamish. alternatively let staking contract have isShutdown flag so one can change staking contract
        require(staking == address(0), "already set");
        staking = _staking;
    }

    /**
     * @dev Approve reward distributor
     * @param _rewardsToken token to be approved
     * @param _distributor address to distribute rewards
     * @param _approved flag approved or not
     */
    function approveRewardDistributor(
        address _rewardsToken,
        address _distributor,
        bool _approved
    ) external onlyOwner {
        require(rewardData[_rewardsToken].lastUpdateTime > 0, "!exist");
        rewardDistributors[_rewardsToken][_distributor] = _approved;
    }

    /**
     * @dev Add reward to be distributed by a distributor
     * @param _rewardToken reward token to be approved
     * @param _distributor address to distribute rewards
     */
    function addReward(address _rewardToken, address _distributor) external onlyOwner {
        require(rewardData[_rewardToken].lastUpdateTime == 0, "exists");
        require(_rewardToken != address(cve), "!assign");
        rewardTokens.push(_rewardToken);
        rewardData[_rewardToken].lastUpdateTime = uint40(block.timestamp);
        rewardData[_rewardToken].periodFinish = uint40(block.timestamp);
        rewardDistributors[_rewardToken][_distributor] = true;
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
    ) external onlyOwner {
        require(_token != address(cve), "cannot withdraw staking token");
        require(rewardData[_token].lastUpdateTime == 0, "cannot withdraw reward token");
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }
        IERC20(_token).safeTransfer(_to, _amount);

        emit TokenRecovered(_token, _to, _amount);
    }

    /**
     * @notice lock cve for account
     * @param _account the account for whom to lock
     * @param _amount amount of cve tokens to lock
     */
    function lock(address _account, uint224 _amount) external {
        cve.safeTransferFrom(msg.sender, address(this), _amount);

        _lock(_account, _amount, false, true);
    }

    /**
     * @notice withdraw and lock cve. By design, CVECVE can only be withdrawn for a locked cve position
     * @param _amount amount of CVECVE tokens to unwrap
     */
    function unwrap(uint224 _amount) external {
        ICveCVE(wrapper).burn(msg.sender, _amount);
        totalLockedSupply -= _amount;
        delegatedVotes -= _amount;
        // @dev don't stake because _amount of cve were staked during deposit
        _lock(msg.sender, _amount, false, false);

        emit Unwrap(msg.sender, _amount);
    }

    /**
     * @notice get rewards for an account
     * @param _account the account for whom to get rewards
     */
    function getRewards(address _account) external {
        updateReward(_account);

        for (uint256 i; i < rewardTokens.length; i++) {
            address _rewardToken = rewardTokens[i];
            uint256 claimable = claimableRewards[_account][_rewardToken];
            if (claimable > 0) {
                claimableRewards[_account][_rewardToken] = 0;
                IERC20(_rewardToken).safeTransfer(_account, claimable);
                emit RewardPaid(_account, _rewardToken, claimable);
            }
        }
    }

    /**
     * @notice get reward for an account for a given reward token
     * @param _account the account for whom to get reward
     * @param _rewardToken the reward token
     */
    function getReward(address _account, address _rewardToken) external {
        updateReward(_account);

        uint256 amount = claimableRewards[_account][_rewardToken];
        if (amount > 0) {
            claimableRewards[_account][_rewardToken] = 0;
            IERC20(_rewardToken).safeTransfer(_account, amount);

            emit RewardPaid(_account, _rewardToken, amount);
        }
    }

    /**
     * @notice Withdraw/relock all currently locked tokens where the unlock time has passed
     * @param _withdrawTo the account to receive withdrawn tokens
     */
    function processExpiredLocks(address _withdrawTo) external {
        _processExpiredLocks(msg.sender, false, _withdrawTo, msg.sender, false);
    }

    /**
     * @notice Withdraw/relock all currently locked tokens where the unlock time has passed
     * @param _relock whether to relock or not
     */
    function processExpiredLocks(bool _relock) external {
        _processExpiredLocks(msg.sender, _relock, msg.sender, msg.sender, false);
    }

    /**
     * @notice Kick expired locks for a given account
     * @param _account account for which to kick expired locks
     */
    function kickExpiredLocks(address _account) external {
        /// @dev Allow kick after grace period
        _processExpiredLocks(_account, false, _account, msg.sender, true);
    }

    /**
     * @notice Total token balance of an account, including unlocked but not withdrawn tokens
     * @param _user account for which to check locked balance
     */
    function lockedBalanceOf(address _user) external view returns (uint256) {
        return userBalances[_user].amount;
    }

    /**
     * @notice Information on a user's locked balances
     * @param _user account for which to get information
     */
    function lockedBalances(address _user)
        external
        view
        returns (
            uint256 total,
            uint256 unlockable,
            uint256 locked,
            Lock[] memory lockData
        )
    {
        Lock[] storage locks = userLocks[_user];
        Balance storage userBalance = userBalances[_user];
        uint256 nextUnlockIndex = userBalance.nextUnlockIndex;
        uint256 idx;
        for (uint256 i = nextUnlockIndex; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp) {
                if (idx == 0) {
                    lockData = new Lock[](locks.length - i);
                }
                lockData[idx] = locks[i];
                idx++;
                locked = locked + locks[i].amount;
            } else {
                unlockable = unlockable + locks[i].amount;
            }
        }
        return (userBalance.amount, unlockable, locked, lockData);
    }

    /**
     * @notice Locked balance of an account which only includes properly locked tokens
     *         as of the most recent eligible epoch. Returns delegated votes for escrow owner
     * @param _account account for which to get information
     */
    function balanceOf(address _account) external view returns (uint256) {
        if (_account == owner()) {
            return delegatedVotes;
        }

        Lock[] storage locks = userLocks[_account];
        uint256 idx = locks.length;
        uint256 nextUnlockIndex = userBalances[_account].nextUnlockIndex;
        /// @dev Start with user's current locked balance
        uint256 amount = userBalances[_account].amount;
        /// @dev Removing old records is more gas efficient than adding up
        for (uint256 i = nextUnlockIndex; i < idx; i++) {
            if (locks[i].unlockTime <= block.timestamp) {
                amount -= locks[i].amount;
            } else {
                /// @dev Stop now as no futher checks are needed
                break;
            }
        }

        /// @dev Also remove amount in the current epoch
        uint256 currentEpoch = (block.timestamp / REWARDS_DURATION) * REWARDS_DURATION;
        if (idx > 0 && uint256(locks[idx - 1].unlockTime) - LOCK_DURATION > currentEpoch) {
            amount -= locks[idx - 1].amount;
        }

        return amount;
    }

    /**
     * @notice Reward per token
     * @param _rewardsToken rewards token
     */
    function rewardPerToken(address _rewardsToken) external view returns (uint256) {
        return _rewardPerToken(_rewardsToken);
    }

    /**
     * @notice Reward per token for duration
     * @param _rewardsToken rewards token
     */
    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return uint256(rewardData[_rewardsToken].rewardRate) * REWARDS_DURATION;
    }

    /**
     * @notice Get number of epochs
     */
    function epochCount() external view returns (uint256) {
        return getCurrentEpochIndex() + 1;
    }

    /**
     * @notice Supply of all properly locked balances at most recent eligible epoch
     */
    function totalSupply() external view returns (uint256) {
        uint256 currentEpoch = getCurrentEpoch();
        uint256 cutOffEpoch = currentEpoch - LOCK_DURATION;

        uint256 currentEpochIndex = getCurrentEpochIndex();
        if (currentEpochIndex * REWARDS_DURATION + firstEpochStartTime > currentEpoch) {
            currentEpochIndex -= 1;
        }

        //traverse inversely to make more current queries more gas efficient
        uint256 supply;
        for (uint256 i = currentEpochIndex; i + 1 != 0; i--) {
            uint256 epochDate = i * REWARDS_DURATION + firstEpochStartTime;
            if (epochDate <= cutOffEpoch) {
                break;
            }
            supply += totalSupplyPerEpoch[epochDate];
        }

        return supply;
    }

    /**
     * @notice Supply of all properly locked BOOSTED balances at the given epoch
     * @param _epochIndex index of epoch at which total supply is calculated
     */
    function totalSupplyAtEpochIndex(uint256 _epochIndex) public view returns (uint256) {
        if (getCurrentEpochIndex() < _epochIndex) {
            return 0;
        }
        uint256 epochStart = _epochIndex * REWARDS_DURATION + firstEpochStartTime;
        uint256 cutOffEpoch = epochStart - LOCK_DURATION;

        uint256 currentEpochIndex = getCurrentEpochIndex();

        //traverse inversely to make more current queries more gas efficient
        uint256 supply;
        for (uint256 i = currentEpochIndex; i + 1 != 0; i--) {
            uint256 epochDate = i * REWARDS_DURATION + firstEpochStartTime;
            if (epochDate <= cutOffEpoch) {
                break;
            }
            supply += totalSupplyPerEpoch[epochDate];
        }

        return supply;
    }

    /**
     * @notice Return currently locked but not active balance
     * @param _user account for whom to compute pending lock
     */
    function pendingLockOf(address _user) external view returns (uint256 amount) {
        Lock[] storage locks = userLocks[_user];

        uint256 locksLength = locks.length;

        //return amount if latest lock is in the future
        uint256 currentEpoch = (block.timestamp / REWARDS_DURATION) * REWARDS_DURATION;
        if (locksLength > 0 && uint256(locks[locksLength - 1].unlockTime) - LOCK_DURATION > currentEpoch) {
            return locks[locksLength - 1].amount;
        }

        return 0;
    }

    /**
     * @notice Return currently locked but not active balance
     * @param _user account for whom to compute pending lock
     */
    function pendingLockAtEpochOf(uint256 _epochIndex, address _user) external view returns (uint256) {
        Lock[] storage locks = userLocks[_user];

        uint256 currentEpochIndex = getCurrentEpochIndex();
        if (_epochIndex > currentEpochIndex) {
            return 0;
        }
        uint256 nextEpoch = _epochIndex * REWARDS_DURATION + firstEpochStartTime + REWARDS_DURATION;
        //traverse inversely
        for (uint256 i = locks.length - 1; i + 1 != 0; i--) {
            uint256 lockEpoch = uint256(locks[i].unlockTime) - LOCK_DURATION;

            //return the next epoch balance
            if (lockEpoch == nextEpoch) {
                return locks[i].amount;
            } else if (lockEpoch < nextEpoch) {
                //no need to check anymore
                break;
            }
        }

        return 0;
    }

    /**
     * @notice Return current epoch
     */
    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp / REWARDS_DURATION) * REWARDS_DURATION;
    }

    /**
     * @notice Return next epoch
     */
    function getNextEpoch() public view returns (uint256) {
        return getCurrentEpoch() + REWARDS_DURATION;
    }

    /**
     * @notice Return index of current epoch
     */
    function getCurrentEpochIndex() public view returns (uint256) {
        uint256 currentEpoch = getCurrentEpoch();
        // will get rounded
        uint256 currentEpochIndex = (currentEpoch - firstEpochStartTime) / REWARDS_DURATION;
        return currentEpochIndex;
    }

    /**
     * @notice Return index of a given epoch. Return max uint if epoch is out of place
     * @param _epoch the epoch
     */
    function getEpochIndex(uint256 _epoch) public view returns (uint256) {
        uint256 currentEpoch = getCurrentEpoch();
        if (_epoch > currentEpoch) {
            return type(uint256).max;
        }

        return (_epoch - firstEpochStartTime) / REWARDS_DURATION;
    }

    /**
     * @notice Update reward params for an account
     * @param _account account for whom to update reward params
     */
    function updateReward(address _account) public {
        {
            //stack too deep
            Balance storage userBalance = userBalances[_account];
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                address token = rewardTokens[i];
                rewardData[token].rewardPerTokenStored = uint216(_rewardPerToken(token));
                rewardData[token].lastUpdateTime = uint40(_lastTimeRewardApplicable(rewardData[token].periodFinish));
                if (_account != address(0)) {
                    //check if reward is boostable or not. use boosted or locked balance accordingly
                    claimableRewards[_account][token] = _earned(_account, token, userBalance.amount);
                    userRewardPerTokenPaid[_account][token] = uint256(rewardData[token].rewardPerTokenStored);
                }
            }
        }
    }

    /**
     * @dev Return last finished time applicable of a reward token
     * @param _rewardsToken rewards token
     */
    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return _lastTimeRewardApplicable(rewardData[_rewardsToken].periodFinish);
    }

    ///////////////////////////////////////////
    ////////////// Internal Functions /////////
    ///////////////////////////////////////////

    /**
     * @dev Return reward per token
     * @param _rewardsToken rewards token
     */
    function _rewardPerToken(address _rewardsToken) internal view returns (uint256) {
        if (totalLockedSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }

        return
            rewardData[_rewardsToken].rewardPerTokenStored +
            (((_lastTimeRewardApplicable(rewardData[_rewardsToken].periodFinish) -
                rewardData[_rewardsToken].lastUpdateTime) *
                rewardData[_rewardsToken].rewardRate *
                1e18) / totalLockedSupply);
    }

    /**
     * @dev Return earned amount of reward tokens for an account
     * @param _user account to calculate for
     * @param _rewardsToken reward token
     * @param _balance balance to use in calculation
     */
    function _earned(
        address _user,
        address _rewardsToken,
        uint256 _balance
    ) internal view returns (uint256) {
        return
            (_balance * (_rewardPerToken(_rewardsToken) - userRewardPerTokenPaid[_user][_rewardsToken])) /
            1e18 +
            claimableRewards[_user][_rewardsToken];
    }

    /**
     * @dev Return last finished time applicable of a reward token. Internal function
     * @param _finishTime finish time
     */
    function _lastTimeRewardApplicable(uint256 _finishTime) internal view returns (uint256) {
        return Math.min(block.timestamp, _finishTime);
    }

    /**
     * @dev Vote-lock cve tokens
     * @param _account account for whom to lock
     * @param _amount amount of tokens to lock
     * @param _isRelock whether or not this action is a fresh lock
     * @param _stake whether or not to stake cve directly
     */
    function _lock(
        address _account,
        uint224 _amount,
        bool _isRelock,
        bool _stake
    ) internal {
        require(!isShutdown, "shutdown");
        require(_amount > 0, "invalid amount");

        updateReward(_account);

        Balance storage balance = userBalances[_account];
        balance.amount += _amount;
        totalLockedSupply += _amount;

        uint256 lockEpoch = (block.timestamp / REWARDS_DURATION) * REWARDS_DURATION;
        totalSupplyPerEpoch[lockEpoch] += _amount;

        /// @dev If a fresh lock, add on an extra duration period
        if (!_isRelock) lockEpoch += REWARDS_DURATION;
        uint256 unlockTime = lockEpoch + LOCK_DURATION;

        uint256 idx = userLocks[_account].length;

        /// @dev If the latest user lock is smaller than this lock, always just add new entry to the end of the list
        if (idx == 0 || userLocks[_account][idx - 1].unlockTime < unlockTime) {
            userLocks[_account].push(Lock({ amount: _amount, unlockTime: uint32(unlockTime) }));
        } else {
            /// @dev Else add to a current lock

            /// @dev If latest lock is further in the future, lower index.
            // This can only happen if relocking an expired lock after creating a
            // new lock
            if (userLocks[_account][idx - 1].unlockTime > unlockTime) idx--;

            /// @dev If index points to the epoch when same unlock time, update it.
            // This is always true with a normal lock but maybe not with relock
            if (userLocks[_account][idx - 1].unlockTime == unlockTime) {
                userLocks[_account][idx - 1].amount += _amount;
            } else {
                /// @dev Can only enter here if a relock is made after a lock
                /// and there's no lock entry

                /// @dev Reset index
                idx = userLocks[_account].length;

                Lock storage lastLock = userLocks[_account][idx - 1];

                /// @dev Move last lock to end
                userLocks[_account].push(Lock({ amount: lastLock.amount, unlockTime: lastLock.unlockTime }));

                /// @dev Insert current lock by overwriting previous last lock
                lastLock.amount = _amount;
                lastLock.unlockTime = uint32(unlockTime);
            }
        }

        // stake amount directly
        if (_stake) {
            cve.safeIncreaseAllowance(address(staking), _amount);
            IStakingProxy(staking).stake(_amount);
        }

        emit Locked(_account, _amount);
    }

    /**
     * @dev Process expired locks
     * @param _account account for whom to process
     * @param _relock whether to relock processed tokens
     * @param _withdrawTo receiver of processed tokens
     * @param _rewardAddress in the event of a kick incentive/reward, receiver of said reward
     * @param _useGracePeriod in the event of kicking expired locks, grace period after 
            which expired locks can be kicked
     */
    function _processExpiredLocks(
        address _account,
        bool _relock,
        address _withdrawTo,
        address _rewardAddress,
        bool _useGracePeriod
    ) internal {
        updateReward(_account);

        Lock[] storage locks = userLocks[_account];
        Balance storage balance = userBalances[_account];
        uint224 locked;
        uint256 length = locks.length;
        uint256 reward;
        uint256 checkTime = _useGracePeriod ? block.timestamp - gracePeriod : block.timestamp;

        if (isShutdown || locks[length - 1].unlockTime <= checkTime) {
            locked = balance.amount;

            balance.nextUnlockIndex = uint32(length);

            //check for kick reward
            //this wont have the exact reward rate that you would get if looped through
            //but this section is supposed to be for quick and easy low gas processing of all locks
            //we'll assume that if the reward was good enough someone would have processed at an earlier epoch
            if (_useGracePeriod) {
                uint256 currentEpoch = (checkTime / REWARDS_DURATION) * REWARDS_DURATION;
                uint256 epochsover = (currentEpoch - uint256(locks[length - 1].unlockTime)) / REWARDS_DURATION;
                uint256 rewardRate = Math.min(kickRewardPerEpoch * (epochsover + 1), DENOMINATOR);

                reward = (uint256(locks[length - 1].amount) * rewardRate) / DENOMINATOR;
            }
        } else {
            uint32 nextUnlockIndex = balance.nextUnlockIndex;
            for (uint256 i = nextUnlockIndex; i < length; i++) {
                if (locks[i].unlockTime > checkTime) break;

                locked += locks[i].amount;

                //check for kick reward
                //each epoch over due increases reward
                if (_useGracePeriod) {
                    uint256 currentEpoch = (checkTime / REWARDS_DURATION) * REWARDS_DURATION;
                    uint256 epochsover = (currentEpoch - uint256(locks[length - 1].unlockTime)) / REWARDS_DURATION;
                    uint256 rewardRate = Math.min(kickRewardPerEpoch * (epochsover + 1), DENOMINATOR);

                    reward += (uint256(locks[i].amount) * rewardRate) / DENOMINATOR;
                }

                nextUnlockIndex++;
            }
            balance.nextUnlockIndex = nextUnlockIndex;
        }
        require(locked > 0, "no exp locks");

        balance.amount -= locked;
        totalLockedSupply -= locked;

        emit Withdrawn(_account, locked, _relock);

        // send process incentive
        if (reward > 0) {
            /// @dev Preallocate enough CVE from stake contract to pay for both reward and withdraw
            _allocateCVEForWithdrawal(uint256(locked));

            locked -= uint224(reward);

            cve.safeTransfer(_rewardAddress, reward);

            emit KickReward(_rewardAddress, _account, reward);
        }

        // relock or return to user
        if (_relock) {
            _lock(_withdrawTo, locked, true, true);
        } else {
            _transfer(_withdrawTo, locked, true);
        }
    }

    /**
     * @dev Transfer cve to account
     * @param _account account to which funds are transferred
     * @param _amount amount of tokens to transfer
     */
    function _transfer(
        address _account,
        uint256 _amount,
        bool
    ) internal {
        _allocateCVEForWithdrawal(_amount);

        cve.safeTransfer(_account, _amount);
    }

    /**
     * @dev Allocate cve to this contract for transfer
     * @param _amount amount of tokens to allocate
     */
    function _allocateCVEForWithdrawal(uint256 _amount) internal {
        uint256 balance = cve.balanceOf(address(this));
        if (_amount > balance) {
            IStakingProxy(staking).withdraw(_amount - balance);
        }
    }

    /**
     * @dev Notify contract of new distributed rewards
     * @param _rewardsToken reward token
     * @param _amount amount of reward tokens
     */
    function _notifyReward(address _rewardsToken, uint256 _amount) internal {
        Reward storage rdata = rewardData[_rewardsToken];

        if (block.timestamp >= rdata.periodFinish) {
            rdata.rewardRate = uint216(_amount / REWARDS_DURATION);
        } else {
            uint256 remaining = uint256(rdata.periodFinish) - block.timestamp;
            uint256 leftover = remaining * rdata.rewardRate;
            rdata.rewardRate = uint216((_amount + leftover) / REWARDS_DURATION);
        }

        rdata.lastUpdateTime = uint40(block.timestamp);
        rdata.periodFinish = uint40(block.timestamp + REWARDS_DURATION);
    }

    /**
     * @dev Notify contract of new distributed rewards
     * @param _rewardsToken reward token
     * @param _amount amount of reward tokens
     */
    function notifyRewardAmount(address _rewardsToken, uint256 _amount) external {
        updateReward(address(0));

        require(rewardDistributors[_rewardsToken][msg.sender], "not distributor");
        require(_amount > 0, "No reward");

        _notifyReward(_rewardsToken, _amount);

        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the _reward amount
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), _amount);

        emit RewardAdded(_rewardsToken, _amount);
    }
}
