// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IPriceRouter {

    /// @notice queries price from an oracle adaptor
    function getPrice(
        address _asset,
        bool _inUSD,
        bool _getLower
    ) external view returns (uint256, uint256);

    /// @notice Notifies the price router that an asset has been removed from the adaptor calling the function
    function notifyAssetPriceFeedRemoval(address _asset) external;

    function isSupportedAsset(address _asset) external view returns (bool);
}
