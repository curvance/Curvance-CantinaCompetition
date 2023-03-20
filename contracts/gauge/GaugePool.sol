//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GaugeController.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GaugePool is GaugeController, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // structs
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

    // events
    event Deposit(address indexed user, address indexed token, uint256 amount, address indexed onBehalf);
    event Withdraw(address indexed user, address indexed token, uint256 amount, address indexed recipient);
    event Claim(address indexed user, address indexed token, uint256 amount);

    // constants
    uint256 public constant PRECISION = 1e36;

    // storage
    mapping(address => PoolInfo) public poolInfo; // token => pool info
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => info

    constructor(address _cve) GaugeController(_cve) ReentrancyGuard() {}

    /**
     * @notice Returns pending rewards of user
     * @param token Pool token address
     * @param user User address
     */
    function pendingRewards(address token, address user) external view returns (uint256) {
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
                accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            // update rewards from lastRewardTimestamp to current timestamp
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    epochInfo[lastEpoch].rewardPerSec *
                    epochInfo[lastEpoch].poolWeights[token]) /
                epochInfo[lastEpoch].totalWeights;
            accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;
        }

        UserInfo memory info = userInfo[token][user];
        return info.rewardPending + (info.amount * accRewardPerShare) / (PRECISION) - info.rewardDebt;
    }

    /**
     * @notice Deposit into gauge pool
     * @param token Pool token address
     * @param amount Amounts to deposit
     * @param onBehalf User address for behalf
     */
    function deposit(
        address token,
        uint256 amount,
        address onBehalf
    ) external nonReentrant {
        if (!isGaugeEnabled(currentEpoch(), token)) {
            revert GaugeErrors.InvalidToken();
        }
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(onBehalf, token);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        userInfo[token][onBehalf].amount += amount;
        poolInfo[token].totalAmount += amount;

        _calcDebt(onBehalf, token);

        emit Deposit(msg.sender, token, amount, onBehalf);
    }

    /**
     * @notice Withdraw from gauge pool
     * @param token Pool token address
     * @param amount Amounts to withdraw
     * @param recipient The recipient address
     */
    function withdraw(
        address token,
        uint256 amount,
        address recipient
    ) external nonReentrant {
        if (!isGaugeEnabled(currentEpoch(), token)) {
            revert GaugeErrors.InvalidToken();
        }

        UserInfo storage info = userInfo[token][msg.sender];
        if (amount == 0 || info.amount < amount) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        info.amount -= amount;
        poolInfo[token].totalAmount -= amount;
        IERC20(token).safeTransfer(recipient, amount);

        _calcDebt(msg.sender, token);

        emit Withdraw(msg.sender, token, amount, recipient);
    }

    /**
     * @notice Claim rewards from gauge pool
     * @param token Pool token address
     */
    function claim(address token) external nonReentrant {
        if (!isGaugeEnabled(currentEpoch(), token)) {
            revert GaugeErrors.InvalidToken();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }
        IERC20(cve).safeTransfer(msg.sender, rewards);

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

    /**
     * @notice Calculate user's pending rewards
     */
    function _calcPending(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardPending += (info.amount * poolInfo[token].accRewardPerShare) / (PRECISION) - info.rewardDebt;
    }

    /**
     * @notice Calculate user's debt amount for reward calculation
     */
    function _calcDebt(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardDebt = (info.amount * poolInfo[token].accRewardPerShare) / (PRECISION);
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date
     * @param token Pool token address
     */
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
            accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;

            ++lastEpoch;
            lastRewardTimestamp = endTimestamp;
        }

        // update rewards from lastRewardTimestamp to current timestamp
        reward =
            ((block.timestamp - lastRewardTimestamp) *
                epochInfo[lastEpoch].rewardPerSec *
                epochInfo[lastEpoch].poolWeights[token]) /
            epochInfo[lastEpoch].totalWeights;
        accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;

        // update pool storage
        poolInfo[token].lastRewardTimestamp = block.timestamp;
        poolInfo[token].accRewardPerShare = accRewardPerShare;
    }
}
