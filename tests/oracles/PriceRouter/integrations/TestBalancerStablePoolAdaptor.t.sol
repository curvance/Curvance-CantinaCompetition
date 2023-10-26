// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerPoolAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract TestBalancerStablePoolAdapter is TestBasePriceRouter {
    address internal constant _BALANCER_VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private WETH = 0x4200000000000000000000000000000000000006;
    address private RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    address private CHAINLINK_PRICE_FEED_ETH =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private CHAINLINK_PRICE_FEED_RETH_ETH =
        0x536218f9E9Eb48863970252233c8F271f554C2d0;

    address private WETH_RETH = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    bytes32 private WETH_RETH_POOLID =
        0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;

    BalancerStablePoolAdaptor adapter;

    function setUp() public override {
        _fork();

        _deployCentralRegistry();
        _deployPriceRouter();

        adapter = new BalancerStablePoolAdaptor(
            ICentralRegistry(address(centralRegistry)),
            IVault(_BALANCER_VAULT)
        );
    }

    function testRevertWhenUnderlyingAssetPriceNotSet() public {
        BalancerStablePoolAdaptor.AdaptorData memory adapterData;
        adapterData.poolId = WETH_RETH_POOLID;
        adapterData.poolDecimals = 18;
        adapterData.rateProviderDecimals[0] = 18;
        adapterData.rateProviders[
            0
        ] = 0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F;
        adapterData.underlyingOrConstituent[0] = RETH;
        adapterData.underlyingOrConstituent[1] = WETH;
        vm.expectRevert(
            BalancerStablePoolAdaptor
                .BalancerStablePoolAdaptor__ConfigurationError
                .selector
        );
        adapter.addAsset(WETH_RETH, adapterData);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
        chainlinkAdaptor.addAsset(WETH, CHAINLINK_PRICE_FEED_ETH, true);
        chainlinkAdaptor.addAsset(RETH, CHAINLINK_PRICE_FEED_RETH_ETH, false);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(WETH, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(RETH, address(chainlinkAdaptor));

        BalancerStablePoolAdaptor.AdaptorData memory adapterData;
        adapterData.poolId = WETH_RETH_POOLID;
        adapterData.poolDecimals = 18;
        adapterData.rateProviderDecimals[0] = 18;
        adapterData.rateProviders[
            0
        ] = 0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F;
        adapterData.underlyingOrConstituent[0] = RETH;
        adapterData.underlyingOrConstituent[1] = WETH;
        adapter.addAsset(WETH_RETH, adapterData);

        priceRouter.addApprovedAdaptor(address(adapter));
        priceRouter.addAssetPriceFeed(WETH_RETH, address(adapter));

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            WETH_RETH,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adapter.removeAsset(WETH_RETH);
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(WETH_RETH, true, false);
    }
}
