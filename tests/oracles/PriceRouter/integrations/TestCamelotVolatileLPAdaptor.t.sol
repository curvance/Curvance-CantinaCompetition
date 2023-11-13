// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { CamelotVolatileLPAdaptor } from "contracts/oracles/adaptors/camelot/CamelotVolatileLPAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract TestCamelotVolatileLPAdapter is TestBasePriceRouter {
    address private WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address private CHAINLINK_PRICE_FEED_ETH =
        0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address private CHAINLINK_PRICE_FEED_USDC =
        0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    address private WETH_USDC = 0x84652bb2539513BAf36e225c930Fdd8eaa63CE27;

    CamelotVolatileLPAdaptor public adapter;

    function setUp() public override {
        _fork("ETH_NODE_URI_ARBITRUM", 148061500);

        _deployCentralRegistry();
        priceRouter = new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            CHAINLINK_PRICE_FEED_ETH
        );
        centralRegistry.setPriceRouter(address(priceRouter));

        adapter = new CamelotVolatileLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adapter.addAsset(WETH_USDC);

        priceRouter.addApprovedAdaptor(address(adapter));
        priceRouter.addAssetPriceFeed(WETH_USDC, address(adapter));
    }

    function testRevertWhenUnderlyingChainAssetPriceNotSet() public {
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(WETH_USDC, true, false);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, true);
        chainlinkAdaptor.addAsset(WETH, CHAINLINK_PRICE_FEED_ETH, true);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(WETH, address(chainlinkAdaptor));

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            WETH_USDC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adapter.removeAsset(WETH_USDC);
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(WETH_USDC, true, false);
    }
}
