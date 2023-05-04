// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeTransferLib } from "src/base/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Extension } from "./Extension.sol";
import { OracleLibrary } from "lib/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { UniswapV3Pool } from "src/interfaces/Uniswap/UniswapV3Pool.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Curvance Pricing Operations
 * @notice Provides a universal interface allowing Curvance contracts to retrieve secure pricing
 *         data based of Chainlink data feeds, and Uniswap V3 TWAPS.
 * @author crispymangoes
 */
contract PriceOps is Ownable {
    using SafeTransferLib for ERC20;
    using SafeCast for int256;
    using Math for uint256;
    using Address for address;

    /*//////////////////////////////////////////////////////////////
                             STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stores configuration data for a pricing source.
     * @param asset address of the asset this source can price
     * @param descriptor the uint8 id used to describe this asset
     * @param source
     *        - Chainlink Source use Data Feed address.
     *        - TWAP Source use UniswapV3 pool address.
     *        - Extension Source use extension address.
     */
    struct AssetSourceSettings {
        address asset;
        Descriptor descriptor;
        address source;
    }

    /**
     * @notice Stores configuration data for pricing a specific asset.
     * @param allowedSourceDivergence The % envelope the sources can diverge from eachother
     *        - given in basis points, IE 100 == 1%, 500 == 5%
     */
    struct AssetSettings {
        uint64 primarySource;
        uint64 secondarySource;
        uint16 allowedSourceDivergence;
    }

    /**
     * @notice Stores configuration data for Chainlink price sources.
     * @param max the max valid price of the asset
     *        - 0 defaults to use aggregators max price buffered by ~10%
     * @param min the min valid price of the asset
     *        - 0 defaults to use aggregators min price buffered by ~10%
     * @param heartbeat the max amount of time between price updates
     *        - 0 defaults to using DEFAULT_HEART_BEAT
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
     * @notice Stores configuration data for Uniswap V3 Twap price sources.
     * @param secondsAgo period used for TWAP calculation
     * @param baseDecimals the asset you want to price, decimals
     * @param quoteDecimals the asset price is quoted in, decimals
     * @param baseToken the asset you want to price
     * @param quoteToken the asset Twap calulation denominates in
     */
    struct TwapSourceStorage {
        uint32 secondsAgo;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        address baseToken;
        address quoteToken;
    }

    /*//////////////////////////////////////////////////////////////
                             GLOBAL STATE
    //////////////////////////////////////////////////////////////*/

    uint64 public sourceCount;
    mapping(uint64 => AssetSourceSettings) public getAssetSourceSettings;

    /**
     * @notice Mapping between an asset to price and its `AssetSettings`.
     */
    mapping(address => AssetSettings) public getAssetSettings;

    mapping(address => bool) public isExtension;

    /**
     * @notice Returns Chainlink Derivative Storage
     */
    mapping(uint64 => ChainlinkSourceStorage) public getChainlinkSourceStorage;

    /**
     * @notice TWAP Source Storage
     */
    mapping(uint64 => TwapSourceStorage) public getTwapSourceStorage;

    address public constant USD = address(840);
    uint8 public constant NO_ERROR = 0;
    uint8 public constant CAUTION = 1;
    uint8 public constant BAD_SOURCE = 2;
    uint16 public constant MAX_ALLOWED_SOURCE_DIVERGENCE = 0.2e4;
    /**
     * @notice The allowed deviation between the expected answer vs the actual answer.
     */
    uint256 public constant EXPECTED_ANSWER_DEVIATION = 0.02e18;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /**
     * @notice If zero is specified for a Chainlink asset heartbeat, this value is used instead.
     */
    uint24 public constant DEFAULT_HEART_BEAT = 1 days;

    uint64 public constant EDIT_ASSET_DELAY = 7 days;

    mapping(bytes32 => uint64) public editAssetTimestamp;

    /**
     * @notice The smallest possible TWAP that can be used.
     */
    uint32 public constant MINIMUM_SECONDS_AGO = 300;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AddAsset(address indexed asset);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PriceRouter__InvalidMinPrice(uint256 minPrice, uint256 bufferedMinPrice);
    error PriceRouter__InvalidMaxPrice(uint256 maxPrice, uint256 bufferedMaxPrice);
    error PriceRouter__InvalidAsset(address asset);
    error PriceRouter__BadAnswer(uint256 answer, uint256 expectedAnswer);
    error PriceRouter__UnkownDerivative(uint8 unkownDerivative);
    error PriceRouter__MinPriceGreaterThanMaxPrice(uint256 min, uint256 max);
    error PriceRouter__AssetBelowMinPrice(uint64 sourceId, uint256 price, uint256 minPrice);
    error PriceRouter__AssetAboveMaxPrice(uint64 sourceId, uint256 price, uint256 maxPrice);
    error PriceRouter__StalePrice(uint64 sourceId, uint256 timeSinceLastUpdate, uint256 heartbeat);
    error PriceRouter__TwapAssetNotInPool();
    error PriceRouter__SecondsAgoDoesNotMeetMinimum();

    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    enum Descriptor {
        NONE,
        CHAINLINK,
        UNIV3_TWAP,
        EXTENSION
    }

    /*//////////////////////////////////////////////////////////////
                          SETUP LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor adds ETH-USD pricing source to that Chainlink
     *         sources have access to a USD -> ETH conversion.
     */
    constructor(address ETH_USD_FEED, bytes memory parameters) {
        // Save the USD-ETH price feed because it is a widely used pricing path.
        uint64 sourceId = _addSource(USD, Descriptor.CHAINLINK, ETH_USD_FEED, parameters);
        _addAsset(USD, sourceId, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    function addSource(
        address asset,
        Descriptor descriptor,
        address source,
        bytes memory sourceData
    ) external onlyOwner returns (uint64 sourceId) {
        sourceId = _addSource(asset, descriptor, source, sourceData);
    }

    function addAsset(
        address asset,
        uint64 primarySource,
        uint64 secondarySource,
        uint16 _allowedSourceDivergence
    ) external onlyOwner {
        _addAsset(asset, primarySource, secondarySource, _allowedSourceDivergence);
    }

    function proposeEditAsset(
        address asset,
        uint64 primarySource,
        uint64 secondarySource,
        uint16 _allowedSourceDivergence
    ) external onlyOwner {
        if (getAssetSettings[asset].primarySource == 0) revert("Asset not added");
        bytes32 editHash = keccak256(abi.encode(asset, primarySource, secondarySource, _allowedSourceDivergence));

        uint64 editTimestamp = editAssetTimestamp[editHash];

        if (editTimestamp != 0) revert("Edit already proposed.");

        editAssetTimestamp[editHash] = uint64(block.timestamp + EDIT_ASSET_DELAY);

        // TODO emit an event
    }

    function editAsset(
        address asset,
        uint64 primarySource,
        uint64 secondarySource,
        uint16 _allowedSourceDivergence
    ) external onlyOwner {
        bytes32 editHash = keccak256(abi.encode(asset, primarySource, secondarySource, _allowedSourceDivergence));

        uint64 editTimestamp = editAssetTimestamp[editHash];

        if (editTimestamp == 0 || block.timestamp < editTimestamp) revert("Edit not mature.");

        _updateAsset(asset, primarySource, secondarySource, _allowedSourceDivergence);
    }

    function cancelEditAsset(
        address asset,
        uint64 primarySource,
        uint64 secondarySource,
        uint16 _allowedSourceDivergence
    ) external onlyOwner {
        if (getAssetSettings[asset].primarySource == 0) revert("Asset not added");
        bytes32 editHash = keccak256(abi.encode(asset, primarySource, secondarySource, _allowedSourceDivergence));

        uint64 editTimestamp = editAssetTimestamp[editHash];

        if (editTimestamp == 0) revert("Edit not proposed.");

        editAssetTimestamp[editHash] = 0;
    }

    /*//////////////////////////////////////////////////////////////
                        PRICING VIEW LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice return bool indicating whether or not an asset has been set up.
     * @dev Since `addAsset` enforces the derivative is non zero, checking if the stored setting
     *      is nonzero is sufficient to see if the asset is set up.
     */
    function isSupported(address asset) external view returns (bool) {
        return getAssetSettings[asset].primarySource > 0;
    }

    function getPriceInBaseEnforceNonZeroLower(
        address asset
    ) external view returns (uint256 upper, uint256 lower, uint8 errorCode) {
        (upper, lower, errorCode) = _getPriceInBase(asset);

        if (lower == 0) lower = upper;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTENSION VIEW LOGIC
    //////////////////////////////////////////////////////////////*/

    function getPriceInBase(address asset) external view returns (uint256, uint256, uint8) {
        if (!isExtension[msg.sender]) revert("Caller is not an extension.");
        return _getPriceInBase(asset);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL PRICING LOGIC
    //////////////////////////////////////////////////////////////*/

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
            _setupAssetForChainlinkSource(asset, sourceId, source, sourceData);
            (upper, lower, errorCode) = _getPriceInBaseForChainlinkAsset(sourceId, source);
        } else if (descriptor == Descriptor.UNIV3_TWAP) {
            _setupAssetForTwapSource(asset, sourceId, source, sourceData);
            (upper, lower, errorCode) = _getPriceInBaseForTwapAsset(sourceId, source);
        } else if (descriptor == Descriptor.EXTENSION) {
            if (!isExtension[source]) isExtension[source] = true;
            Extension(source).setupSource(asset, sourceId, sourceData);
            (upper, lower, errorCode) = Extension(source).getPriceInBase(sourceId);
        }

        if (errorCode != 0) revert("Source errored");

        getAssetSourceSettings[sourceId] = AssetSourceSettings({
            asset: asset,
            descriptor: descriptor,
            source: source
        });
    }

    function _addAsset(
        address asset,
        uint64 primarySource,
        uint64 secondarySource,
        uint16 _allowedSourceDivergence
    ) internal {
        // Check if asset is already setup.
        if (getAssetSettings[asset].primarySource != 0) revert("Asset already setup");
        _updateAsset(asset, primarySource, secondarySource, _allowedSourceDivergence);
    }

    function _updateAsset(
        address asset,
        uint64 primarySource,
        uint64 secondarySource,
        uint16 _allowedSourceDivergence
    ) internal {
        if (primarySource == 0) revert("Invalid primary");

        // make sure sources are valid, and for the right asset.
        if (getAssetSourceSettings[primarySource].asset != asset) revert("Source Asset mismatch.");
        // If secondary is set make sure asset matches.
        if (secondarySource != 0) {
            if (getAssetSourceSettings[secondarySource].asset != asset) revert("Source Asset mismatch.");
            // Make sure source divergence is reasonable.
            if (_allowedSourceDivergence > MAX_ALLOWED_SOURCE_DIVERGENCE) revert("Invalid source divergence");
        }

        getAssetSettings[asset] = AssetSettings({
            primarySource: primarySource,
            secondarySource: secondarySource,
            allowedSourceDivergence: _allowedSourceDivergence
        });
    }

    function _getPriceInBase(address asset) internal view returns (uint256, uint256, uint8) {
        if (asset == WETH) return (1 ether, 1 ether, NO_ERROR);
        AssetSettings memory settings = getAssetSettings[asset];
        uint8 errorCode = NO_ERROR;
        uint256 primarySourceUpper;
        uint256 primarySourceLower;
        uint8 primaryErrorCode;

        // First figure out if we have a single or dual oracle.
        if (settings.secondarySource == 0) {
            // Single Oracle.

            // Query the primary source.
            (primarySourceUpper, primarySourceLower, primaryErrorCode) = _getPriceFromSource(settings.primarySource);
            // No need to look at error code, just return it.
            return (primarySourceUpper, primarySourceLower, primaryErrorCode);
        } else {
            // Dual Oracle.
            uint256 secondarySourceUpper;
            uint256 secondarySourceLower;
            uint8 secondaryErrorCode;

            // Query the primary source.
            (primarySourceUpper, primarySourceLower, primaryErrorCode) = _getPriceFromSource(settings.primarySource);

            // Query the secondary source.
            (secondarySourceUpper, secondarySourceLower, secondaryErrorCode) = _getPriceFromSource(
                settings.secondarySource
            );

            // We are completely blind if this price is good or not because both sources are bad.
            if (primaryErrorCode == BAD_SOURCE && secondaryErrorCode == BAD_SOURCE) {
                return (0, 0, BAD_SOURCE);
            } else {
                // At best we can return a NO_ERROR but need to check if sources diverge, or if one of them has a non zero error code.
                if (primaryErrorCode == NO_ERROR && secondaryErrorCode == NO_ERROR) {
                    (uint256 upper, uint256 lower) = _findUpperAndLower(
                        primarySourceUpper,
                        primarySourceLower,
                        secondarySourceUpper,
                        secondarySourceLower
                    );

                    // Check for divergence
                    uint256 minLower = upper.mulDivDown(1e4 - settings.allowedSourceDivergence, 1e4);
                    if (lower < minLower) errorCode = CAUTION;

                    return (upper, lower, errorCode);
                } else {
                    // One of our sources has some error, but we know the other one is usable with caution.
                    errorCode = CAUTION;
                    if (primaryErrorCode == BAD_SOURCE) {
                        return (secondarySourceUpper, secondarySourceLower, errorCode);
                    } else if (secondaryErrorCode == BAD_SOURCE) {
                        return (primarySourceUpper, primarySourceLower, errorCode);
                    } else {
                        // Both sources are usable, but need to check for zero lower values.
                        (uint256 upper, uint256 lower) = _findUpperAndLower(
                            primarySourceUpper,
                            primarySourceLower,
                            secondarySourceUpper,
                            secondarySourceLower
                        );
                        return (upper, lower, errorCode);
                    }
                }
            }
        }
    }

    function _findUpperAndLower(
        uint256 primarySourceUpper,
        uint256 primarySourceLower,
        uint256 secondarySourceUpper,
        uint256 secondarySourceLower
    ) internal pure returns (uint256 upper, uint256 lower) {
        // First find upper.
        upper = primarySourceUpper > secondarySourceUpper ? primarySourceUpper : secondarySourceUpper;

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
            (upper, lower, errorCode) = Extension(settings.source).getPriceInBase(sourceId);
        } else revert("Unkown");
    }

    /*//////////////////////////////////////////////////////////////
                        CHAINLINK SOURCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Setup function for pricing Chainlink derivative assets.
     * @dev _source The address of the Chainlink Data feed.
     * @dev _storage A ChainlinkDerivativeStorage value defining valid prices.
     */
    function _setupAssetForChainlinkSource(address, uint64 _sourceId, address _source, bytes memory _storage) internal {
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

        // If errorCode is BAD_SOURCE there is no point to conitnue;
        if (errorCode == BAD_SOURCE) return (0, 0, errorCode);

        if (_sourceId == 1) {
            // Trying to price ETH to USD, but need to invert price.
            upper = uint256(1e18).mulDivDown(1e8, price);
        } else {
            // If price is in Usd, convert to ETH.
            if (parameters.inUsd) {
                (uint256 _baseToEthUpper, uint256 _baseToEthLower, uint8 _errorCode) = _getPriceInBase(USD);
                upper = price.mulDivDown(_baseToEthUpper, 1e8);
                if (_baseToEthLower > 0) lower = price.mulDivDown(_baseToEthLower, 1e8);
                // Favor the worst error code.
                if (_errorCode > errorCode) errorCode = _errorCode;
            } else {
                upper = price;
                // lower is not set.
            }
        }
    }

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
        if (value < min) return BAD_SOURCE;

        if (value > max) return BAD_SOURCE;

        uint256 timeSinceLastUpdate = block.timestamp - timestamp;
        if (timeSinceLastUpdate > heartbeat) return BAD_SOURCE;

        return NO_ERROR;
    }

    /*//////////////////////////////////////////////////////////////
                        UNIV3 TWAP SOURCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Setup function for pricing TWAP source assets.
     */
    function _setupAssetForTwapSource(address asset, uint64 sourceId, address _source, bytes memory _storage) internal {
        TwapSourceStorage memory parameters = abi.decode(_storage, (TwapSourceStorage));

        // Verify seconds ago is reasonable.
        if (parameters.secondsAgo < MINIMUM_SECONDS_AGO) revert PriceRouter__SecondsAgoDoesNotMeetMinimum();

        UniswapV3Pool pool = UniswapV3Pool(_source);

        address token0 = pool.token0();
        address token1 = pool.token1();
        if (token0 == asset) {
            parameters.baseDecimals = ERC20(asset).decimals();
            parameters.quoteDecimals = ERC20(token1).decimals();
            parameters.quoteToken = token1;
        } else if (token1 == asset) {
            parameters.baseDecimals = ERC20(asset).decimals();
            parameters.quoteDecimals = ERC20(token0).decimals();
            parameters.quoteToken = token0;
        } else revert PriceRouter__TwapAssetNotInPool();

        // Verify seconds ago is reasonable
        // Also if I add in asset to this I could do a sanity check to make sure asset is token0 or token1

        getTwapSourceStorage[sourceId] = parameters;
    }

    /**
     * @notice
     */
    function _getPriceInBaseForTwapAsset(
        uint64 sourceId,
        address source
    ) internal view returns (uint256 upper, uint256 lower, uint8 errorCode) {
        TwapSourceStorage memory parameters = getTwapSourceStorage[sourceId];
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(source, parameters.secondsAgo);
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
            // If underlying source is bad, we can not trust this source.
            if (_errorCode == BAD_SOURCE) return (0, 0, _errorCode);
            upper = quoteAmount.mulDivDown(_quoteToBaseUpper, 10 ** parameters.quoteDecimals);
            if (_quoteToBaseLower > 0)
                lower = quoteAmount.mulDivDown(_quoteToBaseLower, 10 ** parameters.quoteDecimals);
            if (_errorCode > 0) errorCode = _errorCode;
        } else {
            // Price is already given in base.
            upper = quoteAmount;
        }
    }
}
