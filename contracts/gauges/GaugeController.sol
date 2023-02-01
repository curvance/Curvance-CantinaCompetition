//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GaugeErrors.sol";

contract GaugeController is Ownable {
    // storage
    address public cve;
    uint256 public rewardPerSec;
    uint256 public totalAllocPoint;
    mapping(address => uint256) public poolAllocPoint; // token => alloc point

    constructor(address _cve) Ownable() {
        cve = _cve;
    }

    function isGaugeEnabled(address token) public view returns (bool) {
        return poolAllocPoint[token] > 0;
    }

    function updateRewardPerSec(uint256 _rewardPerSec) external onlyOwner {
        rewardPerSec = _rewardPerSec;
    }

    function updateEmissionRates(address[] memory tokens, uint256[] memory allocPoints) external onlyOwner {
        if (tokens.length != allocPoints.length) {
            revert GaugeErrors.InvalidLength();
        }

        massUpdatePools(tokens);

        for (uint256 i = 0; i < tokens.length; ++i) {
            totalAllocPoint = totalAllocPoint + allocPoints[i] - poolAllocPoint[tokens[i]];
            poolAllocPoint[tokens[i]] = allocPoints[i];
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
    function updatePool(address token) public virtual {}
}
