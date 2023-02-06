//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GaugeController.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GuagePool is GaugeController, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // structs
    struct PoolInfo {
        uint256 lastRewardTimestamp;
        uint256 accRewardPerShare; // Accumulated Rewards per share, times 1e12. See below.
    }
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    // events
    event Deposit(address indexed user, address indexed token, uint256 amount, address indexed onBehalf);
    event Withdraw(address indexed user, address indexed token, uint256 amount, address indexed recipient);
    event Claim(address indexed user, address indexed token, uint256 amount);

    // storage
    mapping(address => PoolInfo) public poolInfo; // token => pool info
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => info

    constructor(address _cve) GaugeController(_cve) ReentrancyGuard() {}

    function pendingRewards(address token, address user) external view returns (uint256) {
        uint256 accRewardPerShare = poolInfo[token].accRewardPerShare;
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        uint256 totalDeposited = IERC20(token).balanceOf(address(this));

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
                        epochInfo[lastEpoch].poolAllocPoint[token]) /
                    epochInfo[lastEpoch].totalAllocPoint;
                accRewardPerShare = accRewardPerShare + (reward * (1e12)) / totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            // update rewards from lastRewardTimestamp to current timestamp
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    epochInfo[lastEpoch].rewardPerSec *
                    epochInfo[lastEpoch].poolAllocPoint[token]) /
                epochInfo[lastEpoch].totalAllocPoint;
            accRewardPerShare = accRewardPerShare + (reward * (1e12)) / totalDeposited;
        }

        UserInfo memory info = userInfo[token][user];
        return (info.amount * accRewardPerShare) / (1e12) - info.rewardDebt;
    }

    function deposit(
        address token,
        uint256 amount,
        address onBehalf
    ) external nonReentrant {
        if (!isGaugeEnabled(token)) {
            revert GaugeErrors.InvalidToken();
        }
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(onBehalf, token);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        userInfo[token][onBehalf].amount += amount;

        _calcDebt(onBehalf, token);

        emit Deposit(msg.sender, token, amount, onBehalf);
    }

    function withdraw(
        address token,
        uint256 amount,
        address recipient
    ) external nonReentrant {
        if (!isGaugeEnabled(token)) {
            revert GaugeErrors.InvalidToken();
        }

        UserInfo storage info = userInfo[token][msg.sender];
        if (amount == 0 || info.amount < amount) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        info.amount -= amount;
        IERC20(token).safeTransfer(recipient, amount);

        _calcDebt(msg.sender, token);

        emit Withdraw(msg.sender, token, amount, recipient);
    }

    function claim(address token) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoRewards();
        }
        IERC20(cve).safeTransfer(msg.sender, rewards);

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

    function _calcPending(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardPending += (info.amount * poolInfo[token].accRewardPerShare) / (1e12) - info.rewardDebt;
    }

    function _calcDebt(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardDebt = (info.amount * poolInfo[token].accRewardPerShare) / (1e12);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(address token) public override {
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 totalDeposited = IERC20(token).balanceOf(address(this));
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
                    epochInfo[lastEpoch].poolAllocPoint[token]) /
                epochInfo[lastEpoch].totalAllocPoint;
            accRewardPerShare = accRewardPerShare + (reward * (1e12)) / totalDeposited;

            ++lastEpoch;
            lastRewardTimestamp = endTimestamp;
        }

        // update rewards from lastRewardTimestamp to current timestamp
        reward =
            ((block.timestamp - lastRewardTimestamp) *
                epochInfo[lastEpoch].rewardPerSec *
                epochInfo[lastEpoch].poolAllocPoint[token]) /
            epochInfo[lastEpoch].totalAllocPoint;
        accRewardPerShare = accRewardPerShare + (reward * (1e12)) / totalDeposited;

        // update pool storage
        poolInfo[token].lastRewardTimestamp = lastRewardTimestamp;
        poolInfo[token].accRewardPerShare = accRewardPerShare;
    }
}
