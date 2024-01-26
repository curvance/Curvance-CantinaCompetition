// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { VelodromeVolatileLPAdaptor } from "contracts/oracles/adaptors/velodrome/VelodromeVolatileLPAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";

contract TestOracleRouter is TestBaseOracleRouter {
    address private WETH = address(0x4200000000000000000000000000000000000006);
    address private USDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    address private CHAINLINK_PRICE_FEED_ETH =
        0xb7B9A39CC63f856b90B364911CC324dC46aC1770;
    address private CHAINLINK_PRICE_FEED_USDC =
        0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;

    address private veloRouter =
        address(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    address private WETH_USDC =
        address(0x0493Bf8b6DBB159Ce2Db2E0E8403E753Abd1235b);

    VelodromeVolatileLPAdaptor adapter;

    function setUp() public override {
        _fork("ETH_NODE_URI_OPTIMISM", 110333246);

        _deployCentralRegistry();
        _deployMarketManager();
        _deployDynamicInterestRateModel();

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry)),
            CHAINLINK_PRICE_FEED_ETH
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, 0, true);
        chainlinkAdaptor.addAsset(WETH, CHAINLINK_PRICE_FEED_ETH, 0, true);
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(WETH, address(chainlinkAdaptor));

        adapter = new VelodromeVolatileLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adapter.addAsset(WETH_USDC);

        oracleRouter.addApprovedAdaptor(address(adapter));
        oracleRouter.addAssetPriceFeed(WETH_USDC, address(adapter));
    }

    function testReturnsCorrectPrice() public {
        uint256 higherPrice;
        uint256 lowerPrice;
        uint256 errorCode;

        (higherPrice, errorCode) = oracleRouter.getPrice(
            WETH_USDC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(higherPrice, 0);

        (lowerPrice, errorCode) = oracleRouter.getPrice(WETH_USDC, true, true);
        assertEq(errorCode, 0);
        assertGt(lowerPrice, 0);
        assertEq(higherPrice, lowerPrice);

        (higherPrice, errorCode) = oracleRouter.getPrice(
            WETH_USDC,
            false,
            false
        );
        assertEq(errorCode, 0);
        assertGt(higherPrice, 0);

        (lowerPrice, errorCode) = oracleRouter.getPrice(
            WETH_USDC,
            false,
            true
        );
        assertEq(errorCode, 0);
        assertGt(lowerPrice, 0);
        assertEq(higherPrice, lowerPrice);
    }

    function testRevertAfterAssetRemove() public {
        adapter.removeAsset(WETH_USDC);
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(WETH_USDC, true, false);
    }

    function testReturnsCorrectPriceForMTokens() public {
        DToken dUSDC = new DToken(
            ICentralRegistry(address(centralRegistry)),
            USDC,
            address(marketManager),
            address(interestRateModel)
        );
        // support market
        deal(USDC, address(this), 200000e6);
        IERC20(USDC).approve(address(dUSDC), 200000e6);
        marketManager.listToken(address(dUSDC));

        oracleRouter.addMTokenSupport(address(dUSDC));

        uint256 dUSDCPrice;
        uint256 usdcPrice;
        uint256 errorCode;

        (dUSDCPrice, errorCode) = oracleRouter.getPrice(
            address(dUSDC),
            true,
            false
        );
        assertEq(errorCode, 0);
        assertApproxEqRel(dUSDCPrice, 1 ether, 0.01 ether);

        (usdcPrice, errorCode) = oracleRouter.getPrice(USDC, true, false);
        assertEq(errorCode, 0);
        assertEq(dUSDCPrice, usdcPrice);
    }

    function testRevertWhenAdaptorNotApproved() public {
        oracleRouter.removeApprovedAdaptor(address(adapter));

        vm.expectRevert(
            OracleRouter.OracleRouter__AdaptorIsNotApproved.selector
        );
        oracleRouter.getPrice(WETH_USDC, true, false);
    }
}
