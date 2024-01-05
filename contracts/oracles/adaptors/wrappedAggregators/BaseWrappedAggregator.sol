// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { WAD } from "contracts/libraries/Constants.sol";

abstract contract BaseWrappedAggregator is IChainlink {
    function aggregator() external view returns (address) {
        return address(this);
    }

    function maxAnswer() external view returns (int192) {
        int256 max = int256(
            IChainlink(IChainlink(underlyingAssetAggregator()).aggregator())
                .maxAnswer()
        );

        max = (max * getWrappedAssetWeight()) / SafeCast.toInt256(WAD);
        if (max > type(int192).max) {
            return type(int192).max;
        }
        if (max < type(int192).min) {
            return type(int192).min;
        }

        return SafeCast.toInt192(max);
    }

    function minAnswer() external view returns (int192) {
        int256 min = int256(
            IChainlink(IChainlink(underlyingAssetAggregator()).aggregator())
                .minAnswer()
        );

        min = (min * getWrappedAssetWeight()) / SafeCast.toInt256(WAD);
        if (min > type(int192).max) {
            return type(int192).max;
        }
        if (min < type(int192).min) {
            return type(int192).min;
        }

        return SafeCast.toInt192(min);
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

        answer = (answer * getWrappedAssetWeight()) / SafeCast.toInt256(WAD);
    }

    function underlyingAssetAggregator()
        public
        view
        virtual
        returns (address)
    {}

    function getWrappedAssetWeight() public view virtual returns (int256) {}
}
