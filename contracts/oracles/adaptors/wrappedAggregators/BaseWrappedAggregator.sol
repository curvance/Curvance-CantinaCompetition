// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { WAD } from "contracts/libraries/Constants.sol";

abstract contract BaseWrappedAggregator is IChainlink {
    function aggregator() external view returns (address) {
        return address(this);
    }

    function maxAnswer() external view returns (int192) {
        uint256 max = uint256(
            uint192(
                IChainlink(
                    IChainlink(underlyingAssetAggregator()).aggregator()
                ).maxAnswer()
            )
        );

        // getWrappedAssetWeight() won't exceed uint64.max in most cases
        // we will revert if max * getWrappedAssetWeight() execeeds uint256.max
        max = (max * getWrappedAssetWeight()) / WAD;
        if (max > uint192(type(int192).max)) {
            return type(int192).max;
        }

        return int192(uint192(max));
    }

    function minAnswer() external view returns (int192) {
        uint256 min = uint256(
            uint192(
                IChainlink(
                    IChainlink(underlyingAssetAggregator()).aggregator()
                ).minAnswer()
            )
        );

        // getWrappedAssetWeight() won't exceed uint64.max in most cases
        // we will revert if min * getWrappedAssetWeight() execeeds uint256.max
        min = (min * getWrappedAssetWeight()) / WAD;
        if (min > uint192(type(int192).min)) {
            return type(int192).min;
        }

        return int192(uint192(min));
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

        // getWrappedAssetWeight() won't exceed uint64.max in most cases
        // we will revert if answer * getWrappedAssetWeight() execeeds uint256.max
        answer = int256((uint256(answer) * getWrappedAssetWeight()) / WAD);
    }

    function underlyingAssetAggregator()
        public
        view
        virtual
        returns (address)
    {}

    function getWrappedAssetWeight() public view virtual returns (uint256) {}
}
