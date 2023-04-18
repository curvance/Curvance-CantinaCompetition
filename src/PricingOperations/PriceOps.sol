// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeTransferLib } from "src/base/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IExtension } from "./IExtension.sol";
import { OracleLibrary } from "lib/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { UniswapV3Pool } from "src/interfaces/Uniswap/UniswapV3Pool.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Curvance Pricing Operations
 * @notice Provides a universal interface allowing Curvance contracts to retrieve secure pricing
 *         data based of Chainlink data feeds, and Uniswap V3 TWAPS.
 * @author crispymangoes
 */
//  TODO so if the failure method is a slow failure like stale prices, or low liquidity in a TWAP, then it should return an error
// TODO but if failure method is a fast one like VP manipualtion it should revert.
contract PriceOps is Ownable {
    using SafeTransferLib for ERC20;
    using SafeCast for int256;
    using Math for uint256;
    using Address for address;

    event AddAsset(address indexed asset);

    // =========================================== ASSETS CONFIG ===========================================

    enum Descriptor {
        NONE,
        CHAINLINK,
        UNIV3_TWAP,
        EXTENSION
    }

    /**
     * @notice Bare minimum settings all derivatives support.
     * @param descriptor the uint8 id used to describe this asset
     * @param source the address used to price the asset
     */
    struct AssetSourceSettings {
        address asset;
        Descriptor descriptor;
        address source;
    }

    uint64 public sourceCount;
    mapping(uint64 => AssetSourceSettings) public getAssetSourceSettings;

    // So this is what is used to query assets
    struct AssetSettings {
        uint64 primarySource;
        uint64 secondarySource;
    }

    /**
     * @notice Mapping between an asset to price and its `AssetSettings`.
     */
    mapping(address => AssetSettings) public getAssetSettings;

    mapping(address => bool) public isExtension;

    /**
     * @notice Stores pricing information during calls.
     * @param asset the address of the asset
     * @param price the USD price of the asset
     * @dev If the price does not fit into a uint96, the asset is NOT added to the cache.
     */
    struct PriceCache {
        uint64 sourceId;
        uint96 upper;
        uint96 lower;
    }

    /**
     * @notice The size of the price cache. A larger cache can hold more values,
     *         but incurs a larger gas cost overhead. A smaller cache has a
     *         smaller gas overhead but caches less prices.
     */
    uint8 private constant PRICE_CACHE_SIZE = 2;

    // ======================================= NEW FUNCTIONS =======================================
    address public constant USD = address(840);
    address public constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    constructor(bytes memory parameters) {
        // Save the USD-ETH price feed because it is a widely used pricing path.
        uint64 sourceId = _addSource(USD, Descriptor.CHAINLINK, ETH_USD_FEED, parameters);
        _addAsset(USD, sourceId, 0);
    }

    // TODO so one of the sources failing is the same as price diverging.
    function getPriceInBaseEnforceNonZeroLower(
        address asset
    ) external view returns (uint256 upper, uint256 lower, uint8 errorCode) {
        (upper, lower, errorCode) = _getPriceInBase(asset);

        if (lower == 0) lower = upper;
    }

    function getPriceInBase(address asset) external view returns (uint256, uint256, uint8) {
        if (!isExtension[msg.sender]) revert("Caller is not an extension.");
        return _getPriceInBase(asset);
    }

    uint8 public constant ANCHOR_OUT_OF_RANGE = 3;

    function _getPriceInBase(address asset) internal view returns (uint256, uint256, uint8) {
        // If mode is anchor, then run an anchor check anchoring primary upper to secondary upper, and the same for lower
        AssetSettings memory settings = getAssetSettings[asset];

        uint256 primarySourceUpper;
        uint256 primarySourceLower;
        uint256 secondarySourceUpper;
        uint256 secondarySourceLower;
        uint8 errorCode;
        // TODO need to look at error code
        // If primary has error use secondary
        // if secondary is set and has error use primary, but set anchor OOR
        // IF both return no errors, but values differ greatly set anchor OOR
        //  - I guess we would do the same lower upper logic?

        // TODO so if there is only 1

        // Make sure primary is good, and returning non-zero. If either fail revert.
        (primarySourceUpper, primarySourceLower, errorCode) = _getPriceFromSource(settings.primarySource);
        // If primary source is returning a zero for price, then revert
        if (primarySourceUpper == 0) revert("Bad primary");
        if (settings.secondarySource == 0) {
            // Secondary not set.
            return (primarySourceUpper, primarySourceLower, errorCode);
        }
        (secondarySourceUpper, secondarySourceLower, errorCode) = _getPriceFromSource(settings.secondarySource);
        // If secondary source is returning a zero for price, then revert
        if (secondarySourceUpper == 0) revert("Bad secondary");

        if (secondarySourceUpper > 0) {
            // TODO Make sure primary and secondary do not differ greatly.
        }

        // First find upper.
        uint256 upper = primarySourceUpper > secondarySourceUpper ? primarySourceUpper : secondarySourceUpper;
        uint256 lower;

        // Now find lower.
        if (primarySourceLower == 0 && secondarySourceLower == 0) {
            // Use the smaller upper value.
            lower = primarySourceUpper < secondarySourceUpper ? primarySourceUpper : secondarySourceUpper;
        } else {
            if (primarySourceLower != 0 && secondarySourceLower != 0) {
                // Use the smaller lower value.
                lower = primarySourceLower < secondarySourceLower ? primarySourceLower : secondarySourceLower;
            } else {
                // Else compare non zero lower to smaller upper.
                uint256 smallerUpper = primarySourceUpper.min(secondarySourceUpper);
                if (primarySourceLower != 0)
                    lower = primarySourceLower < smallerUpper ? primarySourceLower : smallerUpper;
                else lower = secondarySourceLower < smallerUpper ? secondarySourceLower : smallerUpper;
            }
        }
        return (upper, lower, errorCode);
    }

    function _getPriceFromSource(
        uint64 sourceId
    ) internal view returns (uint256 upper, uint256 lower, uint8 errorCode) {
        AssetSourceSettings memory settings = getAssetSourceSettings[sourceId];
        // Note sources CAN return an upper and lower, but a lot of them will only return an upper.
        // Like if we had a TWAP for GEAR/USDC then when we price USDC, that could use CL USDC->USD and TWAP USDC->ETH then CL ETH->USD
        if (settings.descriptor == Descriptor.CHAINLINK) {
            (upper, lower, errorCode) = _getPriceInBaseForChainlinkAsset(sourceId, settings.source);
        } else if (settings.descriptor == Descriptor.UNIV3_TWAP) {
            (upper, lower, errorCode) = _getPriceInBaseForTwapAsset(sourceId, settings.source);
        } else if (settings.descriptor == Descriptor.EXTENSION) {
            (upper, lower, errorCode) = IExtension(settings.source).getPriceInBase(sourceId);
        } else revert("Unkown");
    }

    function addSource(
        address asset,
        Descriptor descriptor,
        address source,
        bytes memory sourceData
    ) external onlyOwner returns (uint64 sourceId) {
        sourceId = _addSource(asset, descriptor, source, sourceData);
    }

    function _addSource(
        address asset,
        Descriptor descriptor,
        address source,
        bytes memory sourceData
    ) internal returns (uint64 sourceId) {
        // Supports Chainlink Assets, UniV3 TWAPS, and Extension contracts. All of these are able to call `getPriceInBase`
        sourceId = ++sourceCount;

        uint256 upper;
        uint256 lower;
        uint8 errorCode;

        if (descriptor == Descriptor.CHAINLINK) {
            _setupAssetForChainlinkSource(sourceId, source, sourceData);
            (upper, lower, errorCode) = _getPriceInBaseForChainlinkAsset(sourceId, source);
        } else if (descriptor == Descriptor.UNIV3_TWAP) {
            _setupAssetForTwapSource(sourceId, source, sourceData);
            (upper, lower, errorCode) = _getPriceInBaseForTwapAsset(sourceId, source);
        } else if (descriptor == Descriptor.EXTENSION) {
            if (!isExtension[source]) isExtension[source] = true;
            IExtension(source).setupSource(asset, sourceId, sourceData);
            (upper, lower, errorCode) = IExtension(source).getPriceInBase(sourceId);
        }

        // TODO errorCode should be zero.

        getAssetSourceSettings[sourceId] = AssetSourceSettings({
            asset: asset,
            descriptor: descriptor,
            source: source
        });
    }

    function addAsset(address asset, uint64 primarySource, uint64 secondarySource) external onlyOwner {
        // Check if asset is already setup.
        // TODO primary source can not be 0

        // make sure sources are valid, and for the right asset.

        _addAsset(asset, primarySource, secondarySource);
    }

    function _addAsset(address asset, uint64 primarySource, uint64 secondarySource) internal {
        // Check if asset is already setup.
        // TODO primary source can not be 0

        // make sure sources are valid, and for the right asset.

        getAssetSettings[asset] = AssetSettings({ primarySource: primarySource, secondarySource: secondarySource });
    }

    function editAsset() external onlyOwner {
        // This needs to be a higher privelage function, so maybe timelock edits to it?
    }

    /**
     * @notice return bool indicating whether or not an asset has been set up.
     * @dev Since `addAsset` enforces the derivative is non zero, checking if the stored setting
     *      is nonzero is sufficient to see if the asset is set up.
     */
    function isSupported(address asset) external view returns (bool) {
        return getAssetSettings[asset].primarySource > 0;
    }

    // ======================================= PRICING OPERATIONS =======================================

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
     * @notice Attempted to add an invalid asset.
     * @param asset address of the invalid asset
     */
    error PriceRouter__InvalidAsset(address asset);

    /**
     * @notice Attempted to add an asset, but actual answer was outside range of expectedAnswer.
     */
    error PriceRouter__BadAnswer(uint256 answer, uint256 expectedAnswer);

    /**
     * @notice Attempted to perform an operation using an unkown derivative.
     */
    error PriceRouter__UnkownDerivative(uint8 unkownDerivative);

    /**
     * @notice Attempted to add an asset with invalid min/max prices.
     * @param min price
     * @param max price
     */
    error PriceRouter__MinPriceGreaterThanMaxPrice(uint256 min, uint256 max);

    /**
     * @notice The allowed deviation between the expected answer vs the actual answer.
     */
    uint256 public constant EXPECTED_ANSWER_DEVIATION = 0.02e18;

    // ======================================= PRICING OPERATIONS =======================================
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // =========================================== CHAINLINK PRICE SOURCE ===========================================\
    /**
     * @notice Stores data for Chainlink source assets.
     * @param max the max valid price of the asset
     * @param min the min valid price of the asset
     * @param heartbeat the max amount of time between price updates
     * @param inUsd bool indicating whether the price feed is
     *        denominated in USD(true) or ETH(false)
     */
    struct ChainlinkSourceStorage {
        uint144 max;
        uint80 min;
        uint24 heartbeat;
        bool inUsd;
    }
    /**
     * @notice Returns Chainlink Derivative Storage
     */
    mapping(uint64 => ChainlinkSourceStorage) public getChainlinkSourceStorage;

    /**
     * @notice If zero is specified for a Chainlink asset heartbeat, this value is used instead.
     */
    uint24 public constant DEFAULT_HEART_BEAT = 1 days;

    /**
     * @notice Setup function for pricing Chainlink derivative assets.
     * @dev _source The address of the Chainlink Data feed.
     * @dev _storage A ChainlinkDerivativeStorage value defining valid prices.
     */
    function _setupAssetForChainlinkSource(uint64 _sourceId, address _source, bytes memory _storage) internal {
        ChainlinkSourceStorage memory parameters = abi.decode(_storage, (ChainlinkSourceStorage));

        // Use Chainlink to get the min and max of the asset.
        IChainlinkAggregator aggregator = IChainlinkAggregator(IChainlinkAggregator(_source).aggregator());
        uint256 minFromChainklink = uint256(uint192(aggregator.minAnswer()));
        uint256 maxFromChainlink = uint256(uint192(aggregator.maxAnswer()));

        // Add a ~10% buffer to minimum and maximum price from Chainlink because Chainlink can stop updating
        // its price before/above the min/max price.
        uint256 bufferedMinPrice = (minFromChainklink * 1.1e18) / 1e18;
        uint256 bufferedMaxPrice = (maxFromChainlink * 0.9e18) / 1e18;

        if (parameters.min == 0) {
            // Revert if bufferedMinPrice overflows because uint80 is too small to hold the minimum price,
            // and lowering it to uint80 is not safe because the price feed can stop being updated before
            // it actually gets to that lower price.
            if (bufferedMinPrice > type(uint80).max) revert("Buffered Min Overflow");
            parameters.min = uint80(bufferedMinPrice);
        } else {
            if (parameters.min < bufferedMinPrice)
                revert PriceRouter__InvalidMinPrice(parameters.min, bufferedMinPrice);
        }

        if (parameters.max == 0) {
            //Do not revert even if bufferedMaxPrice is greater than uint144, because lowering it to uint144 max is more conservative.
            parameters.max = bufferedMaxPrice > type(uint144).max ? type(uint144).max : uint144(bufferedMaxPrice);
        } else {
            if (parameters.max > bufferedMaxPrice)
                revert PriceRouter__InvalidMaxPrice(parameters.max, bufferedMaxPrice);
        }

        if (parameters.min >= parameters.max)
            revert PriceRouter__MinPriceGreaterThanMaxPrice(parameters.min, parameters.max);

        parameters.heartbeat = parameters.heartbeat != 0 ? parameters.heartbeat : DEFAULT_HEART_BEAT;

        getChainlinkSourceStorage[_sourceId] = parameters;
    }

    /**
     * @notice Get the price of a Chainlink derivative in terms of BASE.
     */
    function _getPriceInBaseForChainlinkAsset(
        uint64 _sourceId,
        address _source
    ) internal view returns (uint256 upper, uint256 lower, uint8 errorCode) {
        ChainlinkSourceStorage memory parameters = getChainlinkSourceStorage[_sourceId];
        IChainlinkAggregator aggregator = IChainlinkAggregator(_source);
        (, int256 _price, , uint256 updatedAt, ) = aggregator.latestRoundData();
        uint256 price = _price.toUint256();
        errorCode = _checkPriceFeed(price, updatedAt, parameters.max, parameters.min, parameters.heartbeat);
        if (_sourceId == 1) {
            // Trying to price ETH to USD, but need to invert price.
            upper = uint256(1e18).mulDivDown(1e8, price);
        } else {
            // If price is in Usd, convert to ETH.
            if (parameters.inUsd) {
                (uint256 _baseToEthUpper, uint256 _baseToEthLower, uint8 _errorCode) = _getPriceInBase(USD);
                upper = price.mulDivDown(_baseToEthUpper, 1e8);
                if (_baseToEthLower > 0) lower = price.mulDivDown(_baseToEthLower, 1e8);
            } else {
                upper = price;
                // lower is not set.
            }
        }
    }

    /**
     * @notice Attempted an operation to price an asset that under its minimum valid price.
     * @param sourceId address of the asset that is under its minimum valid price
     * @param price price of the asset
     * @param minPrice minimum valid price of the asset
     */
    error PriceRouter__AssetBelowMinPrice(uint64 sourceId, uint256 price, uint256 minPrice);

    /**
     * @notice Attempted an operation to price an asset that under its maximum valid price.
     * @param sourceId address of the asset that is under its maximum valid price
     * @param price price of the asset
     * @param maxPrice maximum valid price of the asset
     */
    error PriceRouter__AssetAboveMaxPrice(uint64 sourceId, uint256 price, uint256 maxPrice);

    /**
     * @notice Attempted to fetch a price for an asset that has not been updated in too long.
     * @param sourceId address of the asset thats price is stale
     * @param timeSinceLastUpdate seconds since the last price update
     * @param heartbeat maximum allowed time between price updates
     */
    error PriceRouter__StalePrice(uint64 sourceId, uint256 timeSinceLastUpdate, uint256 heartbeat);

    uint8 public constant SOURCE_INVALID = 1;

    uint8 public constant NO_ERROR = 0;

    /**
     * @notice helper function to validate a price feed is safe to use.
     * @param value the price value the price feed gave.
     * @param timestamp the last timestamp the price feed was updated.
     * @param max the upper price bound
     * @param min the lower price bound
     * @param heartbeat the max amount of time between price updates
     */
    function _checkPriceFeed(
        uint256 value,
        uint256 timestamp,
        uint144 max,
        uint88 min,
        uint24 heartbeat
    ) internal view returns (uint8) {
        if (value < min) return SOURCE_INVALID;

        if (value > max) return SOURCE_INVALID;

        uint256 timeSinceLastUpdate = block.timestamp - timestamp;
        if (timeSinceLastUpdate > heartbeat) return SOURCE_INVALID;

        return NO_ERROR;
    }

    // =========================================== TWAP PRICE SOURCE ===========================================
    struct TwapSourceStorage {
        uint32 secondsAgo;
        uint8 baseDecimals;
        address baseToken;
        address quoteToken;
    }

    /**
     * @notice TWAP Source Storage
     */
    mapping(uint64 => TwapSourceStorage) public getTwapSourceStorage;

    /**
     * @notice Setup function for pricing TWAP source assets.
     * @dev _source The address of the aToken.
     * @dev _storage is not used.
     */
    function _setupAssetForTwapSource(uint64 sourceId, address _source, bytes memory _storage) internal {
        TwapSourceStorage memory parameters = abi.decode(_storage, (TwapSourceStorage));

        UniswapV3Pool pool = UniswapV3Pool(_source);

        pool.token0();

        // Verify seconds ago is reasonable
        // Also if I add in asset to this I could do a sanity check to make sure asset is token0 or token1

        getTwapSourceStorage[sourceId] = parameters;
    }

    /**
     * @notice Get the price of an Aave derivative in terms of USD.
     */
    function _getPriceInBaseForTwapAsset(
        uint64 sourceId,
        address source
    ) internal view returns (uint256 upper, uint256 lower, uint8 errorCode) {
        TwapSourceStorage memory parameters = getTwapSourceStorage[sourceId];
        (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = OracleLibrary.consult(
            source,
            parameters.secondsAgo
        );
        // Get the amount of quote token each base token is worth.
        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(10 ** parameters.baseDecimals),
            parameters.baseToken,
            parameters.quoteToken
        );

        if (parameters.quoteToken != WETH) {
            (uint256 _quoteToBaseUpper, uint256 _quoteToBaseLower, uint8 _errorCode) = _getPriceInBase(
                parameters.quoteToken
            );
            upper = quoteAmount.mulWadDown(_quoteToBaseUpper);
            if (_quoteToBaseLower > 0) lower = quoteAmount.mulWadDown(_quoteToBaseLower);
            if (_errorCode > 0) errorCode = _errorCode;
        } else {
            // Price is already given in base.
            upper = quoteAmount;
        }
        // TODO run liquidity check, set error code if liquidity is bad
        console.log("Harmonic Mean Liquidity", harmonicMeanLiquidity);
    }
}
