// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "contracts/interfaces/ICentralRegistry.sol";
import "../interfaces/IOracleAdaptor.sol";

/// @title Curvance Dual Oracle Price Router
/// @notice Provides a universal interface allowing Curvance contracts
///         to retrieve secure pricing data based on various price feeds.
contract PriceRouter {
    /// @notice Return data from oracle adaptor
    /// @param price the price of the asset in some asset, either ETH or USD
    /// @param hadError the message return data, whether the adaptor ran into trouble pricing the asset
    struct feedData {
        uint240 price;
        bool hadError;
    }

    struct cTokenData {
        bool isCToken;
        address underlying;
    }

    /// @notice Mapping used to track whether or not an address is an Adaptor.
    mapping(address => bool) public isApprovedAdaptor;
    /// @notice Mapping used to track an assets configured price feeds.
    mapping(address => address[]) public assetPriceFeeds;
    /// @notice Mapping used to link a collateral token to its underlying asset.
    mapping(address => cTokenData) public cTokenAssets;

    /// @notice Address for Curvance DAO registry contract for ownership and location data.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Address for chainlink feed to convert from eth -> usd or usd -> eth.
    address public immutable CHAINLINK_ETH_USD;

    /// @notice Offset for 8 decimal chainlink feeds.
    uint256 public constant CHAINLINK_DIVISOR = 1e8;

    /// @notice Offset for basis points precision for divergence value.
    uint256 public constant DENOMINATOR = 10000;

    /// @notice How wide a divergence between price feeds warrants pausing borrowing.
    uint256 public PRICEFEED_MAXIMUM_DIVERGENCE = 11000;

    /// @notice Maximum time that a chainlink feed can be stale before we do not trust the value.
    uint256 public CHAINLINK_MAX_DELAY = 1 days;

    /// @notice Error code for no error.
    uint256 public constant NO_ERROR = 0;

    /// @notice Error code for caution.
    uint256 public constant CAUTION = 1;

    /// @notice Error code for bad source.
    uint256 public constant BAD_SOURCE = 2;

    constructor(ICentralRegistry _centralRegistry, address ETH_USD_FEED) {
        centralRegistry = _centralRegistry;
        // Save the USD-ETH price feed because it is a widely used pricing path.
        CHAINLINK_ETH_USD = ETH_USD_FEED; // 0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419 on mainnet
    }

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyElevatedPermissions() {
        require(centralRegistry.hasElevatedPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
        _;
    }

    // Only callable by Adaptor
    modifier onlyAdaptor() {
        require(isApprovedAdaptor[msg.sender], "priceRouter: UNAUTHORIZED");
        _;
    }

    /// @notice Retrieves the price of a specified asset from either single or dual oracles.
    /// @dev If the asset has one oracle, it fetches the price from a single feed.
    /// If it has two or more oracles, it fetches the price from both feeds.
    /// @param _asset The address of the asset to retrieve the price for.
    /// @param _inUSD Whether the price should be returned in USD or ETH.
    /// @param _getLower Whether the lower or higher price should be returned if two feeds are available.
    /// @return A tuple containing the asset's price and an error flag (if any).
    function getPrice(
        address _asset,
        bool _inUSD,
        bool _getLower
    ) public view returns (uint256, uint256) {
        uint256 numAssetPriceFeeds = assetPriceFeeds[_asset].length;
        require(numAssetPriceFeeds > 0, "priceRouter: no feeds available");

        if(cTokenAssets[_asset].isCtoken){
            _asset = cTokenAssets[_asset].underlying;
        }

        if (numAssetPriceFeeds < 2) {
            return getPriceSingleFeed(_asset, _inUSD, _getLower);
        }

        return getPriceDualFeed(_asset, _inUSD, _getLower);
    }

    /// @notice Retrieves the prices of multiple specified assets.
    /// @dev Loops through the array of assets and retrieves the price for each using the getPrice function.
    /// @param _asset An array of asset addresses to retrieve the prices for.
    /// @param _inUSD An array of bools indicating whether the price should be returned in USD or ETH.
    /// @param _getLower An array of bools indiciating whether the lower or higher price should be returned if two feeds are available.
    /// @return Two arrays. The first one contains prices for each asset, and the second one contains corresponding error flags (if any).
    function getPriceMulti(
        address[] calldata _asset,
        bool[] calldata _inUSD,
        bool[] calldata _getLower
    ) public view returns (uint256[] memory, uint256[] memory) {
        uint256 numAssets = _asset.length;
        require(numAssets > 0, "priceRouter: no assets to price");
        uint256[] memory prices = new uint256[](numAssets);
        uint256[] memory hadError = new uint256[](numAssets);

        for (uint256 i; i < numAssets; ) {
            (prices[i], hadError[i]) = getPrice(
                _asset[i],
                _inUSD[i],
                _getLower[i]
            );

            unchecked {
                ++i;
            }
        }

        return (prices, hadError);
    }

    /// @notice Retrieves the price of a specified asset from two specific price feeds.
    /// @dev This function is internal and not meant to be accessed directly.
    /// It fetches the price from up to two feeds available for the asset.
    /// @param _asset The address of the asset to retrieve the price for.
    /// @param _inUSD Whether the price should be returned in USD or ETH.
    /// @param _getLower Whether the lower or higher price should be returned if two feeds are available.
    /// @return A tuple containing the asset's price and an error flag (if any).
    /// If both price feeds return an error, it returns (0, BAD_SOURCE).
    /// If one of the price feeds return an error, it returns the price from the working feed along with a CAUTION flag.
    /// Otherwise, it returns (price, NO_ERROR).
    function getPriceDualFeed(
        address _asset,
        bool _inUSD,
        bool _getLower
    ) internal view returns (uint256, uint256) {
        feedData memory feed0 = getPriceFromFeed(_asset, 0, _inUSD, _getLower);
        feedData memory feed1 = getPriceFromFeed(_asset, 1, _inUSD, _getLower);

        /// Check if we had any working price feeds, if not we need to block any market operations
        if (feed0.hadError && feed1.hadError) return (0, BAD_SOURCE);

        /// Check if we had an error in either price that should limit borrowing
        if (feed0.hadError || feed1.hadError) {
            return (getWorkingPrice(feed0, feed1), CAUTION);
        }
        if (_getLower)
            return calculateLowerPriceFeed(feed0.price, feed1.price);

        return calculateHigherPriceFeed(feed0.price, feed1.price);
    }

    /// @notice Retrieves the price of a specified asset from a single oracle.
    /// @dev Fetches the price from the first available price feed for the asset.
    /// @param _asset The address of the asset to retrieve the price for.
    /// @param _inUSD Whether the price should be returned in USD or ETH.
    /// @param _getLower Whether the lower or higher price should be returned if two feeds are available.
    /// @return A tuple containing the asset's price and an error flag (if any).
    /// If the price feed returns an error, it returns (0, BAD_SOURCE).
    /// Otherwise, it returns (price, NO_ERROR).
    function getPriceSingleFeed(
        address _asset,
        bool _inUSD,
        bool _getLower
    ) internal view returns (uint256, uint256) {
        PriceReturnData memory data = IOracleAdaptor(
            assetPriceFeeds[_asset][0]
        ).getPrice(_asset, _inUSD, _getLower);
        if (data.hadError) return (0, BAD_SOURCE);

        if (data.inUSD != _inUSD) {
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
    /// @dev Fetches the price from the nth price feed for the asset, where n is _feedNumber.
    /// Converts the price to USD if necessary.
    /// @param _asset The address of the asset to retrieve the price for.
    /// @param _feedNumber The index number of the feed to use.
    /// @param _inUSD Whether the price should be returned in USD or ETH.
    /// @param _getLower Whether the lower or higher price should be returned if two feeds are available.
    /// @return An instance of feedData containing the asset's price and an error flag (if any).
    /// If the price feed returns an error, it returns feedData with price 0 and hadError set to true.
    function getPriceFromFeed(
        address _asset,
        uint256 _feedNumber,
        bool _inUSD,
        bool _getLower
    ) internal view returns (feedData memory) {
        PriceReturnData memory data = IOracleAdaptor(
            assetPriceFeeds[_asset][_feedNumber]
        ).getPrice(_asset, _inUSD, _getLower);
        if (data.hadError) return (feedData({ price: 0, hadError: true }));

        if (data.inUSD != _inUSD) {
            uint256 conversionPrice;
            (conversionPrice, data.hadError) = getETHUSD();
            data.price = uint240(
                convertPriceETHUSD(data.price, conversionPrice, data.inUSD)
            );
        }

        return (feedData({ price: data.price, hadError: data.hadError }));
    }

    /// @notice Queries the current price of ETH in USD using Chainlink's ETH/USD feed.
    /// @dev The price is deemed valid if the data from Chainlink is fresh and positive.
    /// @return A tuple containing the price of ETH in USD and an error flag.
    /// If the Chainlink data is stale or negative, it returns (_answer, true).
    /// Where true corresponded to hasError = true.
    function getETHUSD() internal view returns (uint256, bool) {
        (, int256 _answer, , uint256 _updatedAt, ) = AggregatorV3Interface(
            CHAINLINK_ETH_USD
        ).latestRoundData();

        // If data is stale or negative we have a problem to relay back
        if (
            _answer <= 0 ||
            (block.timestamp - _updatedAt > CHAINLINK_MAX_DELAY)
        ) {
            return (uint256(_answer), true);
        }
        return (uint256(_answer), false);
    }

    /// @notice Converts a given price between ETH and USD formats.
    /// @dev Depending on the _currentFormatinUSD parameter, this function either converts the price from ETH to USD (if true)
    /// or from USD to ETH (if false) using the provided conversion rate.
    /// @param _currentPrice The price to convert.
    /// @param _conversionRate The rate to use for the conversion.
    /// @param _currentFormatinUSD Specifies whether the current format of the price is in USD.
    /// If true, it will convert the price from USD to ETH.
    /// If false, it will convert the price from ETH to USD.
    /// @return The converted price.
    function convertPriceETHUSD(
        uint240 _currentPrice,
        uint256 _conversionRate,
        bool _currentFormatinUSD
    ) internal pure returns (uint256) {
        if (!_currentFormatinUSD) {
            // current format is in ETH and we want USD
            return (_currentPrice * _conversionRate);
        }

        return (_currentPrice / _conversionRate);
    }

    /// @notice Processes the price data from two different feeds.
    /// @dev Checks for divergence between two prices. If the divergence is more than allowed,
    /// it returns (0, CAUTION).
    /// @param a The price from the first feed.
    /// @param b The price from the second feed.
    /// @return A tuple containing the lower of two prices and an error flag (if any).
    /// If the prices are within acceptable range, it returns (min(a,b), NO_ERROR).
    function calculateLowerPriceFeed(
        uint256 a,
        uint256 b
    ) internal view returns (uint256, uint256) {
        if (a <= b) {
            /// Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE of each other
            if (((a * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < b) {
                return (0, CAUTION);
            }
            return (a, NO_ERROR);
        }

        /// Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE of each other
        if (((b * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < a) {
            return (0, CAUTION);
        }
        return (b, NO_ERROR);
    }

    /// @notice Processes the price data from two different feeds.
    /// @dev Checks for divergence between two prices. If the divergence is more than allowed,
    /// it returns (0, CAUTION).
    /// @param a The price from the first feed.
    /// @param b The price from the second feed.
    /// @return A tuple containing the higher of two prices and an error flag (if any).
    /// If the prices are within acceptable range, it returns (max(a,b), NO_ERROR).
    function calculateHigherPriceFeed(
        uint256 a,
        uint256 b
    ) internal view returns (uint256, uint256) {
        if (a >= b) {
            /// Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE of each other
            if (((b * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < a) {
                return (0, CAUTION);
            }
            return (a, NO_ERROR);
        }

        /// Check if both feeds are within PRICEFEED_MAXIMUM_DIVERGENCE of each other
        if (((a * PRICEFEED_MAXIMUM_DIVERGENCE) / DENOMINATOR) < b) {
            return (0, CAUTION);
        }
        return (b, NO_ERROR);
    }

    /// @notice Returns the price from the working feed between two feeds.
    /// @dev If the first feed had an error, it returns the price from the second feed.
    /// @param feed0 The first feed's data.
    /// @param feed1 The second feed's data.
    /// @return The price from the working feed.
    function getWorkingPrice(
        feedData memory feed0,
        feedData memory feed1
    ) internal pure returns (uint256) {
        /// We know based on context of when this function is called that one but not both feeds have an error.
        /// So if feed0 had the error, feed1 is okay, and vice versa
        if (feed0.hadError) return feed1.price;
        return feed0.price;
    }

    /// @notice Retrieves the price feed data for a given asset.
    /// @dev Fetches the price for the provided asset from all available price feeds and returns them in an array.
    /// Each feedData in the array corresponds to a price feed. If less than two feeds are available, only the available feeds are returned.
    /// @param _asset The address of the asset.
    /// @param _inUSD Specifies whether the price format should be in USD or ETH.
    /// @return An array of feedData objects for the asset, each corresponding to a price feed.
    function getPricesForAsset(
        address _asset,
        bool _inUSD
    ) external view returns (feedData[] memory) {
        uint256 numAssetPriceFeeds = assetPriceFeeds[_asset].length;
        require(numAssetPriceFeeds > 0, "priceRouter: no feeds available");
        feedData[] memory data = new feedData[](numAssetPriceFeeds * 2);

        /// If the asset only has one price feed, we know itll be in feed slot 0 so get both prices and return
        if (numAssetPriceFeeds < 2) {
            data[0] = getPriceFromFeed(_asset, 0, _inUSD, true);
            data[1] = getPriceFromFeed(_asset, 0, _inUSD, false);
            return data;
        }

        /// We know the asset has two price feeds, so get pricing from both feeds and return
        data[0] = getPriceFromFeed(_asset, 0, _inUSD, true);
        data[1] = getPriceFromFeed(_asset, 0, _inUSD, false);
        data[2] = getPriceFromFeed(_asset, 1, _inUSD, true);
        data[3] = getPriceFromFeed(_asset, 1, _inUSD, false);

        return data;
    }

    /// @notice Checks if a given asset is supported by the price router.
    /// @dev An asset is considered supported if it has one or more associated price feeds.
    /// @param _asset The address of the asset to check.
    /// @return True if the asset is supported, false otherwise.
    function isSupportedAsset(address _asset) external view returns (bool) {
        if(cTokenAssets[_asset].isCtoken){
           return assetPriceFeeds[cTokenAssets[_asset].underlying].length > 0;
        }

        return assetPriceFeeds[_asset].length > 0;
    }

    /// @notice Adds a new price feed for a specific asset.
    /// @dev Requires that the feed address is an approved adaptor and that the asset doesn't already have two feeds.
    /// @param _asset The address of the asset.
    /// @param _feed The address of the new feed.
    function addAssetPriceFeed(
        address _asset,
        address _feed
    ) external onlyElevatedPermissions {
        require(isApprovedAdaptor[_feed], "priceRouter: unapproved feed");
        require(
            assetPriceFeeds[_asset].length < 2,
            "priceRouter: dual feed already configured"
        );
        require(
            IOracleAdaptor(_feed).isSupportedAsset(_asset),
            "priceRouter: not supported"
        );
        assetPriceFeeds[_asset].push(_feed);
    }

    /// @notice Removes a price feed for a specific asset.
    /// @dev Requires that the feed exists for the asset.
    /// @param _asset The address of the asset.
    /// @param _feed The address of the feed to be removed.
    function removeAssetPriceFeed(
        address _asset,
        address _feed
    ) public onlyDaoPermissions {
        uint256 numAssetPriceFeeds = assetPriceFeeds[_asset].length;
        require(numAssetPriceFeeds > 0, "priceRouter: no feeds available");

        if (numAssetPriceFeeds > 1) {
            require(
                assetPriceFeeds[_asset][0] == _feed ||
                    assetPriceFeeds[_asset][1] == _feed,
                "priceRouter: feed does not exist"
            );
            if (assetPriceFeeds[_asset][0] == _feed) {
                assetPriceFeeds[_asset][0] = assetPriceFeeds[_asset][1];
            } // we want to remove the first feed of two, so move the second feed to slot one
        } else {
            require(
                assetPriceFeeds[_asset][0] == _feed,
                "priceRouter: feed does not exist"
            );
        } // we know the feed exists, cant use isApprovedAdaptor as we could have removed it as an approved adaptor prior

        assetPriceFeeds[_asset].pop();
    }

    function addCTokenSupport(address cToken, address underlying) external onlyElevatedPermissions {
        require(
            !cTokenAssets[cToken].isCToken,
            "priceRouter: CToken already configured"
        );
        cTokenAssets[cToken].isCToken = true;
        cTokenAssets[cToken].underlying = underlying;
    }


    function removeCTokenSupport(address cToken) external onlyDaoPermissions {
        require(
            cTokenAssets[cToken].isCToken,
            "priceRouter: adaptor does not exist"
        );
        delete cTokenAssets[cToken];
    }

    function notifyAssetPriceFeedRemoval(address _asset) external onlyAdaptor {
        address _feed = msg.sender;
        uint256 numAssetPriceFeeds = assetPriceFeeds[_asset].length;
        require(numAssetPriceFeeds > 0, "priceRouter: no feeds available");

        if (numAssetPriceFeeds > 1) {
            require(
                assetPriceFeeds[_asset][0] == _feed ||
                    assetPriceFeeds[_asset][1] == _feed,
                "priceRouter: feed does not exist"
            );
            if (assetPriceFeeds[_asset][0] == _feed) {
                assetPriceFeeds[_asset][0] = assetPriceFeeds[_asset][1];
            } // we want to remove the first feed of two, so move the second feed to slot one
        } else {
            require(
                assetPriceFeeds[_asset][0] == _feed,
                "priceRouter: feed does not exist"
            );
        } // we know the feed exists, cant use isApprovedAdaptor as we could have removed it as an approved adaptor prior

        assetPriceFeeds[_asset].pop();
    }

    /// @notice Adds a new approved adaptor.
    /// @dev Requires that the adaptor isn't already approved.
    /// @param _adaptor The address of the adaptor to approve.
    function addApprovedAdaptor(address _adaptor) external onlyElevatedPermissions {
        require(
            !isApprovedAdaptor[_adaptor],
            "priceRouter: adaptor already approved"
        );
        isApprovedAdaptor[_adaptor] = true;
    }

    /// @notice Removes an approved adaptor.
    /// @dev Requires that the adaptor is currently approved.
    /// @param _adaptor The address of the adaptor to remove.
    function removeApprovedAdaptor(address _adaptor) external onlyDaoPermissions {
        require(
            isApprovedAdaptor[_adaptor],
            "priceRouter: adaptor does not exist"
        );
        delete isApprovedAdaptor[_adaptor];
    }

    /// @notice Sets a new maximum divergence for price feeds.
    /// @dev Requires that the new divergence is greater than or equal to 10200 aka 2%.
    /// @param _maxDivergence The new maximum divergence.
    function setPriceFeedMaxDivergence(
        uint256 _maxDivergence
    ) external onlyElevatedPermissions {
        require(
            _maxDivergence >= 10200,
            "priceRouter: divergence check is too small"
        );
        PRICEFEED_MAXIMUM_DIVERGENCE = _maxDivergence;
    }

    /// @notice Sets a new maximum delay for Chainlink price feed.
    /// @dev Requires that the new delay is less than 1 day. Only callable by the DaoManager.
    /// @param _delay The new maximum delay in seconds.
    function setChainlinkDelay(uint256 _delay) external onlyElevatedPermissions {
        require(_delay < 1 days, "priceRouter: delay is too large");
        CHAINLINK_MAX_DELAY = _delay;
    }
}
