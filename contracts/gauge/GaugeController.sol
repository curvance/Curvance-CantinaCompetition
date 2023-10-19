// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";

abstract contract GaugeController is IGaugePool {
    /// TYPES ///

    struct Epoch {
        uint256 totalWeights;
        mapping(address => uint256) poolWeights; // token => weight
    }

    /// CONSTANTS ///

    uint256 public constant EPOCH_WINDOW = 2 weeks; // Protocol epoch length
    address public immutable cve; // CVE contract address
    IVeCVE public immutable veCVE; // veCVE contract address
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///

    uint256 public startTime; // Gauge emission start time
    mapping(uint256 => Epoch) internal epochInfo;

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "GaugeController: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyMessagingHub() {
        require(
            msg.sender == centralRegistry.protocolMessagingHub(),
            "GaugeController: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert GaugeErrors.InvalidAddress();
        }
        centralRegistry = centralRegistry_;
        cve = centralRegistry.CVE();
        veCVE = IVeCVE(centralRegistry.veCVE());
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Returns gauge weight of given epoch and token
    /// @param epoch Epoch number
    /// @param token Gauge token address
    function gaugeWeight(
        uint256 epoch,
        address token
    ) external view returns (uint256, uint256) {
        return (
            epochInfo[epoch].totalWeights,
            epochInfo[epoch].poolWeights[token]
        );
    }

    /// @notice Set emission rates of tokens of next epoch
    /// @dev Only the protocol messaging hub can call this
    /// @param epoch Next epoch number
    /// @param tokens Token address array
    /// @param poolWeights Gauge weights (or gauge weights)
    function setEmissionRates(
        uint256 epoch,
        address[] calldata tokens,
        uint256[] calldata poolWeights
    ) external override onlyMessagingHub {
        if (!(epoch == 0 && startTime == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 numTokens = tokens.length;

        if (numTokens != poolWeights.length) {
            revert GaugeErrors.InvalidLength();
        }

        Epoch storage info = epochInfo[epoch];
        for (uint256 i; i < numTokens; ) {
            for (uint256 j; j < numTokens; ) {
                if (i != j && tokens[i] == tokens[j]) {
                    revert GaugeErrors.InvalidToken();
                }

                unchecked {
                    ++j;
                }
            }

            info.totalWeights =
                info.totalWeights +
                poolWeights[i] -
                info.poolWeights[tokens[i]];
            info.poolWeights[tokens[i]] = poolWeights[i];

            unchecked {
                ++i;
            }
        }
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Returns current epoch number
    function currentEpoch() public view returns (uint256) {
        return epochOfTimestamp(block.timestamp);
    }

    /// @notice Returns epoch number of given timestamp
    /// @param timestamp Timestamp in seconds
    function epochOfTimestamp(
        uint256 timestamp
    ) public view returns (uint256) {
        require(startTime != 0, "GaugeController: gauge not started");
        if (timestamp <= startTime) {
            return 0;
        }
        return (timestamp - startTime) / EPOCH_WINDOW;
    }

    /// @notice Returns start time of given epoch
    /// @param epoch Epoch number
    function epochStartTime(uint256 epoch) public view returns (uint256) {
        require(startTime != 0, "GaugeController: gauge not started");
        return startTime + epoch * EPOCH_WINDOW;
    }

    /// @notice Returns end time of given epoch
    /// @param epoch Epoch number
    function epochEndTime(uint256 epoch) public view returns (uint256) {
        require(startTime != 0, "GaugeController: gauge not started");
        return startTime + (epoch + 1) * EPOCH_WINDOW;
    }

    /// @notice Returns if given gauge token is enabled in given epoch
    /// @param epoch Epoch number
    /// @param token Gauge token address
    function isGaugeEnabled(
        uint256 epoch,
        address token
    ) public view returns (bool) {
        return epochInfo[epoch].poolWeights[token] > 0;
    }

    /// @notice Update reward variables for all pools
    /// @dev Be careful of gas spending!
    function massUpdatePools(address[] calldata tokens) external {
        uint256 numTokens = tokens.length;
        for (uint256 i; i < numTokens; ) {
            unchecked {
                updatePool(tokens[i++]);
            }
        }
    }

    /// @notice Update reward variables of the given pool to be up-to-date
    /// @param token Pool token address
    function updatePool(address token) public virtual {}
}
