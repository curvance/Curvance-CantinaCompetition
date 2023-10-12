// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { GaugeController, GaugeErrors } from "contracts/gauge/GaugeController.sol";
import { ChildGaugePool } from "contracts/gauge/ChildGaugePool.sol";

import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";

contract GaugePool is GaugeController, ReentrancyGuard {
    /// TYPES ///

    struct PoolInfo {
        uint256 lastRewardTimestamp;
        // Accumulated Rewards per share, times 1e12. See below.
        uint256 accRewardPerShare;
        uint256 totalAmount;
    }
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    /// CONSTANTS ///

    /// @notice Scalar for math
    uint256 internal constant DENOMINATOR = 10000;
    /// @notice Scalar for math
    uint256 internal constant PRECISION = 1e36;
    address public lendtroller; // Lendtroller linked

    /// STORAGE ///

    // Current child gauges attached to this gauge pool
    ChildGaugePool[] public childGauges;
    mapping(address => PoolInfo) public poolInfo; // token => pool info
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => info

    /// EVENTS ///

    event AddChildGauge(address childGauge);
    event RemoveChildGauge(address childGauge);
    event Deposit(address user, address token, uint256 amount);
    event Withdraw(address user, address token, uint256 amount);
    event Claim(address user, address token, uint256 amount);

    constructor(
        ICentralRegistry centralRegistry_
    ) GaugeController(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Initializes the gauge with a starting time based on the next epoch
    /// @dev    Can only be called once, to start the gauge system
    /// @param lendtroller_ The address to be configured as a lending market
    function start(address lendtroller_) external onlyDaoPermissions {
        if (startTime != 0) {
            revert GaugeErrors.AlreadyStarted();
        }

        // Validate that the lendtroller we are setting is actually a lending market
        if (!centralRegistry.isLendingMarket(lendtroller_)) {
            revert GaugeErrors.InvalidAddress();
        }

        if (
            !ERC165Checker.supportsInterface(
                address(lendtroller_),
                type(ILendtroller).interfaceId
            )
        ) {
            revert GaugeErrors.InvalidAddress();
        }

        startTime = veCVE.nextEpochStartTime();
        lendtroller = lendtroller_;
    }

    /// @notice Adds a new child gauge to the gauge system
    /// @param childGauge The address of the child gauge to be added
    function addChildGauge(address childGauge) external onlyDaoPermissions {
        if (childGauge == address(0)) {
            revert GaugeErrors.InvalidAddress();
        }

        if (ChildGaugePool(childGauge).activationTime() != 0) {
            revert GaugeErrors.InvalidAddress();
        }

        childGauges.push(ChildGaugePool(childGauge));
        ChildGaugePool(childGauge).activate();

        emit AddChildGauge(childGauge);
    }

    /// @notice Removes a child gauge from the gauge system
    /// @param index The index of the child gauge
    /// @param childGauge The address of the child gauge to be removed
    function removeChildGauge(
        uint256 index,
        address childGauge
    ) external onlyDaoPermissions {
        if (childGauge != address(childGauges[index])) {
            revert GaugeErrors.InvalidAddress();
        }

        // If the child gauge is not the last one in the array,
        // copy its data down and then pop
        if (index != (childGauges.length - 1)) {
            childGauges[index] = childGauges[childGauges.length - 1];
        }
        childGauges.pop();

        emit RemoveChildGauge(childGauge);
    }

    function balanceOf(
        address token,
        address user
    ) external view returns (uint256) {
        return userInfo[token][user].amount;
    }

    function totalSupply(address token) external view returns (uint256) {
        return poolInfo[token].totalAmount;
    }

    /// @notice Returns pending rewards of user
    /// @param token Pool token address
    /// @param user User address
    function pendingRewards(
        address token,
        address user
    ) external view returns (uint256) {
        PoolInfo storage _pool = poolInfo[token];
        uint256 accRewardPerShare = _pool.accRewardPerShare;
        uint256 lastRewardTimestamp = _pool.lastRewardTimestamp;
        uint256 totalDeposited = _pool.totalAmount;
        if (lastRewardTimestamp == 0) {
            lastRewardTimestamp = startTime;
        }

        if (block.timestamp > lastRewardTimestamp && totalDeposited != 0) {
            uint256 lastEpoch = epochOfTimestamp(lastRewardTimestamp);
            uint256 currentEpoch = currentEpoch();
            uint256 reward;
            while (lastEpoch < currentEpoch) {
                uint256 endTimestamp = epochEndTime(lastEpoch);

                // update rewards from lastRewardTimestamp to endTimestamp
                reward =
                    ((endTimestamp - lastRewardTimestamp) *
                        epochInfo[lastEpoch].poolWeights[token]) /
                    EPOCH_WINDOW;
                accRewardPerShare =
                    accRewardPerShare +
                    (reward * (PRECISION)) /
                    totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            // update rewards from lastRewardTimestamp to current timestamp
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    epochInfo[lastEpoch].poolWeights[token]) /
                EPOCH_WINDOW;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (PRECISION)) /
                totalDeposited;
        }

        UserInfo memory info = userInfo[token][user];
        return
            info.rewardPending +
            (info.amount * accRewardPerShare) /
            (PRECISION) -
            info.rewardDebt;
    }

    /// @notice Deposit into gauge pool
    /// @param token Pool token address
    /// @param user User address
    /// @param amount Amounts to deposit
    function deposit(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        if (
            msg.sender != token || !ILendtroller(lendtroller).isListed(token)
        ) {
            revert GaugeErrors.InvalidToken();
        }

        updatePool(token);

        _calcPending(user, token);

        userInfo[token][user].amount += amount;
        poolInfo[token].totalAmount += amount;

        _calcDebt(user, token);

        uint256 numChildGauges = childGauges.length;

        for (uint256 i; i < numChildGauges; ) {
            if (address(childGauges[i]) != address(0)) {
                childGauges[i].deposit(token, user, amount);
            }

            unchecked {
                ++i;
            }
        }

        emit Deposit(user, token, amount);
    }

    /// @notice Withdraw from gauge pool
    /// @param token Pool token address
    /// @param user The user address
    /// @param amount Amounts to withdraw
    function withdraw(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        if (
            msg.sender != token || !ILendtroller(lendtroller).isListed(token)
        ) {
            revert GaugeErrors.InvalidToken();
        }

        UserInfo storage info = userInfo[token][user];
        if (info.amount < amount) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(user, token);

        info.amount -= amount;
        poolInfo[token].totalAmount -= amount;

        _calcDebt(user, token);

        uint256 numChildGauges = childGauges.length;

        for (uint256 i; i < numChildGauges; ) {
            if (address(childGauges[i]) != address(0)) {
                childGauges[i].withdraw(token, user, amount);
            }

            unchecked {
                ++i;
            }
        }

        emit Withdraw(user, token, amount);
    }

    /// @notice Claim rewards from gauge pool
    /// @param token Pool token address
    function claim(address token) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }
        SafeTransferLib.safeTransfer(cve, msg.sender, rewards);

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

    /// @notice Claim rewards from gauge pool
    /// @param token Pool token address
    function claimAndExtendLock(
        address token,
        uint256 lockIndex,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        userInfo[token][msg.sender].rewardPending = 0;

        uint256 currentLockBoost = centralRegistry.lockBoostValue();
        // If theres a current lock boost, recognize their bonus rewards
        if (currentLockBoost > 0) {
            uint256 boostedRewards = (rewards * currentLockBoost) /
                DENOMINATOR;
            ICVE(cve).mintLockBoost(boostedRewards - rewards);
            rewards = boostedRewards;
        }

        SafeTransferLib.safeApprove(cve, address(veCVE), rewards);
        veCVE.increaseAmountAndExtendLockFor(
            msg.sender,
            rewards,
            lockIndex,
            continuousLock,
            msg.sender,
            rewardsData,
            params,
            aux
        );

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

    /// @notice Claim rewards from gauge pool
    /// @param token Pool token address
    function claimAndLock(
        address token,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        userInfo[token][msg.sender].rewardPending = 0;

        uint256 currentLockBoost = centralRegistry.lockBoostValue();
        // If theres a current lock boost, recognize their bonus rewards
        if (currentLockBoost > 0) {
            uint256 boostedRewards = (rewards * currentLockBoost) /
                DENOMINATOR;
            ICVE(cve).mintLockBoost(boostedRewards - rewards);
            rewards = boostedRewards;
        }

        SafeTransferLib.safeApprove(cve, address(veCVE), rewards);
        veCVE.lockFor(
            msg.sender,
            rewards,
            continuousLock,
            msg.sender,
            rewardsData,
            params,
            aux
        );

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Update reward variables of the given pool to be up-to-date
    /// @param token Pool token address
    function updatePool(address token) public override {
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        if (lastRewardTimestamp == 0) {
            lastRewardTimestamp = startTime;
        }

        if (
            block.timestamp <= startTime ||
            block.timestamp <= lastRewardTimestamp
        ) {
            return;
        }

        uint256 totalDeposited = poolInfo[token].totalAmount;
        if (totalDeposited == 0) {
            return;
        }

        uint256 accRewardPerShare = poolInfo[token].accRewardPerShare;
        uint256 lastEpoch = epochOfTimestamp(lastRewardTimestamp);
        uint256 currentEpoch = currentEpoch();
        uint256 reward;

        while (lastEpoch < currentEpoch) {
            uint256 endTimestamp = epochEndTime(lastEpoch);

            // update rewards from lastRewardTimestamp to endTimestamp
            reward =
                ((endTimestamp - lastRewardTimestamp) *
                    epochInfo[lastEpoch].poolWeights[token]) /
                EPOCH_WINDOW;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (PRECISION)) /
                totalDeposited;

            ++lastEpoch;
            lastRewardTimestamp = endTimestamp;
        }

        // update rewards from lastRewardTimestamp to current timestamp
        reward =
            ((block.timestamp - lastRewardTimestamp) *
                epochInfo[lastEpoch].poolWeights[token]) /
            EPOCH_WINDOW;
        accRewardPerShare =
            accRewardPerShare +
            (reward * (PRECISION)) /
            totalDeposited;

        // update pool storage
        poolInfo[token].lastRewardTimestamp = block.timestamp;
        poolInfo[token].accRewardPerShare = accRewardPerShare;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Calculate user's pending rewards
    function _calcPending(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardPending +=
            (info.amount * poolInfo[token].accRewardPerShare) /
            (PRECISION) -
            info.rewardDebt;
    }

    /// @notice Calculate user's debt amount for reward calculation
    function _calcDebt(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardDebt =
            (info.amount * poolInfo[token].accRewardPerShare) /
            (PRECISION);
    }
}
