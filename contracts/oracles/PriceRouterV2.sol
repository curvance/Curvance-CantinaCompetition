// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICToken } from "contracts/interfaces/market/ICToken.sol";
import "../interfaces/IOracleAdaptor.sol";

/// @title Curvance Dual Oracle Price Router
/// @notice Provides a universal interface allowing Curvance contracts
///         to retrieve secure pricing data based on various price feeds.
contract PriceRouter {
    /// @notice Return data from oracle adaptor
    /// @param price the price of the asset in some asset, either ETH or USD
    /// @param hadError the message return data, whether the adaptor ran into
    ///                 trouble pricing the asset
    struct FeedData {
        uint240 price;
        bool hadError;
    }

    struct CTokenData {
        bool isCToken;
        address underlying;
    }

    /// CONSTANTS ///

    /// @notice Offset for 8 decimal chainlink feeds.
    uint256 public constant CHAINLINK_DIVISOR = 1e8;

    /// @notice Offset for basis points precision for divergence value.
    uint256 public constant DENOMINATOR = 10000;

    /// @notice Error code for no error.
    uint256 public constant NO_ERROR = 0;

    /// @notice Error code for caution.
    uint256 public constant CAUTION = 1;

    /// @notice Error code for bad source.
    uint256 public constant BAD_SOURCE = 2;

    /// @notice Address for Curvance DAO registry contract for ownership
    ///         and location data.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Address for chainlink feed to convert from eth -> usd
    ///         or usd -> eth.
    address public immutable CHAINLINK_ETH_USD;

    /// STORAGE ///

    /// @notice How wide a divergence between price feeds warrants
    ///         pausing borrowing.
    uint256 public PRICEFEED_MAXIMUM_DIVERGENCE = 11000;

    /// @notice Maximum time that a chainlink feed can be stale before
    ///         we do not trust the value.
    uint256 public CHAINLINK_MAX_DELAY = 1 days;

    /// @notice Mapping used to track whether or not an address is an Adaptor.
    mapping(address => bool) public isApprovedAdaptor;

    /// @notice Mapping used to track an assets configured price feeds.
    mapping(address => address[]) public assetPriceFeeds;

    /// @notice Mapping used to link a collateral token to its underlying asset.
    mapping(address => CTokenData) public cTokenAssets;

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

    // Only callable by Adaptor
    modifier onlyAdaptor() {
        require(isApprovedAdaptor[msg.sender], "priceRouter: UNAUTHORIZED");
        _;
    }

    constructor(ICentralRegistry _centralRegistry, address ETH_USDFEED) {
        require(
            ERC165Checker.supportsInterface(
                address(_centralRegistry),
                type(ICentralRegistry).interfaceId
            ),
            "priceRouter: Central Registry is invalid"
        );
        require(
            ETH_USDFEED != address(0),
            "priceRouter: ETH-USD Feed is invalid"
        );

        centralRegistry = _centralRegistry;
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
        require(isApprovedAdaptor[feed], "priceRouter: unapproved feed");

        require(
            IOracleAdaptor(feed).isSupportedAsset(asset),
            "priceRouter: not supported"
        );

        uint256 numPriceFeeds = assetPriceFeeds[asset].length;

        require(
            numPriceFeeds < 2,
            "priceRouter: dual feed already configured"
        );
        require(
            numPriceFeeds == 0 || assetPriceFeeds[asset][0] != feed,
            "priceRouter: feed already added"
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

    function addCTokenSupport(
        address cToken
    ) external onlyElevatedPermissions {
        require(
            !cTokenAssets[cToken].isCToken,
            "priceRouter: CToken already configured"
        );
        require(
            ERC165Checker.supportsInterface(cToken, type(ICToken).interfaceId),
            "priceRouter: CToken is invalid"
        );

        cTokenAssets[cToken].isCToken = true;
        cTokenAssets[cToken].underlying = ICToken(cToken).underlying();
    }

    function removeCTokenSupport(address cToken) external onlyDaoPermissions {
        require(
            cTokenAssets[cToken].isCToken,
            "priceRouter: CToken is not configured"
        );
        delete cTokenAssets[cToken];
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
            "priceRouter: adaptor already approved"
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
            "priceRouter: adaptor does not exist"
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
            "priceRouter: divergence check is too small"
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
        require(delay < 1 days, "priceRouter: delay is too large");
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
        require(numAssetPriceFeeds > 0, "priceRouter: no feeds available");
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
        if (cTokenAssets[asset].isCToken) {
            return assetPriceFeeds[cTokenAssets[asset].underlying].length > 0;
        }

        return assetPriceFeeds[asset].length > 0;
    }

    /// @notice Retrieves the price of a specified asset from either single
    ///         or dual oracles.
    /// @dev If the asset has one oracle, it fetches the price from a single feed.
    ///      If it has two or more oracles, it fetches the price from both feeds.
    /// @param asset The address of the asset to retrieve the price for.
    /// @param inUSD Whether the price should be returned in USD or ETH.
    /// @param getLower Whether the lower or higher price should be returned
    ///                 if two feeds are available.
    /// @return A tuple containing the asset's price and an error flag (if any).
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) public view returns (uint256, uint256) {
        uint256 numAssetPriceFeeds = assetPriceFeeds[asset].length;
        require(numAssetPriceFeeds > 0, "priceRouter: no feeds available");

        if (cTokenAssets[asset].isCToken) {
            asset = cTokenAssets[asset].underlying;
        }

        if (numAssetPriceFeeds < 2) {
            return getPriceSingleFeed(asset, inUSD, getLower);
        }

        return getPriceDualFeed(asset, inUSD, getLower);
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

        require(numAssets > 0, "priceRouter: no assets to price");

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
        require(numAssetPriceFeeds > 0, "priceRouter: no feeds available");

        if (numAssetPriceFeeds > 1) {
            require(
                assetPriceFeeds[asset][0] == feed ||
                    assetPriceFeeds[asset][1] == feed,
                "priceRouter: feed does not exist"
            );

            // we want to remove the first feed of two,
            // so move the second feed to slot one
            if (assetPriceFeeds[asset][0] == feed) {
                assetPriceFeeds[asset][0] = assetPriceFeeds[asset][1];
            }
        } else {
            require(
                assetPriceFeeds[asset][0] == feed,
                "priceRouter: feed does not exist"
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
                return (0, CAUTION);
            }
            return (a, NO_ERROR);
        }

        // Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE
        // of each other
        if (((b * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < a) {
            return (0, CAUTION);
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
                return (0, CAUTION);
            }
            return (a, NO_ERROR);
        }

        // Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE
        // of each other
        if (((a * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < b) {
            return (0, CAUTION);
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
