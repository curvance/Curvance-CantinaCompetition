// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PendleLPTokenAdaptor } from "contracts/oracles/adaptors/pendle/PendleLPTokenAdaptor.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract TestPendleLPTokenAdapter is TestBasePriceRouter {
    address internal constant _PT_ORACLE =
        0x14030836AEc15B2ad48bB097bd57032559339c92;

    address private _STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private _PT_STETH = 0x7758896b6AC966BbABcf143eFA963030f17D3EdF; // PT-stETH-26DEC24
    address private _LP_STETH = 0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2; // PT-stETH-26DEC24/SY-stETH Market

    PendleLPTokenAdaptor adapter;

    function setUp() public override {
        _fork();

        _deployCentralRegistry();
        _deployPriceRouter();

        adapter = new PendleLPTokenAdaptor(
            ICentralRegistry(address(centralRegistry)),
            IPendlePTOracle(_PT_ORACLE)
        );
    }

    function testRevertWhenUnderlyingAssetPriceNotSet() public {
        PendleLPTokenAdaptor.AdaptorData memory adapterData;
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = _STETH;
        adapterData.pt = _PT_STETH;
        adapterData.quoteAssetDecimals = 18;
        vm.expectRevert(
            PendleLPTokenAdaptor
                .PendleLPTokenAdaptor__QuoteAssetIsNotSupported
                .selector
        );
        adapter.addAsset(_LP_STETH, adapterData);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(_STETH, _CHAINLINK_ETH_USD, true);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(_STETH, address(chainlinkAdaptor));

        PendleLPTokenAdaptor.AdaptorData memory adapterData;
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = _STETH;
        adapterData.pt = _PT_STETH;
        adapterData.quoteAssetDecimals = 18;
        adapter.addAsset(_LP_STETH, adapterData);

        priceRouter.addApprovedAdaptor(address(adapter));
        priceRouter.addAssetPriceFeed(_LP_STETH, address(adapter));

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            _LP_STETH,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adapter.removeAsset(_LP_STETH);
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(_LP_STETH, true, false);
    }
}
