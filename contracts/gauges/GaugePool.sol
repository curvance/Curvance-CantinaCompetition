//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GaugeController.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GuagePool is GaugeController, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // structs
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    // storage
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => info

    constructor(address _cve) GaugeController(_cve) ReentrancyGuard() {}

    function pendingRewards(address token, address user) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[token];
        UserInfo memory info = userInfo[token][user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 totalDeposited = IERC20(token).balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && totalDeposited != 0) {
            uint256 reward = ((block.number - pool.lastRewardBlock) * rewardPerBlock * pool.allocPoint) /
                totalAllocPoint;
            accRewardPerShare = accRewardPerShare + (reward * (1e12)) / totalDeposited;
        }
        return (info.amount * accRewardPerShare) / (1e12) - info.rewardDebt;
    }

    function deposit(
        address token,
        uint256 amount,
        address onBehalf
    ) external nonReentrant {
        updatePool(token);
        _calcPending(onBehalf, token);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        userInfo[token][onBehalf].amount += amount;

        _calcDebt(onBehalf, token);
    }

    function withdraw(
        address token,
        uint256 amount,
        address recipient
    ) external nonReentrant {

        UserInfo storage info = userInfo[token][msg.sender];

        updatePool(token);
        _calcPending(msg.sender, token);

        info.amount -= amount;
        IERC20(token).safeTransfer(recipient, amount);

        _calcDebt(msg.sender, token);
    }

    function claim(address token) external nonReentrant {
        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        IERC20(cve).safeTransfer(msg.sender, rewards);

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);
    }

    function _calcPending(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardPending += (info.amount * poolInfo[token].accRewardPerShare) / (1e12) - info.rewardDebt;
    }

    function _calcDebt(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardDebt = (info.amount * poolInfo[token].accRewardPerShare) / (1e12);
    }
}
