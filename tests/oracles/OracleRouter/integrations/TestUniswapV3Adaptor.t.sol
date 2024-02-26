// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { UniswapV3Adaptor } from "contracts/oracles/adaptors/uniswap/UniswapV3Adaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { IStaticOracle } from "contracts/interfaces/external/uniswap/IStaticOracle.sol";

contract TestUniswapV3Adaptor is TestBaseOracleRouter {
    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address private CHAINLINK_PRICE_FEED_USDC =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    address private uniswapV3Oracle =
        0xB210CE856631EeEB767eFa666EC7C1C57738d438;
    address private WBTC_WETH = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
    address private WBTC_USDC = 0x9a772018FbD77fcD2d25657e5C547BAfF3Fd7D16;

    UniswapV3Adaptor public adaptor;

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        chainlinkAdaptor.addAsset(_ETH_ADDRESS, _CHAINLINK_ETH_USD, 0, true);
        chainlinkAdaptor.addAsset(WETH, _CHAINLINK_ETH_USD, 0, true);
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, 0, true);

        adaptor = new UniswapV3Adaptor(
            ICentralRegistry(address(centralRegistry)),
            IStaticOracle(uniswapV3Oracle),
            WETH
        );
        UniswapV3Adaptor.AdaptorData memory adaptorData;
        adaptorData.priceSource = WBTC_WETH;
        adaptorData.secondsAgo = 3600;
        adaptor.addAsset(WBTC, adaptorData);

        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(WETH, address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));

        oracleRouter.addApprovedAdaptor(address(adaptor));
        oracleRouter.addAssetPriceFeed(WBTC, address(adaptor));
    }

    function testRevertWhenUnderlyingChainAssetPriceNotSet() public {
        chainlinkAdaptor.removeAsset(WETH);

        (, uint256 errorCode) = oracleRouter.getPrice(WBTC, true, false);
        assertEq(errorCode, 2);
    }

    function testReturnsCorrectPriceInUSD() public {
        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            WBTC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testReturnsCorrectPriceInETH() public {
        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            WBTC,
            false,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPriceInUSD();
        testReturnsCorrectPriceInETH();

        adaptor.removeAsset(WBTC);
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(WBTC, true, false);
    }

    function testRevertGetPriceInETH__NotSupported() public {
        vm.expectRevert(
            UniswapV3Adaptor.UniswapV3Adaptor__AssetIsNotSupported.selector
        );
        adaptor.getPrice(address(0), false, false);
    }

    function testRevertAddAsset__SecondsAgoIsLessThanMinimum() public {
        UniswapV3Adaptor.AdaptorData memory adaptorData;
        adaptorData.priceSource = WBTC_WETH;
        adaptorData.secondsAgo = 240;

        vm.expectRevert(
            UniswapV3Adaptor
                .UniswapV3Adaptor__SecondsAgoIsLessThanMinimum
                .selector
        );
        adaptor.addAsset(WBTC, adaptorData);
    }

    function testRevertAddAsset__AssetIsNotSupported() public {
        UniswapV3Adaptor.AdaptorData memory adaptorData;
        adaptorData.priceSource = WBTC_WETH;
        adaptorData.secondsAgo = 3600;
        vm.expectRevert(
            UniswapV3Adaptor.UniswapV3Adaptor__AssetIsNotSupported.selector
        );
        adaptor.addAsset(USDC, adaptorData);
    }

    function testAddAssetForDifferentPair() public {
        testReturnsCorrectPriceInUSD();
        testReturnsCorrectPriceInETH();

        UniswapV3Adaptor.AdaptorData memory adaptorData;
        adaptorData.priceSource = WBTC_USDC;
        adaptorData.secondsAgo = 3600;
        adaptor.addAsset(WBTC, adaptorData);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(
            UniswapV3Adaptor.UniswapV3Adaptor__AssetIsNotSupported.selector
        );
        adaptor.removeAsset(USDC);
    }

    function testGetPriceFromDifferentPair() public {
        UniswapV3Adaptor.AdaptorData memory adaptorData;
        adaptorData.priceSource = WBTC_USDC;
        adaptorData.secondsAgo = 3600;
        adaptor.addAsset(USDC, adaptorData);

        PriceReturnData memory data = adaptor.getPrice(USDC, true, false);
        assertGt(data.price, 0);
        assertEq(data.hadError, false);
        assertEq(data.inUSD, true);

        data = adaptor.getPrice(USDC, false, false);
        assertGt(data.price, 0);
        assertEq(data.hadError, false);
        assertEq(data.inUSD, false);
    }

    function testRevertRemoveAsset__Unauthorized() public {
        vm.expectRevert(
            BaseOracleAdaptor.BaseOracleAdaptor__Unauthorized.selector
        );
        vm.startPrank(address(0));
        adaptor.removeAsset(WBTC);
        vm.stopPrank();
    }
}
