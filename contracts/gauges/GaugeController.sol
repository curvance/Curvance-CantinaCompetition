//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GaugeErrors.sol";

contract GaugeController is Ownable {
    // structs
    struct Epoch {
        uint256 rewardPerSec;
        uint256 totalAllocPoint;
        mapping(address => uint256) poolAllocPoint; // token => alloc point
    }

    uint256 public constant EPOCH_WINDOW = 4 weeks;

    // storage
    address public cve;

    uint256 public startTime;
    mapping(uint256 => Epoch) internal epochInfo;

    constructor(address _cve) Ownable() {
        cve = _cve;
    }

    function start() external onlyOwner {
        if (startTime != 0) {
            revert GaugeErrors.AlreadyStarted();
        }

        startTime = 0;
    }

    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - startTime) / EPOCH_WINDOW;
    }

    function epochOfTimestamp(uint256 timestamp) public pure returns (uint256) {
        return timestamp / EPOCH_WINDOW;
    }

    function epochStartTime(uint256 epoch) public view returns (uint256) {
        return startTime + epoch * EPOCH_WINDOW;
    }

    function epochEndTime(uint256 epoch) public view returns (uint256) {
        return startTime + (epoch + 1) * EPOCH_WINDOW;
    }

    function isGaugeEnabled(address token) public view returns (bool) {
        return isGaugeEnabled(currentEpoch(), token);
    }

    function isGaugeEnabled(uint256 epoch, address token) public view returns (bool) {
        return epochInfo[epoch].poolAllocPoint[token] > 0;
    }

    function setRewardPerSecOfNextEpoch(uint256 epoch, uint256 _rewardPerSec) external onlyOwner {
        if (epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        epochInfo[epoch].rewardPerSec = _rewardPerSec;
    }

    function updateEmissionRates(
        uint256 epoch,
        address[] memory tokens,
        uint256[] memory allocPoints
    ) external onlyOwner {
        if (epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        if (tokens.length != allocPoints.length) {
            revert GaugeErrors.InvalidLength();
        }

        Epoch storage info = epochInfo[epoch];
        for (uint256 i = 0; i < tokens.length; ++i) {
            info.totalAllocPoint = info.totalAllocPoint + allocPoints[i] - info.poolAllocPoint[tokens[i]];
            info.poolAllocPoint[tokens[i]] = allocPoints[i];
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
