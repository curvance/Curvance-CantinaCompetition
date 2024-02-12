// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Api3Adaptor } from "contracts/oracles/adaptors/api3/Api3Adaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";

contract TestApi3Adaptor is TestBaseOracleRouter {
    address private ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address private USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    address private DAPI_PROXY_ARB_USD =
        0x669bFFFAb8866d84F832abF90Dc9c1D73b7525Bc;
    address private CHAINLINK_PRICE_FEED_ETH =
        0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    string private ARB_TICKER = "ARB/USD";

    Api3Adaptor public adapter;

    function setUp() public override {
        _fork("ETH_NODE_URI_ARBITRUM", 174096479);

        _deployCentralRegistry();
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        adapter = new Api3Adaptor(ICentralRegistry(address(centralRegistry)));
        adapter.addAsset(ARB, ARB_TICKER, DAPI_PROXY_ARB_USD, 0, true);

        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        oracleRouter.addApprovedAdaptor(address(adapter));
        oracleRouter.addAssetPriceFeed(ARB, address(adapter));
    }

    function testReturnsCorrectPrice() public {
        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            ARB,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertGetPrice__AssetIsNotSupported() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__AssetIsNotSupported.selector);
        adapter.getPrice(USDC, true, false);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adapter.removeAsset(ARB);
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(ARB, true, false);
    }

    function testRevertAddAsset__InvalidHeartbeat() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__InvalidHeartbeat.selector);
        adapter.addAsset(
            ARB,
            ARB_TICKER,
            DAPI_PROXY_ARB_USD,
            1 days + 1,
            true
        );
    }

    function testRevertAddAsset__DAPINameHashError() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__DAPINameHashError.selector);
        adapter.addAsset(ARB, "ARB/USDC", DAPI_PROXY_ARB_USD, 0, true);
    }

    function testCanAddSameAsset() public {
        adapter.addAsset(ARB, ARB_TICKER, DAPI_PROXY_ARB_USD, 0, false);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__AssetIsNotSupported.selector);
        adapter.removeAsset(address(0));
    }

    function testRevertGetPriceInETH__NotSupported() public {
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(ARB, false, false);
    }
}
