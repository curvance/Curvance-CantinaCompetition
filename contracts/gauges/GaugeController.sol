//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GaugeErrors.sol";

contract GaugeController is Ownable {
    // structs
    struct PoolInfo {
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare; // Accumulated Rewards per share, times 1e12. See below.
    }

    // storage
    address public cve;
    uint256 public rewardPerBlock;
    uint256 public totalAllocPoint;
    mapping(address => PoolInfo) public poolInfo;

    constructor(address _cve) Ownable() {
        cve = _cve;
    }

    function isGaugeEnabled(address token) public view returns (bool) {
        return poolInfo[token].allocPoint > 0;
    }

    function updateEmissionRates(address[] memory tokens, uint256[] memory allocPoints) external onlyOwner {
        if (tokens.length != allocPoints.length) {
            revert GaugeErrors.InvalidLength();
        }

        massUpdatePools(tokens);

        for (uint256 i = 0; i < tokens.length; ++i) {
            totalAllocPoint = totalAllocPoint + allocPoints[i] - poolInfo[tokens[i]].allocPoint;
            poolInfo[tokens[i]].allocPoint = allocPoints[i];
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools(address[] memory tokens) public {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            updatePool(tokens[i]);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(address token) public {
        PoolInfo storage pool = poolInfo[token];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 totalDeposited = IERC20(token).balanceOf(address(this));
        if (totalDeposited == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 reward = ((block.number - pool.lastRewardBlock) * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
        pool.accRewardPerShare = pool.accRewardPerShare + (reward * (1e12)) / totalDeposited;
        pool.lastRewardBlock = block.number;
    }
}
