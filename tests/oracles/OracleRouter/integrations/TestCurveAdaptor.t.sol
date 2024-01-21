// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { CurveAdaptor } from "contracts/oracles/adaptors/curve/CurveAdaptor.sol";
import { CurveBaseAdaptor } from "contracts/oracles/adaptors/curve/CurveBaseAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract TestCurveAdaptor is TestBaseOracleRouter {
    address private CHAINLINK_PRICE_FEED_ETH =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private CHAINLINK_PRICE_FEED_STETH =
        0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    address private ETH_STETH = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
    address private ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    CurveAdaptor adaptor;

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        _deployOracleRouter();

        adaptor = new CurveAdaptor(ICentralRegistry(address(centralRegistry)));

        adaptor.setReentrancyConfig(2, 10000);
    }

    function testRevertWhenUnderlyingAssetPriceNotSet() public {
        adaptor.addAsset(ETH_STETH, ETH_STETH);

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(ETH_STETH, true, false);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(ETH, CHAINLINK_PRICE_FEED_ETH, 0, true);
        chainlinkAdaptor.addAsset(STETH, CHAINLINK_PRICE_FEED_STETH, 0, true);
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(ETH, address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(STETH, address(chainlinkAdaptor));

        adaptor.addAsset(ETH_STETH, ETH_STETH);

        oracleRouter.addApprovedAdaptor(address(adaptor));
        oracleRouter.addAssetPriceFeed(ETH_STETH, address(adaptor));
        (uint256 ethPrice, ) = oracleRouter.getPrice(ETH, true, false);

        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            ETH_STETH,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertApproxEqRel(price, ethPrice, 0.02 ether);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();
        adaptor.removeAsset(ETH_STETH);

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(ETH_STETH, true, false);
    }
}
