//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { GaugeErrors } from "./GaugeErrors.sol";
import { GaugePool } from "./GaugePool.sol";

contract ChildGaugePool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // structs
    struct PoolInfo {
        uint256 lastRewardTimestamp;
        uint256 accRewardPerShare; // Accumulated Rewards per share, times 1e12. See below.
        uint256 totalAmount;
    }
    struct UserInfo {
        uint256 rewardDebt;
        uint256 rewardPending;
    }
    enum UserAction {
        DEPOSIT,
        WITHDRAW,
        CLAIM
    }

    // events

    // constants
    uint256 public constant EPOCH_WINDOW = 4 weeks;
    uint256 public constant PRECISION = 1e36;

    // storage
    uint256 public activationTime;
    GaugePool public gaugeController;
    address public rewardToken;
    mapping(uint256 => uint256) public epochRewardPerSec; // epoch => rewardPerSec
    mapping(address => PoolInfo) public poolInfo; // token => pool info
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => info

    modifier onlyGaugeController() {
        if (msg.sender != address(gaugeController)) {
            revert GaugeErrors.Unauthorized();
        }
        _;
    }

    constructor(address _gaugeController, address _rewardToken) Ownable() {
        gaugeController = GaugePool(_gaugeController);
        rewardToken = _rewardToken;
    }

    function activate() external onlyGaugeController {
        activationTime = block.timestamp;
    }

    function setRewardPerSec(uint256 epoch, uint256 newRewardPerSec) external onlyOwner {
        if (!(epoch == 0 && startTime() == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 prevRewardPerSec = epochRewardPerSec[epoch];
        epochRewardPerSec[epoch] = newRewardPerSec;

        if (prevRewardPerSec > newRewardPerSec) {
            IERC20(rewardToken).safeTransfer(msg.sender, EPOCH_WINDOW * (prevRewardPerSec - newRewardPerSec));
        } else {
            IERC20(rewardToken).safeTransferFrom(
                msg.sender,
                address(this),
                EPOCH_WINDOW * (newRewardPerSec - prevRewardPerSec)
            );
        }
    }

    function startTime() public view returns (uint256) {
        return gaugeController.startTime();
    }

    function currentEpoch() public view returns (uint256) {
        return gaugeController.currentEpoch();
    }

    /**
     * @notice Returns pending rewards of user
     * @param token Pool token address
     * @param user User address
     */
    function pendingRewards(address token, address user) external view returns (uint256) {
        if (!gaugeController.isGaugeEnabled(gaugeController.currentEpoch(), token)) {
            revert GaugeErrors.InvalidToken();
        }

        uint256 accRewardPerShare = poolInfo[token].accRewardPerShare;
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        uint256 totalDeposited = gaugeController.totalSupply(token);

        if (lastRewardTimestamp == 0) {
            lastRewardTimestamp = activationTime;
        }

        if (block.timestamp > lastRewardTimestamp && totalDeposited != 0) {
            uint256 lastEpoch = gaugeController.epochOfTimestamp(lastRewardTimestamp);
            uint256 curEpoch = gaugeController.currentEpoch();
            uint256 reward;
            while (lastEpoch < curEpoch) {
                uint256 endTimestamp = gaugeController.epochEndTime(lastEpoch);

                (uint256 totalWeights, uint256 poolWeights) = gaugeController.gaugeWeight(lastEpoch, token);
                // update rewards from lastRewardTimestamp to endTimestamp
                reward =
                    ((endTimestamp - lastRewardTimestamp) * epochRewardPerSec[lastEpoch] * poolWeights) /
                    totalWeights;
                accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            (uint256 totalWeightsOfCurrentEpoch, uint256 poolWeightsOfCurrentEpoch) = gaugeController.gaugeWeight(
                lastEpoch,
                token
            );
            // update rewards from lastRewardTimestamp to current timestamp
            reward =
                ((block.timestamp - lastRewardTimestamp) * epochRewardPerSec[lastEpoch] * poolWeightsOfCurrentEpoch) /
                totalWeightsOfCurrentEpoch;
            accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;
        }

        UserInfo memory info = userInfo[token][user];
        return
            info.rewardPending +
            (gaugeController.balanceOf(token, user) * accRewardPerShare) /
            (PRECISION) -
            info.rewardDebt;
    }

    function deposit(address token, address user, uint256 amount) external nonReentrant onlyGaugeController {
        _updatePool(token, UserAction.DEPOSIT, amount);

        _calcPending(user, token, UserAction.DEPOSIT, amount);

        _calcDebt(user, token);
    }

    function withdraw(address token, address user, uint256 amount) external nonReentrant onlyGaugeController {
        _updatePool(token, UserAction.WITHDRAW, amount);

        _calcPending(user, token, UserAction.WITHDRAW, amount);

        _calcDebt(user, token);
    }

    function claim(address token) external nonReentrant {
        _updatePool(token, UserAction.CLAIM, 0);

        _calcPending(msg.sender, token, UserAction.CLAIM, 0);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }
        IERC20(rewardToken).safeTransfer(msg.sender, rewards);

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);
    }

    /**
     * @notice Calculate user's pending rewards
     */
    function _calcPending(address user, address token, UserAction action, uint256 amount) internal {
        uint256 userAmount = gaugeController.balanceOf(token, user);
        if (action == UserAction.DEPOSIT) {
            userAmount -= amount;
        } else if (action == UserAction.WITHDRAW) {
            userAmount += amount;
        }

        UserInfo storage info = userInfo[token][user];
        info.rewardPending += (userAmount * poolInfo[token].accRewardPerShare) / (PRECISION) - info.rewardDebt;
    }

    /**
     * @notice Calculate user's debt amount for reward calculation
     */
    function _calcDebt(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardDebt = (gaugeController.balanceOf(token, user) * poolInfo[token].accRewardPerShare) / (PRECISION);
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date
     * @param token Pool token address
     */
    function _updatePool(address token, UserAction action, uint256 amount) internal {
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        if (lastRewardTimestamp == 0) {
            poolInfo[token].lastRewardTimestamp = activationTime;
            lastRewardTimestamp = activationTime;
        }

        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 totalDeposited = gaugeController.totalSupply(token);
        if (action == UserAction.DEPOSIT) {
            totalDeposited -= amount;
        } else if (action == UserAction.WITHDRAW) {
            totalDeposited += amount;
        }

        if (totalDeposited == 0) {
            poolInfo[token].lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 accRewardPerShare = poolInfo[token].accRewardPerShare;
        uint256 lastEpoch = gaugeController.epochOfTimestamp(lastRewardTimestamp);
        uint256 curEpoch = gaugeController.currentEpoch();
        uint256 reward;
        while (lastEpoch < curEpoch) {
            uint256 endTimestamp = gaugeController.epochEndTime(lastEpoch);

            (uint256 totalWeights, uint256 poolWeights) = gaugeController.gaugeWeight(lastEpoch, token);

            // update rewards from lastRewardTimestamp to endTimestamp
            reward = ((endTimestamp - lastRewardTimestamp) * epochRewardPerSec[lastEpoch] * poolWeights) / totalWeights;
            accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;

            ++lastEpoch;
            lastRewardTimestamp = endTimestamp;
        }

        (uint256 totalWeightsOfCurrentEpoch, uint256 poolWeightsOfCurrentEpoch) = gaugeController.gaugeWeight(
            lastEpoch,
            token
        );
        // update rewards from lastRewardTimestamp to current timestamp
        reward =
            ((block.timestamp - lastRewardTimestamp) * epochRewardPerSec[lastEpoch] * poolWeightsOfCurrentEpoch) /
            totalWeightsOfCurrentEpoch;
        accRewardPerShare = accRewardPerShare + (reward * (PRECISION)) / totalDeposited;

        // update pool storage
        poolInfo[token].lastRewardTimestamp = block.timestamp;
        poolInfo[token].accRewardPerShare = accRewardPerShare;
    }
}
