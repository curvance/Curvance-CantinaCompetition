//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GaugeController.sol";
import "./ChildGaugePool.sol";
import "../compound/Comptroller/ComptrollerInterface.sol";

import "@openzeppelin/contracts/interfaces/IERC20.sol";
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
    event AddChildGauge(address indexed childGauge);
    event RemoveChildGauge(address indexed childGauge);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Claim(address indexed user, address indexed token, uint256 amount);

    // constants
    uint256 public constant PRECISION = 1e36;

    // storage
    address public comptroller;
    ChildGaugePool[] public childGauges;
    mapping(address => PoolInfo) public poolInfo; // token => pool info
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => info

    constructor(address _cve, address _ve, address _comptroller) GaugeController(_cve, _ve) ReentrancyGuard() {
        comptroller = _comptroller;
    }

    function addChildGauge(address _childGauge) external onlyOwner {
        if (_childGauge == address(0)) {
            revert GaugeErrors.InvalidAddress();
        }
        childGauges.push(ChildGaugePool(_childGauge));

        ChildGaugePool(_childGauge).activate();

        emit AddChildGauge(_childGauge);
    }

    function removeChildGauge(uint256 _index, address _childGauge) external onlyOwner {
        if (_childGauge != address(childGauges[_index])) {
            revert GaugeErrors.InvalidAddress();
        }
        childGauges[_index] = ChildGaugePool(address(0));

        emit RemoveChildGauge(_childGauge);
    }

    function balanceOf(address token, address user) external view returns (uint256) {
        return userInfo[token][user].amount;
    }

    function totalSupply(address token) external view returns (uint256) {
        return poolInfo[token].totalAmount;
    }

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
     * @param user User address
     * @param amount Amounts to deposit
     */
    function deposit(address token, address user, uint256 amount) external nonReentrant {
        (bool isListed, , ) = ComptrollerInterface(comptroller).getIsMarkets(token);
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

        for (uint256 i = 0; i < childGauges.length; ++i) {
            if (address(childGauges[i]) != address(0)) {
                childGauges[i].deposit(token, user, amount);
            }
        }

        emit Deposit(user, token, amount);
    }

    /**
     * @notice Withdraw from gauge pool
     * @param token Pool token address
     * @param user The user address
     * @param amount Amounts to withdraw
     */
    function withdraw(address token, address user, uint256 amount) external nonReentrant {
        (bool isListed, , ) = ComptrollerInterface(comptroller).getIsMarkets(token);
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

        for (uint256 i = 0; i < childGauges.length; ++i) {
            if (address(childGauges[i]) != address(0)) {
                childGauges[i].withdraw(token, user, amount);
            }
        }

        emit Withdraw(user, token, amount);
    }

    /**
     * @notice Claim rewards from gauge pool
     * @param token Pool token address
     */
    function claim(address token) external nonReentrant {
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
     * @notice Claim rewards from gauge pool
     * @param token Pool token address
     */
    function claimAndExtendLock(address token, uint256 lockIndex, bool continuousLock) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        IERC20(cve).safeApprove(address(ve), rewards);
        ve.increaseAmountAndExtendLockFor(msg.sender, rewards, lockIndex, continuousLock);

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token, rewards);
    }

    /**
     * @notice Claim rewards from gauge pool
     * @param token Pool token address
     */
    function claimAndLock(address token, bool continuousLock) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        IERC20(cve).safeApprove(address(ve), rewards);
        ve.lockFor(msg.sender, uint216(rewards), continuousLock);

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
