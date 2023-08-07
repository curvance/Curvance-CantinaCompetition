// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

/// @title Curvance Dual Oracle Price Router
/// @notice Provides a universal interface allowing Curvance contracts
///         to retrieve secure pricing data based on various price feeds.
contract PriceRouter {
    
    /// TYPES ///

    struct FeedData {
        uint240 price; // price of the asset in some asset, either ETH or USD
        bool hadError; // message return data, true if adaptor couldnt price asset
    }

    struct MTokenData {
        bool isMToken; // Whether the provided address is an MToken or not
        address underlying; // Token address of underlying asset for MToken
    }

    /// CONSTANTS ///

    uint256 public constant CHAINLINK_DIVISOR = 1e8; // Chainlink decimal offset
    uint256 public constant DENOMINATOR = 10000; // Scalar for divergence value
    uint256 public constant NO_ERROR = 0; // 0 = no error
    uint256 public constant CAUTION = 1; // 1 = price divergence or 1 missing price
    uint256 public constant BAD_SOURCE = 2; // 2 = could not price at all
    address public immutable CHAINLINK_ETH_USD; // Feed to convert ETH -> USD
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///

    uint256 public PRICEFEED_MAXIMUM_DIVERGENCE = 11000; // Corresponds to 10%
    uint256 public CHAINLINK_MAX_DELAY = 1 days; // Maximum chainlink price staleness


    /// Address => Adaptor approval status
    mapping(address => bool) public isApprovedAdaptor;
    /// Address => Price Feed addresses
    mapping(address => address[]) public assetPriceFeeds;
    /// Address => MToken metadata
    mapping(address => MTokenData) public mTokenAssets;

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "centralRegistry: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "centralRegistry: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyAdaptor() {
        require(isApprovedAdaptor[msg.sender], "PriceRouter: UNAUTHORIZED");
        _;
    }

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address ETH_USDFEED) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "PriceRouter: invalid central registry"
        );
        require(
            ETH_USDFEED != address(0),
            "PriceRouter: ETH-USD Feed is invalid"
        );

        centralRegistry = centralRegistry_;
        // Save the USD-ETH price feed because it is a widely used pricing path.
        CHAINLINK_ETH_USD = ETH_USDFEED; // 0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419 on mainnet
    }

    /// FUNCTIONS ///

    /// @notice Adds a new price feed for a specific asset.
    /// @dev Requires that the feed address is an approved adaptor
    ///      and that the asset doesn't already have two feeds.
    /// @param asset The address of the asset.
    /// @param feed The address of the new feed.
    function addAssetPriceFeed(
        address asset,
        address feed
    ) external onlyElevatedPermissions {
        require(isApprovedAdaptor[feed], "PriceRouter: unapproved feed");

        require(
            IOracleAdaptor(feed).isSupportedAsset(asset),
            "PriceRouter: not supported"
        );

        uint256 numPriceFeeds = assetPriceFeeds[asset].length;

        require(
            numPriceFeeds < 2,
            "PriceRouter: dual feed already configured"
        );
        require(
            numPriceFeeds == 0 || assetPriceFeeds[asset][0] != feed,
            "PriceRouter: feed already added"
        );

        assetPriceFeeds[asset].push(feed);
    }

    /// @notice Removes a price feed for a specific asset.
    /// @dev Requires that the feed exists for the asset.
    /// @param asset The address of the asset.
    /// @param feed The address of the feed to be removed.
    function removeAssetPriceFeed(
        address asset,
        address feed
    ) external onlyDaoPermissions {
        _removeAssetPriceFeed(asset, feed);
    }

    function addMTokenSupport(
        address mToken
    ) external onlyElevatedPermissions {
        require(
            !mTokenAssets[mToken].isMToken,
            "PriceRouter: MToken already configured"
        );
        require(
            ERC165Checker.supportsInterface(mToken, type(IMToken).interfaceId),
            "PriceRouter: MToken is invalid"
        );

        mTokenAssets[mToken].isMToken = true;
        mTokenAssets[mToken].underlying = IMToken(mToken).underlying();
    }

    function removeMTokenSupport(address mToken) external onlyDaoPermissions {
        require(
            mTokenAssets[mToken].isMToken,
            "PriceRouter: MToken is not configured"
        );
        delete mTokenAssets[mToken];
    }

    function notifyAssetPriceFeedRemoval(address asset) external onlyAdaptor {
        _removeAssetPriceFeed(asset, msg.sender);
    }

    /// @notice Adds a new approved adaptor.
    /// @dev Requires that the adaptor isn't already approved.
    /// @param _adaptor The address of the adaptor to approve.
    function addApprovedAdaptor(
        address _adaptor
    ) external onlyElevatedPermissions {
        require(
            !isApprovedAdaptor[_adaptor],
            "PriceRouter: adaptor already approved"
        );
        isApprovedAdaptor[_adaptor] = true;
    }

    /// @notice Removes an approved adaptor.
    /// @dev Requires that the adaptor is currently approved.
    /// @param _adaptor The address of the adaptor to remove.
    function removeApprovedAdaptor(
        address _adaptor
    ) external onlyDaoPermissions {
        require(
            isApprovedAdaptor[_adaptor],
            "PriceRouter: adaptor does not exist"
        );
        delete isApprovedAdaptor[_adaptor];
    }

    /// @notice Sets a new maximum divergence for price feeds.
    /// @dev Requires that the new divergence is greater than
    ///      or equal to 10200 aka 2%.
    /// @param maxDivergence The new maximum divergence.
    function setPriceFeedMaxDivergence(
        uint256 maxDivergence
    ) external onlyElevatedPermissions {
        require(
            maxDivergence >= 10200,
            "PriceRouter: divergence check is too small"
        );
        PRICEFEED_MAXIMUM_DIVERGENCE = maxDivergence;
    }

    /// @notice Sets a new maximum delay for Chainlink price feed.
    /// @dev Requires that the new delay is less than 1 day.
    ///      Only callable by the DaoManager.
    /// @param delay The new maximum delay in seconds.
    function setChainlinkDelay(
        uint256 delay
    ) external onlyElevatedPermissions {
        require(delay < 1 days, "PriceRouter: delay is too large");
        CHAINLINK_MAX_DELAY = delay;
    }

    /// @notice Retrieves the price feed data for a given asset.
    /// @dev Fetches the price for the provided asset from all available
    ///      price feeds and returns them in an array.
    ///      Each FeedData in the array corresponds to a price feed.
    ///      If less than two feeds are available, only the available feeds
    ///      are returned.
    /// @param asset The address of the asset.
    /// @param inUSD Specifies whether the price format should be in USD or ETH.
    /// @return An array of FeedData objects for the asset, each corresponding
    ///         to a price feed.
    function getPricesForAsset(
        address asset,
        bool inUSD
    ) external view returns (FeedData[] memory) {
        uint256 numAssetPriceFeeds = assetPriceFeeds[asset].length;
        require(numAssetPriceFeeds > 0, "PriceRouter: no feeds available");
        FeedData[] memory data = new FeedData[](numAssetPriceFeeds * 2);

        /// If the asset only has one price feed, we know itll be in
        /// feed slot 0 so get both prices and return
        if (numAssetPriceFeeds < 2) {
            data[0] = getPriceFromFeed(asset, 0, inUSD, true);
            data[1] = getPriceFromFeed(asset, 0, inUSD, false);
            return data;
        }

        /// We know the asset has two price feeds, so get pricing from
        /// both feeds and return
        data[0] = getPriceFromFeed(asset, 0, inUSD, true);
        data[1] = getPriceFromFeed(asset, 0, inUSD, false);
        data[2] = getPriceFromFeed(asset, 1, inUSD, true);
        data[3] = getPriceFromFeed(asset, 1, inUSD, false);

        return data;
    }

    /// @notice Checks if a given asset is supported by the price router.
    /// @dev An asset is considered supported if it has one
    ///      or more associated price feeds.
    /// @param asset The address of the asset to check.
    /// @return True if the asset is supported, false otherwise.
    function isSupportedAsset(address asset) external view returns (bool) {
        if (mTokenAssets[asset].isMToken) {
            return assetPriceFeeds[mTokenAssets[asset].underlying].length > 0;
        }

        return assetPriceFeeds[asset].length > 0;
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Retrieves the price of a specified asset from either single
    ///         or dual oracles.
    /// @dev If the asset has one oracle, it fetches the price from a single feed.
    ///      If it has two or more oracles, it fetches the price from both feeds.
    /// @param asset The address of the asset to retrieve the price for.
    /// @param inUSD Whether the price should be returned in USD or ETH.
    /// @param getLower Whether the lower or higher price should be returned
    ///                 if two feeds are available.
    /// @return price The price of the asset.
    /// @return errorCode An error code related to fetching the price. '1' indicates that price should be taken with caution.
    ///                   '2' indicates a complete failure in receiving a price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) public view returns (uint256 price, uint256 errorCode) {
        uint256 numAssetPriceFeeds = assetPriceFeeds[asset].length;
        require(numAssetPriceFeeds > 0, "PriceRouter: no feeds available");

        if (mTokenAssets[asset].isMToken) {
            asset = mTokenAssets[asset].underlying;
        }

        if (numAssetPriceFeeds < 2) {
            (price, errorCode) = getPriceSingleFeed(asset, inUSD, getLower);
        } else {
            (price, errorCode) = getPriceDualFeed(asset, inUSD, getLower);
        }

        /// If somehow a feed returns a price of 0 make sure we trigger the BAD_SOURCE flag
        if (price == 0 && errorCode < BAD_SOURCE) {
            errorCode = BAD_SOURCE;
        }
    }

    /// @notice Retrieves the prices of multiple specified assets.
    /// @dev Loops through the array of assets and retrieves the price
    ///      for each using the getPrice function.
    /// @param assets An array of asset addresses to retrieve the prices for.
    /// @param inUSD An array of bools indicating whether the price should be
    ///              returned in USD or ETH.
    /// @param getLower An array of bools indiciating whether the lower
    ///                 or higher price should be returned if two feeds are available.
    /// @return Two arrays. The first one contains prices for each asset,
    ///         and the second one contains corresponding error flags (if any).
    function getPriceMulti(
        address[] calldata assets,
        bool[] calldata inUSD,
        bool[] calldata getLower
    ) public view returns (uint256[] memory, uint256[] memory) {
        uint256 numAssets = assets.length;

        require(numAssets > 0, "PriceRouter: no assets to price");
        require(
            numAssets == inUSD.length && numAssets == getLower.length,
            "PriceRouter: incorrect param lengths"
        );

        uint256[] memory prices = new uint256[](numAssets);
        uint256[] memory hadError = new uint256[](numAssets);

        for (uint256 i; i < numAssets; ) {
            (prices[i], hadError[i]) = getPrice(
                assets[i],
                inUSD[i],
                getLower[i]
            );

            unchecked {
                ++i;
            }
        }

        return (prices, hadError);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Removes a price feed for a specific asset.
    /// @dev Requires that the feed exists for the asset.
    /// @param asset The address of the asset.
    /// @param feed The address of the feed to be removed.
    function _removeAssetPriceFeed(address asset, address feed) internal {
        uint256 numAssetPriceFeeds = assetPriceFeeds[asset].length;
        require(numAssetPriceFeeds > 0, "PriceRouter: no feeds available");

        if (numAssetPriceFeeds > 1) {
            require(
                assetPriceFeeds[asset][0] == feed ||
                    assetPriceFeeds[asset][1] == feed,
                "PriceRouter: feed does not exist"
            );

            // we want to remove the first feed of two,
            // so move the second feed to slot one
            if (assetPriceFeeds[asset][0] == feed) {
                assetPriceFeeds[asset][0] = assetPriceFeeds[asset][1];
            }
        } else {
            require(
                assetPriceFeeds[asset][0] == feed,
                "PriceRouter: feed does not exist"
            );
        }
        // we know the feed exists, cant use isApprovedAdaptor as
        // we could have removed it as an approved adaptor prior

        assetPriceFeeds[asset].pop();
    }

    /// @notice Retrieves the price of a specified asset from two specific price feeds.
    /// @dev This function is internal and not meant to be accessed directly.
    ///      It fetches the price from up to two feeds available for the asset.
    /// @param asset The address of the asset to retrieve the price for.
    /// @param inUSD Whether the price should be returned in USD or ETH.
    /// @param getLower Whether the lower or higher price should be returned
    ///                 if two feeds are available.
    /// @return A tuple containing the asset's price and an error flag (if any).
    ///         If both price feeds return an error, it returns (0, BAD_SOURCE).
    ///         If one of the price feeds return an error, it returns the price
    ///         from the working feed along with a CAUTION flag.
    ///         Otherwise, it returns (price, NO_ERROR).
    function getPriceDualFeed(
        address asset,
        bool inUSD,
        bool getLower
    ) internal view returns (uint256, uint256) {
        FeedData memory feed0 = getPriceFromFeed(asset, 0, inUSD, getLower);
        FeedData memory feed1 = getPriceFromFeed(asset, 1, inUSD, getLower);

        // Check if we had any working price feeds,
        // if not we need to block any market operations
        if (feed0.hadError && feed1.hadError) return (0, BAD_SOURCE);

        // Check if we had an error in either price that should limit borrowing
        if (feed0.hadError || feed1.hadError) {
            return (getWorkingPrice(feed0, feed1), CAUTION);
        }
        if (getLower) return calculateLowerPriceFeed(feed0.price, feed1.price);

        return calculateHigherPriceFeed(feed0.price, feed1.price);
    }

    /// @notice Retrieves the price of a specified asset from a single oracle.
    /// @dev Fetches the price from the first available price feed for the asset.
    /// @param asset The address of the asset to retrieve the price for.
    /// @param inUSD Whether the price should be returned in USD or ETH.
    /// @param getLower Whether the lower or higher price should be returned
    ///                 if two feeds are available.
    /// @return A tuple containing the asset's price and an error flag (if any).
    ///         If the price feed returns an error, it returns (0, BAD_SOURCE).
    ///         Otherwise, it returns (price, NO_ERROR).
    function getPriceSingleFeed(
        address asset,
        bool inUSD,
        bool getLower
    ) internal view returns (uint256, uint256) {
        PriceReturnData memory data = IOracleAdaptor(assetPriceFeeds[asset][0])
            .getPrice(asset, inUSD, getLower);
        if (data.hadError) return (0, BAD_SOURCE);

        if (data.inUSD != inUSD) {
            uint256 conversionPrice;
            (conversionPrice, data.hadError) = getETHUSD();
            if (data.hadError) return (0, BAD_SOURCE);

            data.price = uint240(
                convertPriceETHUSD(data.price, conversionPrice, data.inUSD)
            );
        }

        return (data.price, NO_ERROR);
    }

    /// @notice Retrieves the price of a specified asset from a specific price feed.
    /// @dev Fetches the price from the nth price feed for the asset,
    ///      where n is feedNumber.
    ///      Converts the price to USD if necessary.
    /// @param asset The address of the asset to retrieve the price for.
    /// @param feedNumber The index number of the feed to use.
    /// @param inUSD Whether the price should be returned in USD or ETH.
    /// @param getLower Whether the lower or higher price should be returned
    ///                 if two feeds are available.
    /// @return An instance of FeedData containing the asset's price
    ///         and an error flag (if any).
    ///         If the price feed returns an error, it returns feedData
    ///         with price 0 and hadError set to true.
    function getPriceFromFeed(
        address asset,
        uint256 feedNumber,
        bool inUSD,
        bool getLower
    ) internal view returns (FeedData memory) {
        PriceReturnData memory data = IOracleAdaptor(
            assetPriceFeeds[asset][feedNumber]
        ).getPrice(asset, inUSD, getLower);
        if (data.hadError) return (FeedData({ price: 0, hadError: true }));

        if (data.inUSD != inUSD) {
            uint256 conversionPrice;
            (conversionPrice, data.hadError) = getETHUSD();
            data.price = uint240(
                convertPriceETHUSD(data.price, conversionPrice, data.inUSD)
            );
        }

        return (FeedData({ price: data.price, hadError: data.hadError }));
    }

    /// @notice Queries the current price of ETH in USD using Chainlink's ETH/USD feed.
    /// @dev The price is deemed valid if the data from Chainlink is fresh
    ///      and positive.
    /// @return A tuple containing the price of ETH in USD and an error flag.
    ///         If the Chainlink data is stale or negative,
    ///         it returns (answer, true).
    ///         Where true corresponded to hasError = true.
    function getETHUSD() internal view returns (uint256, bool) {
        (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(
            CHAINLINK_ETH_USD
        ).latestRoundData();

        // If data is stale or negative we have a problem to relay back
        if (
            answer <= 0 || (block.timestamp - updatedAt > CHAINLINK_MAX_DELAY)
        ) {
            return (uint256(answer), true);
        }
        return (uint256(answer), false);
    }

    /// @notice Converts a given price between ETH and USD formats.
    /// @dev Depending on the currentFormatInUSD parameter,
    ///      this function either converts the price from ETH to USD (if true)
    /// or from USD to ETH (if false) using the provided conversion rate.
    /// @param currentPrice The price to convert.
    /// @param conversionRate The rate to use for the conversion.
    /// @param currentFormatInUSD Specifies whether the current format of the price is in USD.
    ///                           If true, it will convert the price from USD to ETH.
    ///                           If false, it will convert the price from ETH to USD.
    /// @return The converted price.
    function convertPriceETHUSD(
        uint240 currentPrice,
        uint256 conversionRate,
        bool currentFormatInUSD
    ) internal pure returns (uint256) {
        if (!currentFormatInUSD) {
            // current format is in ETH and we want USD
            return (currentPrice * conversionRate);
        }

        return (currentPrice / conversionRate);
    }

    /// @notice Processes the price data from two different feeds.
    /// @dev Checks for divergence between two prices.
    ///      If the divergence is more than allowed, it returns (0, CAUTION).
    /// @param a The price from the first feed.
    /// @param b The price from the second feed.
    /// @return A tuple containing the lower of two prices and an error flag (if any).
    ///         If the prices are within acceptable range,
    ///         it returns (min(a,b), NO_ERROR).
    function calculateLowerPriceFeed(
        uint256 a,
        uint256 b
    ) internal view returns (uint256, uint256) {
        if (a <= b) {
            // Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE
            // of each other
            if (((a * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < b) {
                /// Return the price but notify that the price should be taken with caution
                /// because we are outside the accepted range of divergence
                return (a, CAUTION);
            }
            return (a, NO_ERROR);
        }

        // Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE
        // of each other
        if (((b * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < a) {
            /// Return the price but notify that the price should be taken with caution
            /// because we are outside the accepted range of divergence
            return (b, CAUTION);
        }
        return (b, NO_ERROR);
    }

    /// @notice Processes the price data from two different feeds.
    /// @dev Checks for divergence between two prices.
    ///      If the divergence is more than allowed, it returns (0, CAUTION).
    /// @param a The price from the first feed.
    /// @param b The price from the second feed.
    /// @return A tuple containing the higher of two prices and an error flag (if any).
    ///         If the prices are within acceptable range,
    ///         it returns (max(a,b), NO_ERROR).
    function calculateHigherPriceFeed(
        uint256 a,
        uint256 b
    ) internal view returns (uint256, uint256) {
        if (a >= b) {
            // Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE
            // of each other
            if (((b * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < a) {
                /// Return the price but notify that the price should be taken with caution
                /// because we are outside the accepted range of divergence
                return (a, CAUTION);
            }
            return (a, NO_ERROR);
        }

        // Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE
        // of each other
        if (((a * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < b) {
            /// Return the price but notify that the price should be taken with caution
            /// because we are outside the accepted range of divergence
            return (b, CAUTION);
        }
        return (b, NO_ERROR);
    }

    /// @notice Returns the price from the working feed between two feeds.
    /// @dev If the first feed had an error, it returns the price from
    ///      the second feed.
    /// @param feed0 The first feed's data.
    /// @param feed1 The second feed's data.
    /// @return The price from the working feed.
    function getWorkingPrice(
        FeedData memory feed0,
        FeedData memory feed1
    ) internal pure returns (uint256) {
        // We know based on context of when this function is called that one
        // but not both feeds have an error.
        // So if feed0 had the error, feed1 is okay, and vice versa
        if (feed0.hadError) return feed1.price;
        return feed0.price;
    }
}
