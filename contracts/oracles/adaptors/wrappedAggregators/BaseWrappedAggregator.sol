// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { FixedPointMathLib } from "contracts/libraries/external/FixedPointMathLib.sol";

import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";

abstract contract BaseWrappedAggregator is IChainlink {

    /// ERRORS ///

    error BaseWrappedAggregator__UintToIntError();
    error BaseWrappedAggregator__intToUIntError();

    /// EXTERNAL FUNCTIONS ///

    function aggregator() external view returns (address) {
        return address(this);
    }

    function maxAnswer() external view returns (int192) {
        uint256 max = uint256(
            uint192(IChainlink(IChainlink(underlyingAssetAggregator()).aggregator())
                .maxAnswer()
            )
        );

        max = FixedPointMathLib.fullMulDiv(max, getWrappedAssetWeight(), WAD);
        int256 intMax = _toInt256(max);
        if (intMax > type(int192).max) {
            return type(int192).max;
        }
        if (intMax < type(int192).min) {
            return type(int192).min;
        }

        return _toInt192(intMax);
    }

    function minAnswer() external view returns (int192) {
        uint256 min = uint256(
            uint192(IChainlink(IChainlink(underlyingAssetAggregator()).aggregator())
                .minAnswer()
            )
        );

        min = FixedPointMathLib.fullMulDiv(min, getWrappedAssetWeight(), WAD);
        int256 intMin = _toInt256(min);

        if (intMin > type(int192).max) {
            return type(int192).max;
        }
        if (intMin < type(int192).min) {
            return type(int192).min;
        }

        return _toInt192(intMin);
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

        answer = (answer * _toInt256(getWrappedAssetWeight())) / _toInt256(WAD);
    }

    /// PUBLIC FUNCTIONS TO OVERRIDE ///

    function underlyingAssetAggregator()
        public
        view
        virtual
        returns (address)
    {}

    function getWrappedAssetWeight() public view virtual returns (uint256) {}

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

    /// @dev Converts a signed int256 into an unsigned uint256.
    function _toUInt256(int256 value) internal pure returns (uint256) {
        if (value < 0) {
            revert BaseWrappedAggregator__intToUIntError();
        }
        return uint256(value);
    }
}
