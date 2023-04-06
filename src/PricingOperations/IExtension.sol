// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IExtension {
    // Only callable by pricerouter.
    function setupSource(address asset, uint64 sourceId, bytes memory sourceData) external;

    function getPriceInBase(uint64 sourceId) external view returns (uint256, uint256);
}
