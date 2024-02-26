// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { VelodromeStableLPAdaptor } from "contracts/oracles/adaptors/velodrome/VelodromeStableLPAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { BaseStableLPAdaptor } from "contracts/oracles/adaptors/uniV2Base/BaseStableLPAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { VelodromeLib } from "contracts/libraries/VelodromeLib.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";

contract TestVelodromeStableLPAdaptor is TestBaseOracleRouter {
    address private DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address private USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    address private CHAINLINK_PRICE_FEED_ETH =
        0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    address private CHAINLINK_PRICE_FEED_DAI =
        0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6;
    address private CHAINLINK_PRICE_FEED_USDC =
        0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;

    address private veloRouter = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;
    address private DAI_USDC = 0x19715771E30c93915A5bbDa134d782b81A820076;

    VelodromeStableLPAdaptor public adaptor;

    function setUp() public override {
        _fork("ETH_NODE_URI_OPTIMISM", 110333246);

        _deployCentralRegistry();
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        adaptor = new VelodromeStableLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adaptor.addAsset(DAI_USDC);

        chainlinkAdaptor.addAsset(
            _ETH_ADDRESS,
            CHAINLINK_PRICE_FEED_ETH,
            0,
            true
        );
        chainlinkAdaptor.addAsset(DAI, CHAINLINK_PRICE_FEED_DAI, 0, true);
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, 0, true);

        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(DAI, address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));

        oracleRouter.addApprovedAdaptor(address(adaptor));
        oracleRouter.addAssetPriceFeed(DAI_USDC, address(adaptor));
    }

    function testRevertWhenUnderlyingChainAssetPriceNotSet() public {
        chainlinkAdaptor.removeAsset(DAI);

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(DAI_USDC, true, false);
    }

    function testReturnsCorrectPrice() public {
        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            DAI_USDC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adaptor.removeAsset(DAI_USDC);
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(DAI_USDC, true, false);
    }

    function testRevertAddAsset__AssetIsNotStableLP() public {
        vm.expectRevert(
            VelodromeStableLPAdaptor
                .VelodromeStableLPAdaptor__AssetIsNotStableLP
                .selector
        );
        adaptor.addAsset(0x0493Bf8b6DBB159Ce2Db2E0E8403E753Abd1235b);
    }

    function testCanUpdateAsset() public {
        adaptor.addAsset(DAI_USDC);
        adaptor.addAsset(DAI_USDC);
    }

    function testPriceDoesNotChangeAfterLargeSwap() public {
        uint256 errorCode;
        uint256 priceBefore;
        (priceBefore, errorCode) = oracleRouter.getPrice(
            DAI_USDC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(priceBefore, 0);

        // try large swap (500K USDC)
        uint256 amount = 500000e6;
        deal(USDC, address(this), amount);
        VelodromeLib._swapExactTokensForTokens(
            veloRouter,
            DAI_USDC,
            USDC,
            DAI,
            amount,
            true
        );

        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        assertGt(IERC20(DAI).balanceOf(address(this)), 0);

        uint256 priceAfter;
        (priceAfter, errorCode) = oracleRouter.getPrice(DAI_USDC, true, false);
        assertEq(errorCode, 0);
        assertApproxEqRel(priceBefore, priceAfter, 100000);
    }

    function testRevertGetPrice__AssetIsNotSupported() public {
        vm.expectRevert(
            BaseStableLPAdaptor
                .BaseStableLPAdaptor__AssetIsNotSupported
                .selector
        );
        adaptor.getPrice(address(0), true, false);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(
            BaseStableLPAdaptor
                .BaseStableLPAdaptor__AssetIsNotSupported
                .selector
        );
        adaptor.removeAsset(address(0));
    }
}
