//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./GaugeErrors.sol";
import "../interfaces/IGaugePool.sol";

contract GaugeController is IGaugePool, Ownable {
    using SafeERC20 for IERC20;

    // structs
    struct Epoch {
        uint256 rewardPerSec;
        uint256 totalWeights;
        mapping(address => uint256) poolWeights; // token => weight
    }

    uint256 public constant EPOCH_WINDOW = 4 weeks;

    // storage
    address public cve;

    uint256 public startTime;
    mapping(uint256 => Epoch) internal epochInfo;

    constructor(address _cve) Ownable() {
        cve = _cve;
    }

    /**
     * @notice Start gauge system
     * @dev Only owner
     */
    function start() external onlyOwner {
        if (startTime != 0) {
            revert GaugeErrors.AlreadyStarted();
        }

        startTime = block.timestamp;
    }

    /**
     * @notice Returns current epoch number
     */
    function currentEpoch() public view returns (uint256) {
        assert(startTime != 0);
        return (block.timestamp - startTime) / EPOCH_WINDOW;
    }

    /**
     * @notice Returns epoch number of given timestamp
     * @param timestamp Timestamp in seconds
     */
    function epochOfTimestamp(uint256 timestamp) public view returns (uint256) {
        assert(startTime != 0);
        return (timestamp - startTime) / EPOCH_WINDOW;
    }

    /**
     * @notice Returns start time of given epoch
     * @param epoch Epoch number
     */
    function epochStartTime(uint256 epoch) public view returns (uint256) {
        assert(startTime != 0);
        return startTime + epoch * EPOCH_WINDOW;
    }

    /**
     * @notice Returns end time of given epoch
     * @param epoch Epoch number
     */
    function epochEndTime(uint256 epoch) public view returns (uint256) {
        assert(startTime != 0);
        return startTime + (epoch + 1) * EPOCH_WINDOW;
    }

    /**
     * @notice Returns reward per second of given epoch
     * @param epoch Epoch number
     */
    function rewardPerSec(uint256 epoch) external view returns (uint256) {
        return epochInfo[epoch].rewardPerSec;
    }

    /**
     * @notice Returns gauge weight of given epoch and token
     * @param epoch Epoch number
     * @param token Gauge token address
     */
    function gaugeWeight(uint256 epoch, address token) external view returns (uint256, uint256) {
        return (epochInfo[epoch].totalWeights, epochInfo[epoch].poolWeights[token]);
    }

    /**
     * @notice Returns if given gauge token is enabled in given epoch
     * @param epoch Epoch number
     * @param token Gauge token address
     */
    function isGaugeEnabled(uint256 epoch, address token) public view returns (bool) {
        return epochInfo[epoch].poolWeights[token] > 0;
    }

    /**
     * @notice Set rewardPerSec of next epoch
     * @dev Only owner
     * @param epoch Next epoch number
     * @param newRewardPerSec Reward per second
     */
    function setRewardPerSecOfNextEpoch(uint256 epoch, uint256 newRewardPerSec) external override onlyOwner {
        if (!(epoch == 0 && startTime == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 prevRewardPerSec = epochInfo[epoch].rewardPerSec;
        epochInfo[epoch].rewardPerSec = newRewardPerSec;

        if (prevRewardPerSec > newRewardPerSec) {
            IERC20(cve).safeTransfer(msg.sender, EPOCH_WINDOW * (prevRewardPerSec - newRewardPerSec));
        } else {
            IERC20(cve).safeTransferFrom(
                msg.sender,
                address(this),
                EPOCH_WINDOW * (newRewardPerSec - prevRewardPerSec)
            );
        }
    }

    /**
     * @notice Set emission rates of tokens of next epoch
     * @dev Only owner
     * @param epoch Next epoch number
     * @param tokens Token address array
     * @param poolWeights Gauge weights (or gauge weights)
     */
    function setEmissionRates(
        uint256 epoch,
        address[] memory tokens,
        uint256[] memory poolWeights
    ) external override onlyOwner {
        if (!(epoch == 0 && startTime == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        if (tokens.length != poolWeights.length) {
            revert GaugeErrors.InvalidLength();
        }

        Epoch storage info = epochInfo[epoch];
        for (uint256 i = 0; i < tokens.length; ++i) {
            info.totalWeights = info.totalWeights + poolWeights[i] - info.poolWeights[tokens[i]];
            info.poolWeights[tokens[i]] = poolWeights[i];
        }
    }

    /**
     * @notice Update reward variables for all pools
     * @dev Be careful of gas spending!
     */
    function massUpdatePools(address[] memory tokens) public {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            updatePool(tokens[i]);
        }
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date
     * @param token Pool token address
     */
    function updatePool(address token) public virtual {}
}
