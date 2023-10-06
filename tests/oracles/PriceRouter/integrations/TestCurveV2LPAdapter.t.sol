// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { CurveV2LPAdapter } from "contracts/oracles/adaptors/curve/CurveV2LPAdapter.sol";
import { CurveReentrancyCheck } from "contracts/oracles/adaptors/curve/CurveReentrancyCheck.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerPoolAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { VelodromeLib } from "contracts/market/zapper/protocols/VelodromeLib.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract TestCurveV2LPAdapter is TestBasePriceRouter {
    address private CHAINLINK_PRICE_FEED_ETH =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private CHAINLINK_PRICE_FEED_STETH =
        0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    address private ETH_STETH = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
    address private ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    CurveV2LPAdapter adapter;

    function setUp() public override {
        _fork();

        _deployCentralRegistry();
        _deployPriceRouter();

        adapter = new CurveV2LPAdapter(
            ICentralRegistry(address(centralRegistry))
        );

        adapter.setReentrancyVerificationConfig(
            ETH_STETH,
            24000,
            CurveReentrancyCheck.N_COINS.TWO_COINS
        );
    }

    function testRevertWhenUnderlyingAssetPriceNotSet() public {
        adapter.addAsset(ETH_STETH, ETH_STETH);

        vm.expectRevert(0xe4558fac);
        priceRouter.getPrice(ETH_STETH, true, false);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(ETH, CHAINLINK_PRICE_FEED_ETH, true);
        chainlinkAdaptor.addAsset(STETH, CHAINLINK_PRICE_FEED_STETH, true);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(ETH, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(STETH, address(chainlinkAdaptor));

        adapter.addAsset(ETH_STETH, ETH_STETH);

        priceRouter.addApprovedAdaptor(address(adapter));
        priceRouter.addAssetPriceFeed(ETH_STETH, address(adapter));
        (uint256 ethPrice, ) = priceRouter.getPrice(ETH, true, false);

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            ETH_STETH,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertApproxEqRel(price, ethPrice, 0.02 ether);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();
        adapter.removeAsset(ETH_STETH);

        vm.expectRevert(0xe4558fac);
        priceRouter.getPrice(ETH_STETH, true, false);
    }
}
