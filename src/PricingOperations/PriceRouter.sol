// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { CErc20Storage } from "@compound/CTokenInterfaces.sol";
import { CToken } from "@compound/CToken.sol";

// Curve imports
import { ICurvePool } from "src/interfaces/ICurvePool.sol";
import { ICurveToken } from "src/interfaces/ICurveToken.sol";

// Aave imports
import { IAaveToken } from "src/interfaces/IAaveToken.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Curvance Price Router
 * @notice Provides a universal interface allowing Sommelier contracts to retrieve secure pricing
 *         data from Chainlink.
 * @author crispymangoes
 */
contract PriceRouter is Ownable {
    using SafeERC20 for ERC20;
    using SafeCast for int256;
    using Math for uint256;

    event AddAsset(address indexed asset);
    event RemoveAsset(address indexed asset);

    enum PriceDerivative {
        CHAINLINK,
        CURVE,
        AAVE
    }

    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    // =========================================== ASSETS CONFIG ===========================================

    /**
     * @param minPrice minimum price in USD for the asset before reverting
     * @param maxPrice maximum price in USD for the asset before reverting
     * @param isPriceRangeInETH if true price range values are given in ETH, if false price range is given in USD
     * @param heartbeat maximum allowed time that can pass with no update before price data is considered stale
     * @param isSupported whether this asset is supported by the platform or not
     */
    struct AssetConfig {
        PriceDerivative priceDerivative;
        bytes settings;
        bool isSupported;
    }

    /**
     * @notice Get the asset data for a given asset.
     */
    mapping(address => AssetConfig) public getAssetConfig;

    uint256 public constant EXPECTED_ANSWER_DEVIATION = 0.02e18;

    // ======================================= ADAPTOR OPERATIONS =======================================

    /**
     * @notice Attempted to add an invalid asset.
     * @param asset address of the invalid asset
     */
    error PriceRouter__InvalidAsset(address asset);

    error PriceRouter__BadAnswer(uint256 answer, uint256 expectedAnswer);

    /**
     * @notice Add an asset for the price router to support.
     * @param asset address of asset to support on the platform
     * @param _priceDerivative defines what logic to use to price asset.
     * @param _settings bytes variable used to store any data price derivative needs to calculate a valid price.
     * @param expectedAnswerInUSD once asset has been set up, getValueInUSD is called,
     *                            and the resulting answer is compared against expectedAnswerInUSD
     *                            to help verify new asset has been set up properly.
     */
    function addAsset(
        address asset,
        PriceDerivative _priceDerivative,
        bytes memory _settings,
        uint256 expectedAnswerInUSD
    ) external onlyOwner {
        if (asset == address(0)) revert PriceRouter__InvalidAsset(address(asset));
        if (_priceDerivative == PriceDerivative.CHAINLINK) {
            _settings = _setupPriceForChainlinkDerivative(asset, _settings);
        } else if (_priceDerivative == PriceDerivative.CURVE) {
            _settings = _setupPriceForCurveDerivative(asset, _settings);
        }

        getAssetConfig[asset] = AssetConfig({
            priceDerivative: _priceDerivative,
            settings: _settings,
            isSupported: true
        });

        uint256 minAnswer = expectedAnswerInUSD.mulWadDown((1e18 - EXPECTED_ANSWER_DEVIATION));
        uint256 maxAnswer = expectedAnswerInUSD.mulWadDown((1e18 + EXPECTED_ANSWER_DEVIATION));

        uint256 answer = getValueInUSD(asset);

        if (answer < minAnswer || answer > maxAnswer) revert PriceRouter__BadAnswer(answer, expectedAnswerInUSD);

        // Confirm new asset does have a decimals method.
        ERC20(asset).decimals();

        emit AddAsset(asset);
    }

    // ======================================= PRICING OPERATIONS =======================================
    //TODO from compounds oracle
    /**
     * @notice Get the underlying price of a cToken, in the format expected by the Comptroller.
     * @dev Implements the PriceOracle interface for Compound v2.
     * @dev unlike compound oracle, this oracle does not assume stable coins are $1.
     * @param cToken The cToken address for price retrieval
     * @return price denominated in USD for the given cToken address, in the format expected by the Comptroller.
     */
    function getUnderlyingPrice(CToken cToken) external view returns (uint256 price) {
        address underlying = CErc20Storage(address(cToken)).underlying();
        // Comptroller wants price with 6 decimals of precision.
        price = getValueInUSD(underlying).changeDecimals(8, 36 - ERC20(underlying).decimals());
    }

    // =========================================== HELPER FUNCTIONS ===========================================

    /**
     * @notice Gets the exchange rate between a base and a quote asset
     * @param baseAsset the asset to convert into quoteAsset
     * @param quoteAsset the asset base asset is converted into
     * @return exchangeRate value of base asset in terms of quote asset
     */
    function _getExchangeRate(
        address baseAsset,
        address quoteAsset,
        uint8 quoteAssetDecimals
    ) internal view returns (uint256 exchangeRate) {
        exchangeRate = getValueInUSD(baseAsset).mulDivDown(10**quoteAssetDecimals, getValueInUSD(quoteAsset));
    }

    /**
     * @notice Attempted to update the asset to one that is not supported by the platform.
     * @param asset address of the unsupported asset
     */
    error PriceRouter__UnsupportedAsset(address asset);

    /**
     * @notice Attempted an operation to price an asset that under its minimum valid price.
     * @param asset address of the asset that is under its minimum valid price
     * @param price price of the asset
     * @param minPrice minimum valid price of the asset
     */
    error PriceRouter__AssetBelowMinPrice(address asset, uint256 price, uint256 minPrice);

    /**
     * @notice Attempted an operation to price an asset that under its maximum valid price.
     * @param asset address of the asset that is under its maximum valid price
     * @param price price of the asset
     * @param maxPrice maximum valid price of the asset
     */
    error PriceRouter__AssetAboveMaxPrice(address asset, uint256 price, uint256 maxPrice);

    /**
     * @notice Attempted to fetch a price for an asset that has not been updated in too long.
     * @param asset address of the asset thats price is stale
     * @param timeSinceLastUpdate seconds since the last price update
     * @param heartbeat maximum allowed time between price updates
     */
    error PriceRouter__StalePrice(address asset, uint256 timeSinceLastUpdate, uint256 heartbeat);

    /**
     * @notice Gets the valuation of some asset in USD
     * @dev USD valuation has 8 decimals
     * @param asset the asset to get the value of in USD
     * @return value the value of asset in USD
     */
    function getValueInUSD(address asset) public view returns (uint256 value) {
        AssetConfig memory config = getAssetConfig[asset];
        if (!config.isSupported) revert PriceRouter__UnsupportedAsset(address(asset));

        value = _getValueInUSD(address(asset), config);
    }

    /**
     * @notice Interacts with Chainlink feed registry and first tries to get `asset` price in USD,
     *         if that fails, then it tries to get `asset` price in ETH, and then converts the answer into USD.
     * @param asset the ERC20 token to get the price of.
     * @return price the price of `asset` in USD
     */
    function _getValueInUSD(address asset, AssetConfig memory config) internal view returns (uint256 price) {
        bytes memory settings = config.settings;
        if (config.priceDerivative == PriceDerivative.CHAINLINK) {
            price = _getPriceForChainlinkDerivative(asset, settings);
        } else if (config.priceDerivative == PriceDerivative.CURVE) {
            price = _getPriceForCurveDerivative(asset, settings);
        } else if (config.priceDerivative == PriceDerivative.AAVE) {
            price = _getPriceForAaveDerivative(asset, settings);
        }
    }

    // =========================================== CHAINLINK PRICE DERIVATIVE ==========================================
    /**
     * @notice Feed Registry contract used to get chainlink data feeds.
     */
    FeedRegistryInterface public constant feedRegistry =
        FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    function _remap(address asset) internal pure returns (address) {
        if (asset == WETH) return Denominations.ETH;
        if (asset == WBTC) return Denominations.BTC;
        return asset;
    }

    /**
     * @notice Attempted to set a minimum price below the Chainlink minimum price (with buffer).
     * @param minPrice minimum price attempted to set
     * @param bufferedMinPrice minimum price that can be set including buffer
     */
    error PriceRouter__InvalidMinPrice(uint256 minPrice, uint256 bufferedMinPrice);

    /**
     * @notice Attempted to set a maximum price above the Chainlink maximum price (with buffer).
     * @param maxPrice maximum price attempted to set
     * @param bufferedMaxPrice maximum price that can be set including buffer
     */
    error PriceRouter__InvalidMaxPrice(uint256 maxPrice, uint256 bufferedMaxPrice);

    /**
     * @notice Attempted to add an asset with a certain price range denomination, but actual denomination was different.
     * @param expected price range denomination
     * @param actual price range denomination
     * @dev If an asset has price feeds in USD and ETH, the feed in USD is favored
     */
    error PriceRouter__PriceRangeDenominationMisMatch(bool expected, bool actual);

    /**
     * @notice Attempted to add an asset with invalid min/max prices.
     * @param min price
     * @param max price
     */
    error PriceRouter__MinPriceGreaterThanMaxPrice(uint256 min, uint256 max);

    uint96 public constant DEFAULT_HEART_BEAT = 1 days;

    function _setupPriceForChainlinkDerivative(address asset, bytes memory settings)
        internal
        view
        returns (bytes memory)
    {
        (uint256 minPrice, uint256 maxPrice, bool rangeInETH, uint96 heartbeat) = abi.decode(
            settings,
            (uint256, uint256, bool, uint96)
        );
        // Use Chainlink to get the min and max of the asset.
        address assetToQuery = _remap(asset);
        (uint256 minFromChainklink, uint256 maxFromChainlink, bool isETH) = _getPriceRange(assetToQuery);

        // Check if callers expected price range  denomination matches actual.
        if (rangeInETH != isETH) revert PriceRouter__PriceRangeDenominationMisMatch(rangeInETH, isETH);

        // Add a ~10% buffer to minimum and maximum price from Chainlink because Chainlink can stop updating
        // its price before/above the min/max price.
        uint256 bufferedMinPrice = minFromChainklink.mulWadDown(1.1e18);
        uint256 bufferedMaxPrice = maxFromChainlink.mulWadDown(0.9e18);

        if (minPrice == 0) {
            minPrice = bufferedMinPrice;
        } else {
            if (minPrice < bufferedMinPrice) revert PriceRouter__InvalidMinPrice(minPrice, bufferedMinPrice);
        }

        if (maxPrice == 0) {
            maxPrice = bufferedMaxPrice;
        } else {
            if (maxPrice > bufferedMaxPrice) revert PriceRouter__InvalidMaxPrice(maxPrice, bufferedMaxPrice);
        }

        if (minPrice >= maxPrice) revert PriceRouter__MinPriceGreaterThanMaxPrice(minPrice, maxPrice);

        heartbeat = heartbeat != 0 ? heartbeat : DEFAULT_HEART_BEAT;

        return abi.encode(minPrice, maxPrice, rangeInETH, heartbeat);
    }

    function _getPriceForChainlinkDerivative(address asset, bytes memory settings)
        internal
        view
        returns (uint256 price)
    {
        // Remap asset if need be.
        asset = _remap(asset);

        (, , bool rangeInETH, ) = abi.decode(settings, (uint256, uint256, bool, uint96));

        if (!rangeInETH) {
            // Price feed is in USD.
            (, int256 _price, , uint256 _timestamp, ) = feedRegistry.latestRoundData(address(asset), Denominations.USD);
            price = _price.toUint256();
            _checkPriceFeed(asset, price, _timestamp, settings);
        } else {
            // Price feed is in ETH.
            (, int256 _price, , uint256 _timestamp, ) = feedRegistry.latestRoundData(address(asset), Denominations.ETH);
            price = _price.toUint256();
            _checkPriceFeed(asset, price, _timestamp, settings);

            // Convert price from ETH to USD.
            price = _price.toUint256().mulWadDown(_getExchangeRateFromETHToUSD());
        }
    }

    /**
     * @notice Could not find an asset's price range in USD or ETH.
     * @param asset address of the asset
     */
    error PriceRouter__PriceRangeNotAvailable(address asset);

    /**
     * @notice Interacts with Chainlink feed registry and first tries to get `asset` price range in USD,
     *         if that fails, then it tries to get `asset` price range in ETH, and then converts the range into USD.
     * @param asset the ERC20 token to get the price range of.
     * @return min the minimum price where Chainlink nodes stop updating the oracle
     * @return max the maximum price where Chainlink nodes stop updating the oracle
     */
    function _getPriceRange(address asset)
        internal
        view
        returns (
            uint256 min,
            uint256 max,
            bool isETH
        )
    {
        try feedRegistry.getFeed(address(asset), Denominations.USD) returns (AggregatorV2V3Interface aggregator) {
            IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

            min = uint256(uint192(chainlinkAggregator.minAnswer()));
            max = uint256(uint192(chainlinkAggregator.maxAnswer()));
            isETH = false;
        } catch {
            // If we can't find the USD price, then try the ETH price.
            try feedRegistry.getFeed(address(asset), Denominations.ETH) returns (AggregatorV2V3Interface aggregator) {
                IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

                min = uint256(uint192(chainlinkAggregator.minAnswer()));
                max = uint256(uint192(chainlinkAggregator.maxAnswer()));
                isETH = true;
            } catch {
                revert PriceRouter__PriceRangeNotAvailable(address(asset));
            }
        }
    }

    /**
     * @notice helper function to grab pricing data for ETH in USD
     * @return exchangeRate the exchange rate for ETH in terms of USD
     * @dev It is inefficient to re-calculate _checkPriceFeed for ETH -> USD multiple times for a single TX,
     * but this is done in the explicit way because it is simpler and less prone to logic errors.
     */
    function _getExchangeRateFromETHToUSD() internal view returns (uint256 exchangeRate) {
        (, int256 _price, , uint256 _timestamp, ) = feedRegistry.latestRoundData(Denominations.ETH, Denominations.USD);
        exchangeRate = _price.toUint256();
        _checkPriceFeed(WETH, exchangeRate, _timestamp, getAssetConfig[WETH].settings);
    }

    /**
     * @notice helper function to validate a price feed is safe to use.
     * @param asset ERC20 asset price feed data is for.
     * @param value the price value the price feed gave.
     * @param timestamp the last timestamp the price feed was updated.
     * @param settings abi encoded bytes storing settings for Chainlink derivative asset.
     */
    function _checkPriceFeed(
        address asset,
        uint256 value,
        uint256 timestamp,
        bytes memory settings
    ) internal view {
        (uint256 minPrice, uint256 maxPrice, , uint96 heartbeat) = abi.decode(
            settings,
            (uint256, uint256, bool, uint96)
        );
        if (value < minPrice) revert PriceRouter__AssetBelowMinPrice(asset, value, minPrice);

        if (value > maxPrice) revert PriceRouter__AssetAboveMaxPrice(asset, value, maxPrice);

        uint256 timeSinceLastUpdate = block.timestamp - timestamp;
        if (timeSinceLastUpdate > heartbeat) revert PriceRouter__StalePrice(asset, timeSinceLastUpdate, heartbeat);
    }

    // =========================================== CURVE PRICE DERIVATIVE ===========================================

    function _setupPriceForCurveDerivative(address asset, bytes memory settings) internal view returns (bytes memory) {
        address curvePool = abi.decode(settings, (address));

        try ICurveToken(asset).minter() returns (address _pool) {
            if (curvePool != _pool) revert("Wrong pool");
        } catch {} // Do nothing

        ICurvePool pool = ICurvePool(curvePool);
        uint256 coinsLength = 0;
        while (true) {
            try pool.coins(coinsLength) {
                coinsLength++;
            } catch {
                break;
            }
        }
        address[] memory coins = new address[](coinsLength);
        for (uint256 i = 0; i < coinsLength; i++) {
            coins[i] = pool.coins(i);
        }

        return abi.encode(curvePool, coins);
    }

    //TODO this assumes Curve pools NEVER add or remove tokens
    function _getPriceForCurveDerivative(address asset, bytes memory settings) internal view returns (uint256 price) {
        (address curvePool, address[] memory coins) = abi.decode(settings, (address, address[]));

        ICurvePool pool = ICurvePool(curvePool);
        uint256 minPrice = type(uint256).max;
        for (uint256 i = 0; i < coins.length; i++) {
            uint256 tokenPrice = getValueInUSD(coins[i]);
            if (tokenPrice < minPrice) minPrice = tokenPrice;
        }

        if (minPrice == type(uint256).max) revert("Min price not found.");

        // Virtual price is based off the Curve Token decimals.
        uint256 curveTokenDecimals = ERC20(asset).decimals();
        price = minPrice.mulDivDown(pool.get_virtual_price(), 10**curveTokenDecimals);
    }

    // =========================================== AAVE PRICE DERIVATIVE ===========================================

    error PriceRouter__WrongUnderlying(address actual, address expected);

    function _setupPriceForAaveDerivative(address asset, bytes memory settings) internal view returns (bytes memory) {
        address underlying = abi.decode(settings, (address));

        address actual = IAaveToken(asset).UNDERLYING_ASSET_ADDRESS();
        if (actual != underlying) revert PriceRouter__WrongUnderlying(actual, underlying);

        return settings;
    }

    function _getPriceForAaveDerivative(address asset, bytes memory settings) internal view returns (uint256 price) {
        address underlying = abi.decode(settings, (address));
        price = getValueInUSD(underlying);
    }

    // =========================================== COMPOUND PRICE DERIVATIVE ===========================================

    // Basically just needs to unwrap it.
    function _setupPriceForCompoundDerivative(address asset, bytes memory settings)
        internal
        view
        returns (bytes memory)
    {}

    function _getPriceForCompoundDerivative(address asset, bytes memory settings)
        internal
        view
        returns (uint256 price)
    {}
}
