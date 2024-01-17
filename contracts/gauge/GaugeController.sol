// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";

abstract contract GaugeController is IGaugePool {
    /// TYPES ///

    struct Epoch {
        uint256 totalWeights;
        /// @notice token => weight
        mapping(address => uint256) poolWeights;
    }

    /// CONSTANTS ///

    /// @notice Protocol epoch length.
    uint256 public constant EPOCH_WINDOW = 2 weeks;

    /// @notice CVE contract address.
    address public immutable cve;
    /// @notice VeCVE contract address.
    IVeCVE public immutable veCVE;
    /// @notice Curvance DAO Hub.
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Start time that gauge controller starts, in unix time.
    uint256 public startTime;

    mapping(uint256 => Epoch) internal _epochInfo;

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
        cve = centralRegistry.cve();
        veCVE = IVeCVE(centralRegistry.veCVE());
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Returns gauge weight of given epoch and token.
    /// @param epoch Epoch number.
    /// @param token Gauge token address.
    function gaugeWeight(
        uint256 epoch,
        address token
    ) external view returns (uint256, uint256) {
        return (
            _epochInfo[epoch].totalWeights,
            _epochInfo[epoch].poolWeights[token]
        );
    }

    /// @notice Set emission rates of tokens of next epoch.
    /// @dev Only the protocol messaging hub can call this.
    /// @param epoch Next epoch number.
    /// @param tokens Array containing all tokens to set emission rates for.
    /// @param poolWeights Gauge weights (or gauge weights).
    function setEmissionRates(
        uint256 epoch,
        address[] calldata tokens,
        uint256[] calldata poolWeights
    ) external override {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            revert GaugeErrors.Unauthorized();
        }

        if (
            !(epoch == 0 && (startTime == 0 || block.timestamp < startTime)) &&
            epoch != currentEpoch() + 1
        ) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 numTokens = tokens.length;

        if (numTokens != poolWeights.length) {
            revert GaugeErrors.InvalidLength();
        }

        Epoch storage info = _epochInfo[epoch];
        address priorAddress;
        for (uint256 i; i < numTokens; ) {
            /// We sort the token addresses offchain
            /// from smallest to largest to validate there are no duplicates.
            if (priorAddress > tokens[i]) {
                revert GaugeErrors.InvalidToken();
            }

            info.totalWeights =
                info.totalWeights +
                poolWeights[i] -
                info.poolWeights[tokens[i]];
            info.poolWeights[tokens[i]] = poolWeights[i];
            unchecked {
                /// Update prior to current token then increment i.
                priorAddress = tokens[i++];
            }
        }
    }

    /// @notice Update reward variables for all pools.
    /// @param tokens Array containing all tokens to update pools for.
    function massUpdatePools(address[] calldata tokens) external {
        uint256 numTokens = tokens.length;
        for (uint256 i; i < numTokens; ) {
            unchecked {
                /// Update pool for current token then increment i.
                updatePool(tokens[i++]);
            }
        }
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Returns current epoch number.
    function currentEpoch() public view returns (uint256) {
        return epochOfTimestamp(block.timestamp);
    }

    /// @notice Returns epoch number of `timestamp`.
    /// @param timestamp Timestamp in seconds.
    function epochOfTimestamp(
        uint256 timestamp
    ) public view returns (uint256) {
        _checkGaugeHasStarted();
        return (timestamp - startTime) / EPOCH_WINDOW;
    }

    /// @notice Returns start time of `epoch`.
    /// @param epoch Epoch number.
    function epochStartTime(uint256 epoch) public view returns (uint256) {
        _checkGaugeHasStarted();
        return startTime + epoch * EPOCH_WINDOW;
    }

    /// @notice Returns end time of `epoch`.
    /// @param epoch Epoch number.
    function epochEndTime(uint256 epoch) public view returns (uint256) {
        _checkGaugeHasStarted();
        return startTime + (epoch + 1) * EPOCH_WINDOW;
    }

    /// @notice Returns if given gauge token is enabled in `epoch`.
    /// @param epoch Epoch number.
    /// @param token Gauge token address.
    function isGaugeEnabled(
        uint256 epoch,
        address token
    ) public view returns (bool) {
        return _epochInfo[epoch].poolWeights[token] > 0;
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert GaugeErrors.Unauthorized();
        }
    }

    /// @dev Checks whether the gauge controller has started or not.
    function _checkGaugeHasStarted() internal view {
        if (startTime == 0) {
            revert GaugeErrors.NotStarted();
        }
    }

    /// FUNCTIONS TO OVERRIDE ///

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param token Pool token address.
    function updatePool(address token) public virtual {}
}
