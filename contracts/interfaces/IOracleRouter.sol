// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

interface IOracleRouter {
    /// @notice Retrieves the price of a specified asset from either single
    ///         or dual oracles.
    /// @dev If the asset has one oracle, it fetches the price from a single feed.
    ///      If it has two or more oracles, it fetches the price from both feeds.
    /// @param asset The address of the asset to retrieve the price for.
    /// @param inUSD Whether the price should be returned in USD or ETH.
    /// @param getLower Whether the lower or higher price should be returned
    ///                 if two feeds are available.
    /// @return price The price of the asset.
    /// @return errorCode An error code related to fetching the price. 
    ///                   '1' indicates that price should be taken with
    ///                   caution.
    ///                   '2' indicates a complete failure in receiving
    ///                   a price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view returns (uint256, uint256);

    /// @notice Retrieves the prices of multiple assets.
    /// @param assets An array of asset addresses to retrieve the prices for.
    /// @param inUSD An array of bools indicating whether the price should be
    ///              returned in USD or ETH.
    /// @param getLower An array of bools indiciating whether the lower
    ///                 or higher price should be returned if two feeds
    ///                 are available.
    /// @return Two arrays. The first one contains prices for each asset,
    ///         and the second one contains corresponding error
    ///         flags (if any).
    function getPrices(
        address[] calldata assets,
        bool[] calldata inUSD,
        bool[] calldata getLower
    ) external view returns (uint256[] memory, uint256[] memory);

    /// @notice Retrieves the prices and account data of multiple assets
    ///         inside a Curvance Market.
    /// @param account The account to retrieve data for.
    /// @param assets An array of asset addresses to retrieve the prices for.
    /// @param errorCodeBreakpoint The error code that will cause liquidity
    ///                            operations to revert.
    /// @return AccountSnapshot[] Contains `assets` data for `account`
    /// @return uint256[] Contains prices for `assets`.
    /// @return uint256 The number of assets `account` is in.
    function getPricesForMarket(
        address account,
        IMToken[] calldata assets,
        uint256 errorCodeBreakpoint
    )
        external
        view
        returns (AccountSnapshot[] memory, uint256[] memory, uint256);

    /// @notice Removes a price feed for a specific asset
    ///         triggered by an adaptors notification.
    /// @dev Requires that the feed exists for the asset.
    /// @param asset The address of the asset.
    function notifyFeedRemoval(address asset) external;

    /// @notice Checks if a given asset is supported by the Oracle Router.
    /// @dev An asset is considered supported if it has one
    ///      or more associated price feeds.
    /// @param asset The address of the asset to check.
    /// @return True if the asset is supported, false otherwise.
    function isSupportedAsset(address asset) external view returns (bool);

    /// @notice Check whether L2 sequencer is valid or down.
    /// @return True if sequencer is valid.
    function isSequencerValid() external view returns (bool);
}
