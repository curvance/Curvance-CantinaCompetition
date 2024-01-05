// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { WAD } from "contracts/libraries/Constants.sol";

abstract contract BaseWrappedAggregator is IChainlink {

    /// ERRORS ///

    error BaseWrappedAggregator__UintToIntError();

    /// EXTERNAL FUNCTIONS ///

    function aggregator() external view returns (address) {
        return address(this);
    }

    function maxAnswer() external view returns (int192) {
        int256 max = int256(
            IChainlink(IChainlink(underlyingAssetAggregator()).aggregator())
                .maxAnswer()
        );

        max = (max * getWrappedAssetWeight()) / _toInt256(WAD);
        if (max > type(int192).max) {
            return type(int192).max;
        }
        if (max < type(int192).min) {
            return type(int192).min;
        }

        return _toInt192(max);
    }

    function minAnswer() external view returns (int192) {
        int256 min = int256(
            IChainlink(IChainlink(underlyingAssetAggregator()).aggregator())
                .minAnswer()
        );

        min = (min * getWrappedAssetWeight()) / _toInt256(WAD);
        if (min > type(int192).max) {
            return type(int192).max;
        }
        if (min < type(int192).min) {
            return type(int192).min;
        }

        return _toInt192(min);
    }

    function decimals() external view returns (uint8) {
        return IChainlink(underlyingAssetAggregator()).decimals();
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = IChainlink(
            underlyingAssetAggregator()
        ).latestRoundData();

        answer = (answer * getWrappedAssetWeight()) / _toInt256(WAD);
    }

    /// PUBLIC FUNCTIONS TO OVERRIDE ///

    function underlyingAssetAggregator()
        public
        view
        virtual
        returns (address)
    {}

    function getWrappedAssetWeight() public view virtual returns (int256) {}

    /// INTERNAl FUNCTIONS /// 

    /// @dev Returns the downcasted int192 from int256, reverting on
    ///      overflow (when the input is less than smallest int192 or
    ///      greater than largest int192).
    function _toInt192(int256 value) internal pure returns (int192 downcasted) {
        downcasted = int192(value);
        if (downcasted != value) {
            revert BaseWrappedAggregator__UintToIntError();
        }
    }

    /// @dev Converts an unsigned uint256 into a signed int256.
    function _toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max`
        //       is guaranteed to be positive
        if (value > uint256(type(int256).max)) {
            revert BaseWrappedAggregator__UintToIntError();
        }
        return int256(value);
    }
}
