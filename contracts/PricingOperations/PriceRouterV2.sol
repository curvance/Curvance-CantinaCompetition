// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../interfaces/ICentralRegistry.sol";
import "../interfaces/IOracleExtension.sol";



/**
 * @title Curvance Dual Oracle Price Router
 * @notice Provides a universal interface allowing Curvance contracts to retrieve secure pricing
 *         data based on various price feeds.
 */
contract PriceRouter {

    /**
    * @notice Return data from oracle extension
    * @param price the price of the asset in some asset, either ETH or USD
    * @param hadError the message return data, whether the extension ran into trouble pricing the asset
    */
    struct feedData {
        uint240 price;
        bool hadError;
    }
    //TODO:
    // Natspec/documentation
    // Decide on which permissioned functions need timelock vs no timelock
    // Check if mappings for assetPriceFeeds is better than 2 slot array
    // Write grabbing multiple prices from extensions to save on checks
    // Potentially move ETHUSD call to chainlink extension?

    /**
     * @notice Mapping used to track whether or not an address is an Extension.
     */
    mapping(address => bool) public isApprovedExtensions;
    /**
     * @notice Mapping used to track an assets configured price feeds.
     */
    mapping(address => address[]) public assetPriceFeeds;

    ICentralRegistry public immutable centralRegistry;
    address public immutable CHAINLINK_ETH_USD;
    uint256 public constant CHAINLINK_DIVISOR = 1e8;
    uint256 public constant DENOMINATOR = 10000;

    uint256 public PRICEFEED_MAXIMUM_DIVERGENCE = 11000;
    uint256 public CHAINLINK_MAX_DELAY = 1 days;

    /**
     * @notice Error code for no error.
     */
    uint256 public constant NO_ERROR = 0;

    /**
     * @notice Error code for caution.
     */
    uint256 public constant CAUTION = 1;

    /**
     * @notice Error code for bad source.
     */
    uint256 public constant BAD_SOURCE = 2;

    constructor(ICentralRegistry _centralRegistry, address ETH_USD_FEED) {
        
        centralRegistry = _centralRegistry;  
        // Save the USD-ETH price feed because it is a widely used pricing path.
        CHAINLINK_ETH_USD = ETH_USD_FEED;//0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419 on mainnet

    }

    modifier onlyDaoManager () {
        require(msg.sender == centralRegistry.daoAddress(), "priceRouter: UNAUTHORIZED");
        _;
    }

    function getPrice(address _asset) public view returns (uint256, uint256) {
        uint256 oracles = assetPriceFeeds[_asset].length;
        require(oracles > 0,"priceRouter: no feeds available");

        if (oracles < 2) {
            return getPriceSingleFeed(_asset);
        }

        return getPriceDualFeed(_asset);

    }

    function getPriceDualFeed(address _asset) internal view returns (uint256, uint256) {
        feedData memory feed0 = getPriceFromFeed(_asset, 0);
        feedData memory feed1 = getPriceFromFeed(_asset, 1);

        if (feed0.hadError && feed1.hadError) return (0, BAD_SOURCE);
        if (feed0.hadError || feed1.hadError){
            return (getWorkingPrice(feed0, feed1), CAUTION);
        }

        return processPriceFeedData(feed0.price, feed1.price);

    }

    function getPriceSingleFeed(address _asset) internal view returns (uint256, uint256) {
        priceReturnData memory data = IOracleExtension(assetPriceFeeds[_asset][0]).getPrice(_asset);
        if (data.hadError) return (0, BAD_SOURCE);

        if (!data.inUSD) {
            (data.price, data.hadError) = priceToUSD(data.price);
            if (data.hadError) return (0, BAD_SOURCE); 
        }

        return (data.price, NO_ERROR);

    }

    function getPriceFromFeed(address _asset, uint256 _feedNumber) internal view returns (feedData memory) {
        priceReturnData memory data = IOracleExtension(assetPriceFeeds[_asset][_feedNumber]).getPrice(_asset);
        if (data.hadError) return (feedData({price: 0, hadError: true}));
        
        if (!data.inUSD) {
            (data.price, data.hadError) = priceToUSD(data.price);
        }

        return (feedData({price: data.price, hadError: data.hadError}));

    }

    function priceToUSD(uint256 _priceInETH) internal view returns (uint240, bool) {
        (, int256 _answer, , uint256 _updatedAt, ) = AggregatorV3Interface(CHAINLINK_ETH_USD).latestRoundData();

            // If data is stale or negative we have a problem to relay back
            if (_answer <= 0 || (block.timestamp - _updatedAt > CHAINLINK_MAX_DELAY)) {
                return (uint240(_priceInETH), true);
            }
            return (uint240((_priceInETH * uint256(_answer))/CHAINLINK_DIVISOR), false);
    }

    function processPriceFeedData(uint256 a, uint256 b) internal view returns (uint256, uint256) {
        if (a <= b) {
            if ( ((a * PRICEFEED_MAXIMUM_DIVERGENCE)/DENOMINATOR) < b){
                return (0, CAUTION);
            }
            return(a, NO_ERROR);
        }

        if ( ((b * PRICEFEED_MAXIMUM_DIVERGENCE)/DENOMINATOR) < a){
                return (0, CAUTION);
            }
        return(b, NO_ERROR);
    }

    function getWorkingPrice(feedData memory feed0, feedData memory feed1) internal pure returns (uint256) {
        if (feed0.hadError) return feed0.price;
        return feed1.price;
    }

    function addAssetPriceFeed(address _asset, address _feed) external onlyDaoManager {
        require(isApprovedExtensions[_feed], "priceRouter: unapproved feed");
        require(assetPriceFeeds[_asset].length < 2,"priceRouter: dual feed already configured");
        assetPriceFeeds[_asset].push(_feed);
    }

    function removeAssetPriceFeed(address _asset, address _feed) external onlyDaoManager {
        uint256 oracles = assetPriceFeeds[_asset].length;
        require(oracles > 0,"priceRouter: no feeds available");

        if (oracles > 1) {
            require(assetPriceFeeds[_asset][0] == _feed || assetPriceFeeds[_asset][1] == _feed, "priceRouter: feed does not exist");
            if (assetPriceFeeds[_asset][0] == _feed) {
                assetPriceFeeds[_asset][0] = assetPriceFeeds[_asset][1];
            } // we want to remove the first feed of two, so move the second feed to slot one

        } else {
            require(assetPriceFeeds[_asset][0] == _feed, "priceRouter: feed does not exist");
        } // we know the feed exists, cant use isApprovedExtensions as we could have removed it as an approved extension prior

        assetPriceFeeds[_asset].pop();
    }

    function addApprovedExtension(address _extension) external onlyDaoManager {
        require(!isApprovedExtensions[_extension], "priceRouter: extension already approved");
        isApprovedExtensions[_extension] = true;
    }

    function removeApprovedExtension(address _extension) external onlyDaoManager {
        require(isApprovedExtensions[_extension], "priceRouter: extension does not exist");
        delete isApprovedExtensions[_extension];
    }

    function setPriceFeedMaxDivergence(uint256 _maxDivergence) external onlyDaoManager {
        require( _maxDivergence > 10500, "priceRouter: divergence is too small");
        PRICEFEED_MAXIMUM_DIVERGENCE = _maxDivergence;
    }

    function setChainlinkDelay(uint256 _delay) external onlyDaoManager {
        require(_delay < 1 days, "priceRouter: delay is too large");
        CHAINLINK_MAX_DELAY = _delay;
    }

    

}
