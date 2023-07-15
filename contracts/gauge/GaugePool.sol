// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICveLocker, rewardsData } from "contracts/interfaces/ICveLocker.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";

import "./GaugeController.sol";
import "./ChildGaugePool.sol";

contract GaugePool is GaugeController, ReentrancyGuard {

    /// structs
    struct PoolInfo {
        uint256 lastRewardTimestamp;
        uint256 accRewardPerShare; // Accumulated Rewards per share, times 1e12. See below.
        uint256 totalAmount;
    }
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    /// events
    event AddChildGauge(address indexed childGauge);
    event RemoveChildGauge(address indexed childGauge);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Claim(address indexed user, address indexed token, uint256 amount);

    /// constants
    uint256 public constant PRECISION = 1e36;

    /// storage
    address public lendtroller;
    ChildGaugePool[] public childGauges;
    mapping(address => PoolInfo) public poolInfo; // token => pool info
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => info

    constructor(
        ICentralRegistry _centralRegistry,
        address _lendtroller
    ) GaugeController(_centralRegistry) ReentrancyGuard() {
        lendtroller = _lendtroller;
    }

    function addChildGauge(address _childGauge) external onlyDaoPermissions {
        if (_childGauge == address(0)) {
            revert GaugeErrors.InvalidAddress();
        }
        childGauges.push(ChildGaugePool(_childGauge));

        ChildGaugePool(_childGauge).activate();

        emit AddChildGauge(_childGauge);
    }

    function removeChildGauge(
        uint256 _index,
        address _childGauge
    ) external onlyDaoPermissions {
        if (_childGauge != address(childGauges[_index])) {
            revert GaugeErrors.InvalidAddress();
        }
        childGauges[_index] = ChildGaugePool(address(0));

        emit RemoveChildGauge(_childGauge);
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
        if (!isGaugeEnabled(currentEpoch(), token)) {
            revert GaugeErrors.InvalidToken();
        }

        uint256 accRewardPerShare = poolInfo[token].accRewardPerShare;
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        uint256 totalDeposited = poolInfo[token].totalAmount;

        if (block.timestamp > lastRewardTimestamp && totalDeposited != 0) {
            uint256 lastEpoch = epochOfTimestamp(lastRewardTimestamp);
            uint256 currentEpoch = currentEpoch();
            uint256 reward;
            while (lastEpoch < currentEpoch) {
                uint256 endTimestamp = epochEndTime(lastEpoch);

                // update rewards from lastRewardTimestamp to endTimestamp
                reward =
                    ((endTimestamp - lastRewardTimestamp) *
                        epochInfo[lastEpoch].rewardPerSec *
                        epochInfo[lastEpoch].poolWeights[token]) /
                    epochInfo[lastEpoch].totalWeights;
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
                    epochInfo[lastEpoch].rewardPerSec *
                    epochInfo[lastEpoch].poolWeights[token]) /
                epochInfo[lastEpoch].totalWeights;
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
        (bool isListed, , ) = ILendtroller(lendtroller).getIsMarkets(token);
        if (msg.sender != token || !isListed) {
            revert GaugeErrors.InvalidToken();
        }
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(user, token);

        userInfo[token][user].amount += amount;
        poolInfo[token].totalAmount += amount;

        _calcDebt(user, token);

        uint256 numChildGauges = childGauges.length;

        for (uint256 i = 0; i < numChildGauges; ++i) {
            if (address(childGauges[i]) != address(0)) {
                childGauges[i].deposit(token, user, amount);
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
        (bool isListed, , ) = ILendtroller(lendtroller).getIsMarkets(token);
        if (msg.sender != token || !isListed) {
            revert GaugeErrors.InvalidToken();
        }

        UserInfo storage info = userInfo[token][user];
        if (amount == 0 || info.amount < amount) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(user, token);

        info.amount -= amount;
        poolInfo[token].totalAmount -= amount;

        _calcDebt(user, token);

        uint256 numChildGauges = childGauges.length;

        for (uint256 i = 0; i < numChildGauges; ++i) {
            if (address(childGauges[i]) != address(0)) {
                childGauges[i].withdraw(token, user, amount);
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
        rewardsData memory _rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        SafeTransferLib.safeApprove(cve, address(veCVE), rewards);
        veCVE.increaseAmountAndExtendLockFor(
            msg.sender,
            rewards,
            lockIndex,
            continuousLock,
            msg.sender,
            _rewardsData,
            params,
            aux
        );

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

    /// @notice Claim rewards from gauge pool
    /// @param token Pool token address
    function claimAndLock(
        address token,
        bool continuousLock,
        rewardsData memory _rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        SafeTransferLib.safeApprove(cve, address(veCVE), rewards);
        veCVE.lockFor(
            msg.sender,
            rewards,
            continuousLock,
            msg.sender,
            _rewardsData,
            params,
            aux
        );

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

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

    /// @notice Update reward variables of the given pool to be up-to-date
    /// @param token Pool token address
    function updatePool(address token) public override {
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 totalDeposited = poolInfo[token].totalAmount;
        if (totalDeposited == 0) {
            poolInfo[token].lastRewardTimestamp = block.timestamp;
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
                    epochInfo[lastEpoch].rewardPerSec *
                    epochInfo[lastEpoch].poolWeights[token]) /
                epochInfo[lastEpoch].totalWeights;
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
                epochInfo[lastEpoch].rewardPerSec *
                epochInfo[lastEpoch].poolWeights[token]) /
            epochInfo[lastEpoch].totalWeights;
        accRewardPerShare =
            accRewardPerShare +
            (reward * (PRECISION)) /
            totalDeposited;

        // update pool storage
        poolInfo[token].lastRewardTimestamp = block.timestamp;
        poolInfo[token].accRewardPerShare = accRewardPerShare;
    }
}
