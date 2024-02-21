// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { PendlePrincipalTokenAdaptor } from "contracts/oracles/adaptors/pendle/PendlePrincipalTokenAdaptor.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { IPMarket } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract TestPendlePTTokenAdaptor is TestBaseOracleRouter {
    address internal constant _PT_ORACLE =
        0x14030836AEc15B2ad48bB097bd57032559339c92;

    address private _STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private _PT_STETH = 0x7758896b6AC966BbABcf143eFA963030f17D3EdF; // PT-stETH-26DEC24
    address private _LP_STETH = 0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2; // PT-stETH-26DEC24/SY-stETH Market

    PendlePrincipalTokenAdaptor adapter;

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        _deployOracleRouter();

        adapter = new PendlePrincipalTokenAdaptor(
            ICentralRegistry(address(centralRegistry)),
            IPendlePTOracle(_PT_ORACLE)
        );
    }

    function testRevertWhenUnderlyingAssetPriceNotSet() public {
        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = _STETH;
        adapterData.quoteAssetDecimals = 18;
        vm.expectRevert(
            PendlePrincipalTokenAdaptor
                .PendlePrincipalTokenAdaptor__QuoteAssetIsNotSupported
                .selector
        );
        adapter.addAsset(_PT_STETH, adapterData);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(_ETH_ADDRESS, _CHAINLINK_ETH_USD, 0, true);
        chainlinkAdaptor.addAsset(_STETH, _CHAINLINK_ETH_USD, 0, true);
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(_STETH, address(chainlinkAdaptor));

        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = _STETH;
        adapterData.quoteAssetDecimals = 18;
        adapter.addAsset(_PT_STETH, adapterData);

        oracleRouter.addApprovedAdaptor(address(adapter));
        oracleRouter.addAssetPriceFeed(_PT_STETH, address(adapter));

        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            _PT_STETH,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adapter.removeAsset(_PT_STETH);
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPrice(_PT_STETH, true, false);
    }

    function testRevertAddAsset__WrongMarket() public {
        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = _STETH;
        adapterData.quoteAssetDecimals = 18;

        vm.expectRevert(PendlePrincipalTokenAdaptor.PendlePrincipalTokenAdaptor__WrongMarket.selector);
        adapter.addAsset(address(0), adapterData);
    }

    function testRevertAddAsset__CallIncreaseCardinality() public {
        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 1000;
        adapterData.quoteAsset = _STETH;
        adapterData.quoteAssetDecimals = 18;

        vm.expectRevert(PendlePrincipalTokenAdaptor.PendlePrincipalTokenAdaptor__CallIncreaseCardinality.selector);
        adapter.addAsset(_PT_STETH, adapterData);
    }

    function testRevertAddAsset__TwapDurationIsLessThanMinimum() public {
        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 6;
        adapterData.quoteAsset = _STETH;
        adapterData.quoteAssetDecimals = 18;

        vm.expectRevert(PendlePrincipalTokenAdaptor.PendlePrincipalTokenAdaptor__TwapDurationIsLessThanMinimum.selector);
        adapter.addAsset(_PT_STETH, adapterData);
    }

    function testRevertAddAsset__WrongQuote() public {
        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = address(0);
        adapterData.quoteAssetDecimals = 18;

        vm.expectRevert(PendlePrincipalTokenAdaptor.PendlePrincipalTokenAdaptor__WrongQuote.selector);
        adapter.addAsset(_PT_STETH, adapterData);
    }

    function testCanUpdateAsset() public {
        // set quote asset
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(_ETH_ADDRESS, _CHAINLINK_ETH_USD, 0, true);
        chainlinkAdaptor.addAsset(_STETH, _CHAINLINK_ETH_USD, 0, true);
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(_STETH, address(chainlinkAdaptor));

        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = _STETH;
        adapterData.quoteAssetDecimals = 18;
        adapter.addAsset(_PT_STETH, adapterData);
        adapter.addAsset(_PT_STETH, adapterData);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(PendlePrincipalTokenAdaptor.PendlePrincipalTokenAdaptor__AssetIsNotSupported.selector);
        adapter.removeAsset(_PT_STETH);
    }
}
