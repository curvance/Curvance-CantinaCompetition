// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { CamelotStableLPAdaptor } from "contracts/oracles/adaptors/camelot/CamelotStableLPAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract TestCamelotStableLPAdapter is TestBasePriceRouter {
    address private DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address private USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address private CHAINLINK_PRICE_FEED_ETH =
        0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address private CHAINLINK_PRICE_FEED_DAI =
        0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
    address private CHAINLINK_PRICE_FEED_USDC =
        0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    address private DAI_USDC = 0x01efEd58B534d7a7464359A6F8d14D986125816B;

    CamelotStableLPAdaptor public adapter;

    function setUp() public override {
        _fork("ETH_NODE_URI_ARBITRUM", 148061500);

        _deployCentralRegistry();

        priceRouter = new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            CHAINLINK_PRICE_FEED_ETH
        );
        centralRegistry.setPriceRouter(address(priceRouter));

        adapter = new CamelotStableLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adapter.addAsset(DAI_USDC);

        priceRouter.addApprovedAdaptor(address(adapter));
        priceRouter.addAssetPriceFeed(DAI_USDC, address(adapter));
    }

    function testRevertWhenUnderlyingChainAssetPriceNotSet() public {
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(DAI_USDC, true, false);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, true);
        chainlinkAdaptor.addAsset(DAI, CHAINLINK_PRICE_FEED_DAI, true);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(DAI, address(chainlinkAdaptor));

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            DAI_USDC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adapter.removeAsset(DAI_USDC);
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(DAI_USDC, true, false);
    }
}
