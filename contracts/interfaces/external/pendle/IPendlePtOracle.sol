// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPendlePTOracle {
    function getOracleState(
        address market,
        uint32 duration
    )
        external
        view
        returns (
            bool increaseCardinalityRequired,
            uint16 cardinalityRequired,
            bool oldestObservationSatisfied
        );

    function getPtToAssetRate(
        address market,
        uint32 duration
    ) external view returns (uint256 ptToAssetRate);

    function getLpToAssetRate(
        address market,
        uint32 duration
    ) external view returns (uint256 ptToAssetRate);
}
