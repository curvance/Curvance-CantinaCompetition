// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { CamelotVolatileLPAdaptor } from "contracts/oracles/adaptors/camelot/CamelotVolatileLPAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { BaseVolatileLPAdaptor } from "contracts/oracles/adaptors/utils/BaseVolatileLPAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";

contract TestCamelotVolatileLPAdapter is TestBaseOracleRouter {
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
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        adapter = new CamelotVolatileLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adapter.addAsset(WETH_USDC);

        chainlinkAdaptor.addAsset(
            _ETH_ADDRESS,
            CHAINLINK_PRICE_FEED_ETH,
            0,
            true
        );
        chainlinkAdaptor.addAsset(WETH, CHAINLINK_PRICE_FEED_ETH, 0, true);
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, 0, true);

        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(WETH, address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));

        oracleRouter.addApprovedAdaptor(address(adapter));
        oracleRouter.addAssetPriceFeed(WETH_USDC, address(adapter));
    }

    function testRevertWhenUnderlyingChainAssetPriceNotSet() public {
        chainlinkAdaptor.removeAsset(WETH);

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(WETH_USDC, true, false);
    }

    function testReturnsCorrectPrice() public {
        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
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
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(WETH_USDC, true, false);
    }

    function testRevertAddAsset__AssetIsNotVolatileLP() public {
        vm.expectRevert(
            CamelotVolatileLPAdaptor
                .CamelotVolatileLPAdaptor__AssetIsNotVolatileLP
                .selector
        );
        adapter.addAsset(0x01efEd58B534d7a7464359A6F8d14D986125816B);
    }

    function testCanUpdateAsset() public {
        adapter.addAsset(WETH_USDC);
        adapter.addAsset(WETH_USDC);
    }

    function testRevertGetPrice__AssetIsNotSupported() public {
        vm.expectRevert(
            BaseVolatileLPAdaptor
                .BaseVolatileLPAdaptor__AssetIsNotSupported
                .selector
        );
        adapter.getPrice(address(0), true, false);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(
            BaseVolatileLPAdaptor
                .BaseVolatileLPAdaptor__AssetIsNotSupported
                .selector
        );
        adapter.removeAsset(address(0));
    }
}
