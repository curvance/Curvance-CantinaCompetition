// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { CamelotStableLPAdaptor } from "contracts/oracles/adaptors/camelot/CamelotStableLPAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { BaseStableLPAdaptor } from "contracts/oracles/adaptors/utils/BaseStableLPAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";

contract TestCamelotStableLPAdapter is TestBaseOracleRouter {
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
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        adapter = new CamelotStableLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adapter.addAsset(DAI_USDC);

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

        oracleRouter.addApprovedAdaptor(address(adapter));
        oracleRouter.addAssetPriceFeed(DAI_USDC, address(adapter));
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

        adapter.removeAsset(DAI_USDC);
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(DAI_USDC, true, false);
    }

    function testRevertAddAsset__AssetIsNotStableLP() public {
        vm.expectRevert(
            CamelotStableLPAdaptor
                .CamelotStableLPAdaptor__AssetIsNotStableLP
                .selector
        );
        adapter.addAsset(0x84652bb2539513BAf36e225c930Fdd8eaa63CE27);
    }

    function testCanUpdateAsset() public {
        adapter.addAsset(DAI_USDC);
        adapter.addAsset(DAI_USDC);
    }

    function testRevertGetPrice__AssetIsNotSupported() public {
        vm.expectRevert(
            BaseStableLPAdaptor
                .BaseStableLPAdaptor__AssetIsNotSupported
                .selector
        );
        adapter.getPrice(address(0), true, false);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(
            BaseStableLPAdaptor
                .BaseStableLPAdaptor__AssetIsNotSupported
                .selector
        );
        adapter.removeAsset(address(0));
    }
}
