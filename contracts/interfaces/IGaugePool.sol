// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IGaugePool {
    /// @notice Updates Gauge Emissions for a particular pool
    function setEmissionRates(
        uint256 epoch,
        address[] memory tokens,
        uint256[] memory poolWeights
    ) external;
}
