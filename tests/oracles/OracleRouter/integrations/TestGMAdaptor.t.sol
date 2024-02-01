// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { GMAdaptor } from "contracts/oracles/adaptors/gmx/GMAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";

contract TestGMAdaptor is TestBaseOracleRouter {
    address private GMX_READER = 0xf60becbba223EEA9495Da3f606753867eC10d139;
    address private GMX_DATASTORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    address private GM_BTC_USDC = 0x47c031236e19d024b42f8AE6780E44A573170703;

    address private BTC = 0x47904963fc8b2340414262125aF798B9655E58Cd;
    address private WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address private USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    address private CHAINLINK_PRICE_FEED_ETH =
        0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address private CHAINLINK_PRICE_FEED_BTC =
        0x6ce185860a4963106506C203335A2910413708e9;
    address private CHAINLINK_PRICE_FEED_WBTC =
        0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;
    address private CHAINLINK_PRICE_FEED_USDC =
        0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    GMAdaptor public adapter;

    function setUp() public override {
        _fork("ETH_NODE_URI_ARBITRUM", 145755190);

        _deployCentralRegistry();

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        adapter = new GMAdaptor(
            ICentralRegistry(address(centralRegistry)),
            GMX_READER,
            GMX_DATASTORE
        );
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        oracleRouter.addApprovedAdaptor(address(adapter));
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        chainlinkAdaptor.addAsset(
            _ETH_ADDRESS,
            CHAINLINK_PRICE_FEED_ETH,
            0,
            true
        );
        chainlinkAdaptor.addAsset(WBTC, CHAINLINK_PRICE_FEED_WBTC, 0, true);
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, 0, true);

        oracleRouter.addAssetPriceFeed(
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(WBTC, address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));

        adapter.addAsset(GM_BTC_USDC, WBTC);

        oracleRouter.addAssetPriceFeed(GM_BTC_USDC, address(adapter));
    }

    function testDeploymentRevertWhenCentralRegistryIsInvalid() public {
        vm.expectRevert(
            BaseOracleAdaptor
                .BaseOracleAdaptor__InvalidCentralRegistry
                .selector
        );
        new GMAdaptor(ICentralRegistry(address(0)), GMX_READER, GMX_DATASTORE);
    }

    function testDeploymentRevertWhenReaderIsZeroAddress() public {
        vm.expectRevert(GMAdaptor.GMAdaptor__GMXReaderIsZeroAddress.selector);
        new GMAdaptor(
            ICentralRegistry(address(centralRegistry)),
            address(0),
            GMX_DATASTORE
        );
    }

    function testDeploymentRevertWhenDataStoreIsZeroAddress() public {
        vm.expectRevert(
            GMAdaptor.GMAdaptor__GMXDataStoreIsZeroAddress.selector
        );
        new GMAdaptor(
            ICentralRegistry(address(centralRegistry)),
            GMX_READER,
            address(0)
        );
    }

    function testAddAssetRevertWhenAlteredTokenIsInvalid() public {
        adapter.removeAsset(GM_BTC_USDC);

        vm.expectRevert(GMAdaptor.GMAdaptor__AlteredTokenIsInvalid.selector);
        adapter.addAsset(GM_BTC_USDC, address(0));
    }

    function testAddAssetRevertWhenLongTokenIsNotSupported() public {
        adapter.removeAsset(GM_BTC_USDC);
        oracleRouter.removeAssetPriceFeed(WBTC, address(chainlinkAdaptor));

        vm.expectRevert(
            abi.encodeWithSelector(
                GMAdaptor.GMAdaptor__MarketTokenIsNotSupported.selector,
                WBTC
            )
        );
        adapter.addAsset(GM_BTC_USDC, WBTC);
    }

    function testAddAssetRevertWhenShortTokenIsNotSupported() public {
        adapter.removeAsset(GM_BTC_USDC);
        oracleRouter.removeAssetPriceFeed(USDC, address(chainlinkAdaptor));

        vm.expectRevert(
            abi.encodeWithSelector(
                GMAdaptor.GMAdaptor__MarketTokenIsNotSupported.selector,
                USDC
            )
        );
        adapter.addAsset(GM_BTC_USDC, WBTC);
    }

    function testRemoveAssetRevertWhenGMTokenIsNotSupported() public {
        adapter.removeAsset(GM_BTC_USDC);

        vm.expectRevert(GMAdaptor.GMAdaptor__AssetIsNotSupported.selector);
        adapter.removeAsset(GM_BTC_USDC);
    }

    function testReturnsCorrectPriceInUSD() public {
        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            GM_BTC_USDC,
            true,
            false
        );

        assertEq(errorCode, 0);
        assertApproxEqAbs(price, 1.1215e18, 0.0001e18);
    }

    function testReturnsCorrectPriceInETH() public {
        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            GM_BTC_USDC,
            false,
            false
        );

        assertEq(errorCode, 0);
        assertApproxEqAbs(price, 0.000625e18, 0.000001e18);
    }
}
