// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { WAD, DENOMINATOR } from "contracts/libraries/Constants.sol";

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

    /// @notice Return value indicating no price error
    uint256 public constant NO_ERROR = 0;

    /// @notice Return value indicating price divergence or 1 missing price
    uint256 public constant CAUTION = 1;

    /// @notice Return value indicating no price returned at all
    uint256 public constant BAD_SOURCE = 2;

    /// @notice The address of the chainlink feed to convert ETH -> USD
    address public immutable CHAINLINK_ETH_USD;

    /// @notice The number of decimals the aggregator responses with.
    uint256 public immutable CHAINLINK_DECIMALS;

    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// @notice Time to pass before accepting answers when sequencer
    ///         comes back up.
    uint256 public constant GRACE_PERIOD_TIME = 3600;

    // `bytes4(keccak256(bytes("PriceRouter__NotSupported()")))`
    uint256 internal constant NOT_SUPPORTED_SELECTOR = 0xe4558fac;
    // `bytes4(keccak256(bytes("PriceRouter__InvalidParameter()")))`
    uint256 internal constant INVALID_PARAMETER_SELECTOR = 0xebd2e1ff;
    // `bytes4(keccak256(bytes("PriceRouter__ErrorCodeFlagged()")))`
    uint256 internal constant ERROR_CODE_FLAGGED_SELECTOR = 0x891531fb;

    /// STORAGE ///

    /// @notice The maximum allowed divergence between prices in `DENOMINATOR`
    uint256 public MAXIMUM_DIVERGENCE = 11000; // 10%
    /// @notice The maximum delay accepted between answers from chainlink
    uint256 public CHAINLINK_MAX_DELAY = 1 days;

    // Address => Adaptor approval status
    mapping(address => bool) public isApprovedAdaptor;
    // Address => Price Feed addresses
    mapping(address => address[]) public assetPriceFeeds;
    // Address => MToken metadata
    mapping(address => MTokenData) public mTokenAssets;

    /// ERRORS ///

    error PriceRouter__Unauthorized();
    error PriceRouter__NotSupported();
    error PriceRouter__InvalidParameter();
    error PriceRouter__ErrorCodeFlagged();
    error PriceRouter__AdaptorIsNotApproved();

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address ethUsdFeed) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        if (ethUsdFeed == address(0)) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        centralRegistry = centralRegistry_;
        // Save the USD-ETH price feed because it is a widely used pricing path.
        CHAINLINK_ETH_USD = ethUsdFeed; // 0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419 on mainnet
        CHAINLINK_DECIMALS = 10 ** IChainlink(CHAINLINK_ETH_USD).decimals();
    }

    /// FUNCTIONS ///

    /// @notice Adds a new price feed for a specific asset.
    /// @dev Requires that the feed address is an approved adaptor
    ///      and that the asset doesn't already have two feeds.
    /// @param asset The address of the asset.
    /// @param feed The address of the new feed.
    function addAssetPriceFeed(address asset, address feed) external {
        _checkElevatedPermissions();

        if (!isApprovedAdaptor[feed]) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        if (!IOracleAdaptor(feed).isSupportedAsset(asset)) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        uint256 numPriceFeeds = assetPriceFeeds[asset].length;

        if (numPriceFeeds >= 2) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        if (numPriceFeeds != 0 && assetPriceFeeds[asset][0] == feed) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        assetPriceFeeds[asset].push(feed);
    }

    /// @notice Removes a price feed for a specific asset.
    /// @dev Requires that the feed exists for the asset.
    /// @param asset The address of the asset.
    /// @param feed The address of the feed to be removed.
    function removeAssetPriceFeed(address asset, address feed) external {
        _checkElevatedPermissions();
        _removeFeed(asset, feed);
    }

    function addMTokenSupport(address mToken) external {
        _checkElevatedPermissions();

        if (mTokenAssets[mToken].isMToken) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        mTokenAssets[mToken].isMToken = true;
        mTokenAssets[mToken].underlying = IMToken(mToken).underlying();
    }

    function removeMTokenSupport(address mToken) external {
        _checkElevatedPermissions();

        if (!mTokenAssets[mToken].isMToken) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        delete mTokenAssets[mToken];
    }

    function notifyFeedRemoval(address asset) external {
        if (!isApprovedAdaptor[msg.sender]) {
            revert PriceRouter__Unauthorized();
        }

        _removeFeed(asset, msg.sender);
    }

    /// @notice Adds a new approved adaptor.
    /// @dev Requires that the adaptor isn't already approved.
    /// @param _adaptor The address of the adaptor to approve.
    function addApprovedAdaptor(address _adaptor) external {
        _checkElevatedPermissions();

        if (isApprovedAdaptor[_adaptor]) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        isApprovedAdaptor[_adaptor] = true;
    }

    /// @notice Removes an approved adaptor.
    /// @dev Requires that the adaptor is currently approved.
    /// @param _adaptor The address of the adaptor to remove.
    function removeApprovedAdaptor(address _adaptor) external {
        _checkElevatedPermissions();

        if (!isApprovedAdaptor[_adaptor]) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        delete isApprovedAdaptor[_adaptor];
    }

    /// @notice Sets a new maximum divergence for price feeds.
    /// @dev Requires that the new divergence is greater than
    ///      or equal to 10200 aka 2% and less than or equal to 12000 aka 20%.
    /// @param maxDivergence The new maximum divergence.
    function setPriceFeedMaxDivergence(uint256 maxDivergence) external {
        _checkElevatedPermissions();

        if (maxDivergence < 10200 || maxDivergence > 12000) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        MAXIMUM_DIVERGENCE = maxDivergence;
    }

    /// @notice Sets a new maximum delay for Chainlink price feed.
    /// @dev Requires that the new delay is less than 1 day and more than 1 hour.
    ///      Only callable by the DaoManager.
    /// @param delay The new maximum delay in seconds.
    function setChainlinkDelay(uint256 delay) external {
        _checkElevatedPermissions();

        if (delay < 1 hours || delay > 1 days) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

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
        bool isMToken;
        if (mTokenAssets[asset].isMToken) {
            isMToken = mTokenAssets[asset].isMToken;
            asset = mTokenAssets[asset].underlying;
        }

        uint256 numFeeds = assetPriceFeeds[asset].length;
        if (numFeeds == 0) {
            _revert(NOT_SUPPORTED_SELECTOR);
        }

        FeedData[] memory data = new FeedData[](numFeeds * 2);

        // If the asset only has one price feed, we know itll be in
        // feed slot 0 so get both prices and return
        if (numFeeds < 2) {
            data[0] = _getPriceFromFeed(asset, 0, inUSD, true);
            data[1] = _getPriceFromFeed(asset, 0, inUSD, false);
            if (isMToken) {
                uint256 exchangeRate = IMToken(asset).exchangeRateCached();
                data[0].price = uint240((data[0].price * exchangeRate) / WAD);
                data[1].price = uint240((data[1].price * exchangeRate) / WAD);
            }

            return data;
        }

        // We know the asset has two price feeds, so get pricing from
        // both feeds and return
        data[0] = _getPriceFromFeed(asset, 0, inUSD, true);
        data[1] = _getPriceFromFeed(asset, 0, inUSD, false);
        data[2] = _getPriceFromFeed(asset, 1, inUSD, true);
        data[3] = _getPriceFromFeed(asset, 1, inUSD, false);

        if (isMToken) {
            uint256 exchangeRate = IMToken(asset).exchangeRateCached();
            data[0].price = uint240((data[0].price * exchangeRate) / WAD);
            data[1].price = uint240((data[1].price * exchangeRate) / WAD);
            data[2].price = uint240((data[2].price * exchangeRate) / WAD);
            data[3].price = uint240((data[3].price * exchangeRate) / WAD);
        }

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

    /// @notice Check whether sequencer is valid or down.
    /// @return True if sequencer is valid
    function isSequencerValid() external view returns (bool) {
        return _isSequencerValid();
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
        address mAsset;
        if (mTokenAssets[asset].isMToken) {
            mAsset = asset;
            asset = mTokenAssets[asset].underlying;
        }

        uint256 numFeeds = assetPriceFeeds[asset].length;
        if (numFeeds == 0) {
            _revert(NOT_SUPPORTED_SELECTOR);
        }

        if (numFeeds < 2) {
            (price, errorCode) = _getPriceSingleFeed(asset, inUSD, getLower);
        } else {
            (price, errorCode) = _getPriceDualFeed(asset, inUSD, getLower);
        }

        /// If somehow a feed returns a price of 0 make sure we trigger the BAD_SOURCE flag
        if (price == 0 && errorCode < BAD_SOURCE) {
            errorCode = BAD_SOURCE;
        }

        if (mAsset != address(0)) {
            uint256 exchangeRate = IMToken(mAsset).exchangeRateCached();
            price = (price * exchangeRate) / WAD;
        }
    }

    /// @notice Retrieves the prices of multiple assets.
    /// @param assets An array of asset addresses to retrieve the prices for.
    /// @param inUSD An array of bools indicating whether the price should be
    ///              returned in USD or ETH.
    /// @param getLower An array of bools indiciating whether the lower
    ///                 or higher price should be returned if two feeds are available.
    /// @return Two arrays. The first one contains prices for each asset,
    ///         and the second one contains corresponding error flags (if any).
    function getPrices(
        address[] calldata assets,
        bool[] calldata inUSD,
        bool[] calldata getLower
    ) external view returns (uint256[] memory, uint256[] memory) {
        uint256 numAssets = assets.length;
        if (numAssets == 0) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        if (numAssets != inUSD.length || numAssets != getLower.length) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

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

    /// @notice Retrieves the prices and account data of multiple assets inside a Curvance Market.
    /// @param account The account to retrieve data for.
    /// @param assets An array of asset addresses to retrieve the prices for.
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert.
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
        returns (AccountSnapshot[] memory, uint256[] memory, uint256)
    {
        uint256 numAssets = assets.length;
        if (numAssets == 0) {
            _revert(INVALID_PARAMETER_SELECTOR);
        }

        AccountSnapshot[] memory snapshots = new AccountSnapshot[](numAssets);
        uint256[] memory underlyingPrices = new uint256[](numAssets);
        uint256 hadError;

        for (uint256 i; i < numAssets; ) {
            snapshots[i] = assets[i].getSnapshotPacked(account);
            (underlyingPrices[i], hadError) = getPrice(
                assets[i].underlying(),
                true,
                snapshots[i].isCToken
            );

            if (hadError >= errorCodeBreakpoint) {
                _revert(ERROR_CODE_FLAGGED_SELECTOR);
            }

            unchecked {
                ++i;
            }
        }

        return (snapshots, underlyingPrices, numAssets);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Removes a price feed for a specific asset.
    /// @dev Requires that the feed exists for the asset.
    /// @param asset The address of the asset.
    /// @param feed The address of the feed to be removed.
    function _removeFeed(address asset, address feed) internal {
        uint256 numFeeds = assetPriceFeeds[asset].length;
        if (numFeeds == 0) {
            _revert(NOT_SUPPORTED_SELECTOR);
        }

        if (numFeeds > 1) {
            if (
                assetPriceFeeds[asset][0] != feed &&
                assetPriceFeeds[asset][1] != feed
            ) {
                _revert(NOT_SUPPORTED_SELECTOR);
            }

            // we want to remove the first feed of two,
            // so move the second feed to slot one
            if (assetPriceFeeds[asset][0] == feed) {
                assetPriceFeeds[asset][0] = assetPriceFeeds[asset][1];
            }
        } else {
            if (assetPriceFeeds[asset][0] != feed) {
                _revert(NOT_SUPPORTED_SELECTOR);
            }
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
    function _getPriceDualFeed(
        address asset,
        bool inUSD,
        bool getLower
    ) internal view returns (uint256, uint256) {
        FeedData memory feed0 = _getPriceFromFeed(asset, 0, inUSD, getLower);
        FeedData memory feed1 = _getPriceFromFeed(asset, 1, inUSD, getLower);

        // Check if we had any working price feeds,
        // if not we need to block any market operations
        if (feed0.hadError && feed1.hadError) return (0, BAD_SOURCE);

        // Check if we had an error in either price that should limit borrowing
        if (feed0.hadError || feed1.hadError) {
            return (_getWorkingPrice(feed0, feed1), CAUTION);
        }
        if (getLower) {
            return _calculateLowerPrice(feed0.price, feed1.price);
        }

        return _calculateHigherPrice(feed0.price, feed1.price);
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
    function _getPriceSingleFeed(
        address asset,
        bool inUSD,
        bool getLower
    ) internal view returns (uint256, uint256) {
        address adapter = assetPriceFeeds[asset][0];
        if (!isApprovedAdaptor[adapter]) {
            revert PriceRouter__AdaptorIsNotApproved();
        }

        PriceReturnData memory data = IOracleAdaptor(adapter).getPrice(
            asset,
            inUSD,
            getLower
        );
        if (data.hadError) {
            return (0, BAD_SOURCE);
        }

        if (data.inUSD != inUSD) {
            uint256 newPrice;
            (newPrice, data.hadError) = _getETHUSD();
            if (data.hadError) {
                return (0, BAD_SOURCE);
            }

            data.price = uint240(
                _convertETHUSD(data.price, newPrice, data.inUSD)
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
    function _getPriceFromFeed(
        address asset,
        uint256 feedNumber,
        bool inUSD,
        bool getLower
    ) internal view returns (FeedData memory) {
        address adapter = assetPriceFeeds[asset][feedNumber];
        if (!isApprovedAdaptor[adapter]) {
            revert PriceRouter__AdaptorIsNotApproved();
        }

        PriceReturnData memory data = IOracleAdaptor(adapter).getPrice(
            asset,
            inUSD,
            getLower
        );
        if (data.hadError) {
            return FeedData({ price: 0, hadError: true });
        }

        if (data.inUSD != inUSD) {
            uint256 newPrice;
            (newPrice, data.hadError) = _getETHUSD();
            if (data.hadError) {
                return FeedData({ price: 0, hadError: true });
            }

            data.price = uint240(
                _convertETHUSD(data.price, newPrice, data.inUSD)
            );
        }

        return FeedData({ price: data.price, hadError: data.hadError });
    }

    /// @notice Queries the current price of ETH in USD using Chainlink's ETH/USD feed.
    /// @dev The price is deemed valid if the data from Chainlink is fresh
    ///      and positive.
    /// @return A tuple containing the price of ETH in USD and an error flag.
    ///         If the Chainlink data is stale or negative,
    ///         it returns (answer, true).
    ///         Where true corresponded to hasError = true.
    function _getETHUSD() internal view returns (uint256, bool) {
        if (!_isSequencerValid()) {
            return (0, true);
        }

        (, int256 answer, , uint256 updatedAt, ) = IChainlink(
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

    /// @notice Check whether sequencer is valid or down.
    /// @return True if sequencer is valid
    function _isSequencerValid() internal view returns (bool) {
        address sequencer = centralRegistry.sequencer();

        if (sequencer != address(0)) {
            (, int256 answer, uint256 startedAt, , ) = IChainlink(sequencer)
                .latestRoundData();

            // Answer == 0: Sequencer is up
            // Check that the sequencer is up or the grace period has passed
            // after the sequencer is back up.
            if (
                answer != 0 || block.timestamp < startedAt + GRACE_PERIOD_TIME
            ) {
                return false;
            }
        }

        return true;
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
    function _convertETHUSD(
        uint240 currentPrice,
        uint256 conversionRate,
        bool currentFormatInUSD
    ) internal view returns (uint256) {
        if (!currentFormatInUSD) {
            // current format is in ETH and we want USD
            return (currentPrice * conversionRate) / CHAINLINK_DECIMALS;
        }

        return (currentPrice * CHAINLINK_DECIMALS) / conversionRate;
    }

    /// @notice Processes the price data from two different feeds.
    /// @dev Checks for divergence between two prices.
    ///      If the divergence is more than allowed, it returns (0, CAUTION).
    /// @param a The price from the first feed.
    /// @param b The price from the second feed.
    /// @return A tuple containing the lower of two prices and an error flag (if any).
    ///         If the prices are within acceptable range,
    ///         it returns (min(a,b), NO_ERROR).
    function _calculateLowerPrice(
        uint256 a,
        uint256 b
    ) internal view returns (uint256, uint256) {
        if (a <= b) {
            // Check if both feeds are within MAXIMUM_DIVERGENCE
            // of each other
            if (((a * MAXIMUM_DIVERGENCE) / DENOMINATOR) < b) {
                // Return the price but notify that the price should be taken with caution
                // because we are outside the accepted range of divergence
                return (a, CAUTION);
            }
            return (a, NO_ERROR);
        }

        // Check if both feeds are within MAXIMUM_DIVERGENCE
        // of each other
        if (((b * MAXIMUM_DIVERGENCE) / DENOMINATOR) < a) {
            // Return the price but notify that the price should be taken with caution
            // because we are outside the accepted range of divergence
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
    function _calculateHigherPrice(
        uint256 a,
        uint256 b
    ) internal view returns (uint256, uint256) {
        if (a >= b) {
            // Check if both feeds are within MAXIMUM_DIVERGENCE
            // of each other
            if (((b * MAXIMUM_DIVERGENCE) / DENOMINATOR) < a) {
                // Return the price but notify that the price should be taken with caution
                // because we are outside the accepted range of divergence
                return (a, CAUTION);
            }
            return (a, NO_ERROR);
        }

        // Check if both feeds are within MAXIMUM_DIVERGENCE
        // of each other
        if (((a * MAXIMUM_DIVERGENCE) / DENOMINATOR) < b) {
            // Return the price but notify that the price should be taken with caution
            // because we are outside the accepted range of divergence
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
    function _getWorkingPrice(
        FeedData memory feed0,
        FeedData memory feed1
    ) internal pure returns (uint256) {
        // We know based on context of when this function is called that one
        // but not both feeds have an error.
        // So if feed0 had the error, feed1 is okay, and vice versa
        if (feed0.hadError) return feed1.price;
        return feed0.price;
    }

    /// @notice Internal helper for reverting efficiently.
    /// @param s Selector to revert with.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            revert PriceRouter__Unauthorized();
        }
    }
}
