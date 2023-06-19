// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { ERC20 } from "contracts/base/ERC20.sol";
import { PriceOps } from "contracts/PricingOperations/PriceOps.sol";
import { IChainlinkAggregator } from "contracts/interfaces/IChainlinkAggregator.sol";
import { ICurvePool } from "contracts/interfaces/Curve/ICurvePool.sol";
import { ICurveFi } from "contracts/interfaces/Curve/ICurveFi.sol";
import { CurveV1Extension } from "contracts/PricingOperations/Extensions/CurveV1Extension.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "contracts/utils/Math.sol";

contract CurveV1ExtensionTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    uint256 public ETH_PRICE_USD;
    uint256 public USDC_PRICE_USD;
    uint256 public USDC_PRICE_ETH;

    PriceOps private priceOps;
    CurveV1Extension private curveV1Extension;

    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Data feeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private USDC_ETH_FEED = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address private DAI_ETH_FEED = 0x773616E4d11A78F511299002da57A0a94577F1f4;
    address private USDT_ETH_FEED = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;

    // Mock Data Feeds
    MockDataFeed private MOCK_WETH_USD_FEED;
    MockDataFeed private MOCK_USDC_USD_FEED;
    MockDataFeed private MOCK_USDC_ETH_FEED;
    MockDataFeed private MOCK_USDT_ETH_FEED;
    MockDataFeed private MOCK_DAI_ETH_FEED;

    // Curve Assets
    address private CRV_DAI_USDC_USDT = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address private curve3CrvPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    function setUp() external {
        ETH_PRICE_USD = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        USDC_PRICE_USD = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        USDC_PRICE_ETH = uint256(IChainlinkAggregator(USDC_ETH_FEED).latestAnswer());

        MOCK_WETH_USD_FEED = new MockDataFeed(WETH_USD_FEED);
        MOCK_USDC_USD_FEED = new MockDataFeed(USDC_USD_FEED);
        MOCK_USDC_ETH_FEED = new MockDataFeed(USDC_ETH_FEED);
        MOCK_DAI_ETH_FEED = new MockDataFeed(DAI_ETH_FEED);
        MOCK_USDT_ETH_FEED = new MockDataFeed(USDT_ETH_FEED);

        PriceOps.ChainlinkSourceStorage memory stor;
        stor.inUsd = true;

        // Deploy PriceOps.
        priceOps = new PriceOps(address(MOCK_WETH_USD_FEED), abi.encode(stor));

        curveV1Extension = new CurveV1Extension(priceOps);

        // Setup Chainlink Sources.
        // USDC-USD
        uint64 usdcUsdSource = priceOps.addSource(
            USDC,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDC_USD_FEED),
            abi.encode(stor)
        );
        stor.inUsd = false;
        // DAI-ETH
        uint64 daiEthSource = priceOps.addSource(
            DAI,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_DAI_ETH_FEED),
            abi.encode(stor)
        );
        // USDT-ETH
        uint64 usdtEthSource = priceOps.addSource(
            USDT,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDT_ETH_FEED),
            abi.encode(stor)
        );
        // USDC-ETH
        uint64 usdcEthSource = priceOps.addSource(
            USDC,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDC_ETH_FEED),
            abi.encode(stor)
        );

        // Allowed divergence for USDC sources, 1%
        uint16 divergence = 0.01e4;

        priceOps.addAsset(USDC, usdcUsdSource, usdcEthSource, divergence);
        priceOps.addAsset(DAI, daiEthSource, 0, 0);
        priceOps.addAsset(USDT, usdtEthSource, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        CURVE V1 SOURCE PRICING 
    //////////////////////////////////////////////////////////////*/

    function testCurveV1Source3Pool(uint256 usdcIn) external {
        usdcIn = bound(usdcIn, 1e6, 100_000_000e6);
        ICurvePool pool = ICurvePool(curve3CrvPool);
        uint64 crv3PoolSource = priceOps.addSource(
            CRV_DAI_USDC_USDT,
            PriceOps.Descriptor.EXTENSION,
            address(curveV1Extension),
            abi.encode(curve3CrvPool)
        );
        priceOps.addAsset(CRV_DAI_USDC_USDT, crv3PoolSource, 0, 0);

        // Query price.
        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD.mulDivDown(pool.get_virtual_price(), 1e18), ETH_PRICE_USD),
            0.01e18,
            "upper should be approx equal to 1/ETH_PRICE_USD."
        );
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 0, "There should be no error.");

        ICurveFi threePool = ICurveFi(curve3CrvPool);

        deal(USDC, address(this), usdcIn);
        ERC20(USDC).approve(curve3CrvPool, usdcIn);
        uint256[3] memory amounts = [0, usdcIn, 0];
        threePool.add_liquidity(amounts, 0);

        uint256 lpReceived = ERC20(CRV_DAI_USDC_USDT).balanceOf(address(this));

        uint256 valueIn = usdcIn.mulDivDown(USDC_PRICE_ETH, 10 ** ERC20(USDC).decimals());
        uint256 valueOut = lpReceived.mulDivDown(upper, 10 ** ERC20(CRV_DAI_USDC_USDT).decimals());

        assertApproxEqRel(valueIn, valueOut, 0.01e18, "Value in should approximately equal value out.");
    }

    // TODO add any other curve V1 pools we want to use.

    /*//////////////////////////////////////////////////////////////
                    CURVE V1 SOURCE ERRORS 
    //////////////////////////////////////////////////////////////*/

    function testCurveV1SourceErrorCodes() external {
        ICurvePool pool = ICurvePool(curve3CrvPool);
        uint64 crv3PoolSource = priceOps.addSource(
            CRV_DAI_USDC_USDT,
            PriceOps.Descriptor.EXTENSION,
            address(curveV1Extension),
            abi.encode(curve3CrvPool)
        );
        priceOps.addAsset(CRV_DAI_USDC_USDT, crv3PoolSource, 0, 0);

        // Should be no error codes.
        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD.mulDivDown(pool.get_virtual_price(), 1e18), ETH_PRICE_USD),
            0.01e18,
            "upper should be approx equal to 1/ETH_PRICE_USD."
        );
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 0, "There should be no error.");

        // Make DAI source bad.
        MOCK_DAI_ETH_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
        assertEq(upper, 0, "Extension is blind to DAIs price so return BAD_SOURCE and zeroes.");
        assertEq(upper, lower, "Upper should equal lower.");
        assertEq(errorCode, 2, "There should be a BAD_SOURCE error.");

        // Make DAI source good, but 1 USDC source bad.
        MOCK_DAI_ETH_FEED.setMockUpdatedAt(block.timestamp);
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD.mulDivDown(pool.get_virtual_price(), 1e18), ETH_PRICE_USD),
            0.01e18,
            "upper should be approx equal to 1/ETH_PRICE_USD."
        );
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 1, "Error should be CAUTION.");

        // Make USDC source good, but have USDC sources diverge.
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp);
        uint256 usdcDivergence = 0.03e18;
        MOCK_USDC_USD_FEED.setMockAnswer(int256(uint256(1e8).mulDivDown(1e18 + usdcDivergence, 1e18)));
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD.mulDivDown(pool.get_virtual_price(), 1e18), ETH_PRICE_USD),
            2 * usdcDivergence,
            "upper should be approx equal to 1/ETH_PRICE_USD."
        );
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 2 * usdcDivergence, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 1, "Error should be CAUTION.");

        // Reset bad USDC source.
        MOCK_USDC_USD_FEED.setMockAnswer(0);

        // Make the Eth -> Usd source bad so that one USDC source is bad.
        MOCK_WETH_USD_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD.mulDivDown(pool.get_virtual_price(), 1e18), ETH_PRICE_USD),
            0.01e18,
            "upper should be approx equal to 1/ETH_PRICE_USD."
        );
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 1, "Error should be CAUTION.");

        // Reset Eth->Usd timestamp.
        MOCK_WETH_USD_FEED.setMockUpdatedAt(block.timestamp);

        // Should be error free.
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD.mulDivDown(pool.get_virtual_price(), 1e18), ETH_PRICE_USD),
            0.01e18,
            "upper should be approx equal to 1/ETH_PRICE_USD."
        );
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 0, "There should be no error.");

        // TODO if need be add case where virtual price exceedes bound and make sure 2 error is returned.
    }
}
