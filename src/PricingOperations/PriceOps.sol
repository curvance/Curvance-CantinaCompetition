// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeTransferLib } from "src/base/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IExtension } from "./IExtension.sol";

/**
 * @title Curvance Pricing Operations
 * @notice Provides a universal interface allowing Curvance contracts to retrieve secure pricing
 *         data based of Chainlink data feeds, and Uniswap V3 TWAPS.
 * @author crispymangoes
 */
contract PriceOps is Ownable, AutomationCompatibleInterface {
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
    // TODO so this function would pass in an empty price cache
    // So are arrays from external calls copied into memory? Check this in playground and see how expensive it is.
    function getPriceInBaseEnforceNonZeroLower(address asset) external view returns (uint256 upper, uint256 lower) {
        (upper, lower) = getPriceInBase(asset);

        if (lower == 0) revert("Asset never uses 2 sources for DUAL oracles.");
    }

    mapping(uint64 => bool) public sourceCircuitBreaker;

    // So this just queries the up to(two sources), then reports the higher upper, and lower lower.
    // uint96 lower
    // TODO could add price cache in here
    // TODO this could revert if caller is not an extension or address this.
    function getPriceInBase(address asset) public view returns (uint256, uint256) {
        // If mode is anchor, then run an anchor check anchoring primary upper to secondary upper, and the same for lower
        AssetSettings memory settings = getAssetSettings[asset];

        uint256 primarySourceUpper;
        uint256 primarySourceLower;
        uint256 secondarySourceUpper;
        uint256 secondarySourceLower;

        // Make sure primary is good, and returning non-zero. If either fail revert.
        if (!sourceCircuitBreaker[settings.primarySource]) {
            (primarySourceUpper, primarySourceLower) = _getPriceFromSource(settings.primarySource);
            // If primary source is returning a zero for price, then revert
            if (primarySourceUpper == 0) revert("Bad primary");
        } else revert("Primary ciruit breaker");
        if (settings.secondarySource == 0) {
            // Secondary not set.
            return (primarySourceUpper, primarySourceLower);
        }
        if (!sourceCircuitBreaker[settings.secondarySource]) {
            (secondarySourceUpper, secondarySourceLower) = _getPriceFromSource(settings.secondarySource);
            // If secondary source is returning a zero for price, then revert
            if (secondarySourceUpper == 0) revert("Bad secondary");
        } else revert("Secondary ciruit breaker");

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
        return (upper, lower);
    }

    function _getPriceFromSource(uint64 sourceId) internal view returns (uint256 upper, uint256 lower) {
        AssetSourceSettings memory settings = getAssetSourceSettings[sourceId];
        // Note sources CAN return an upper and lower, but a lot of them will only return an upper.
        // Like if we had a TWAP for GEAR/USDC then when we price USDC, that could use CL USDC->USD and TWAP USDC->ETH then CL ETH->USD
        if (settings.descriptor == Descriptor.CHAINLINK) {
            (upper, lower) = _getPriceInBaseForChainlinkAsset(sourceId, settings.source);
        } else if (settings.descriptor == Descriptor.UNIV3_TWAP) {
            // Call internal function to price TWAP
            // Note internal function can use getPriceInBase
            // (upper, lower) = _getPriceInBaseForTwapAsset(asset, source);
        } else if (settings.descriptor == Descriptor.EXTENSION) {
            (upper, lower) = IExtension(settings.source).getPriceInBase(sourceId);
        } else revert("Unkown");
    }

    function addSource(
        address asset,
        Descriptor descriptor,
        address source,
        bytes calldata sourceData
    ) external onlyOwner returns (uint64 sourceId) {
        // Supports Chainlink Assets, UniV3 TWAPS, and Extension contracts. All of these are able to call `getPriceInBase`
        sourceId = sourceCount++;

        uint256 upper;
        uint256 lower;

        if (descriptor == Descriptor.CHAINLINK) {
            _setupAssetForChainlinkSource(sourceId, source, sourceData);
            (upper, lower) = _getPriceInBaseForChainlinkAsset(sourceId, source);
        } else if (descriptor == Descriptor.UNIV3_TWAP) {
            // _setupAssetForTwapSource(sourceId, source, sourceData);
            // (upper, lower) = _getPriceInBaseForTwapAsset(sourceId, source);
        } else if (descriptor == Descriptor.EXTENSION) {
            IExtension(source).setupSource(asset, sourceData);
            (upper, lower) = IExtension(source).getPriceInBase(sourceId);
        }

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

    // ======================================= CHAINLINK AUTOMATION =======================================
    /**
     * @notice `checkUpkeep` is set up to allow for multiple derivatives to use Chainlink Automation.
     */
    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
        // (uint8 derivative, bytes memory derivativeCheckData) = abi.decode(checkData, (uint8, bytes));
        // if (derivative == 2) {
        //     (upkeepNeeded, performData) = _checkVirtualPriceBound(derivativeCheckData);
        // } else if (derivative == 3) {
        //     (upkeepNeeded, performData) = _checkVirtualPriceBound(derivativeCheckData);
        // } else revert PriceRouter__UnkownDerivative(derivative);
    }

    /**
     * @notice `performUpkeep` is set up to allow for multiple derivatives to use Chainlink Automation.
     */
    function performUpkeep(bytes calldata performData) external {
        // (uint8 derivative, bytes memory derivativePerformData) = abi.decode(performData, (uint8, bytes));
        // if (derivative == 2) {
        //     _updateVirtualPriceBound(derivativePerformData);
        // } else if (derivative == 3) {
        //     _updateVirtualPriceBound(derivativePerformData);
        // } else revert PriceRouter__UnkownDerivative(derivative);
    }

    // ======================================= PRICING OPERATIONS =======================================
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // =========================================== CHAINLINK PRICE SOURCE ===========================================\
    /**
     * @notice Stores data for Chainlink source assets.
     * @param max the max valid price of the asset
     * @param min the min valid price of the asset
     * @param heartbeat the max amount of time between price updates
     * @param inETH bool indicating whether the price feed is
     *        denominated in ETH(true) or USD(false)
     */
    struct ChainlinkSourceStorage {
        uint144 max;
        uint80 min;
        uint24 heartbeat;
        bool inETH;
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
    ) internal view returns (uint256 upper, uint256 lower) {
        ChainlinkSourceStorage memory parameters = getChainlinkSourceStorage[_sourceId];
        IChainlinkAggregator aggregator = IChainlinkAggregator(_source);
        (, int256 _price, , uint256 _timestamp, ) = aggregator.latestRoundData();
        uint256 price = _price.toUint256();
        // _checkPriceFeed(address(_asset), price, _timestamp, parameters.max, parameters.min, parameters.heartbeat);
        // If price is in ETH, then convert price into Base.
        if (parameters.inETH) {
            (uint256 _ethToBaseUpper, uint256 _ethToBaseLower) = getPriceInBase(WETH);
            upper = price.mulWadDown(_ethToBaseUpper);
            if (_ethToBaseLower > 0) lower = price.mulWadDown(_ethToBaseLower);
        } else {
            upper = price;
            // lower is not set.
        }
    }

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
     * @notice helper function to validate a price feed is safe to use.
     * @param asset ERC20 asset price feed data is for.
     * @param value the price value the price feed gave.
     * @param timestamp the last timestamp the price feed was updated.
     * @param max the upper price bound
     * @param min the lower price bound
     * @param heartbeat the max amount of time between price updates
     */
    function _checkPriceFeed(
        address asset,
        uint256 value,
        uint256 timestamp,
        uint144 max,
        uint88 min,
        uint24 heartbeat
    ) internal view {
        if (value < min) revert PriceRouter__AssetBelowMinPrice(address(asset), value, min);

        if (value > max) revert PriceRouter__AssetAboveMaxPrice(address(asset), value, max);

        uint256 timeSinceLastUpdate = block.timestamp - timestamp;
        if (timeSinceLastUpdate > heartbeat)
            revert PriceRouter__StalePrice(address(asset), timeSinceLastUpdate, heartbeat);
    }

    // =========================================== TWAP PRICE SOURCE ===========================================
    /**
     * @notice TWAP Source Storage
     */
    mapping(uint64 => ERC20) public getTwapSourceStorage;

    /**
     * @notice Setup function for pricing TWAP source assets.
     * @dev _source The address of the aToken.
     * @dev _storage is not used.
     */
    // function _setupAssetForTwapSource(address _asset, address _source, bytes memory) internal {
    //     IAaveToken aToken = IAaveToken(_source);
    //     getAaveDerivativeStorage[_asset] = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
    // }

    // /**
    //  * @notice Get the price of an Aave derivative in terms of USD.
    //  */
    // function _getPriceInBaseForTwapAsset(ERC20 asset, address source) internal view returns (uint256) {
    //     asset = getAaveDerivativeStorage[asset];
    //     return _getPriceInUSD(asset, getAssetSettings[asset], cache);
    // }
}
