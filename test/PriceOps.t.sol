// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { SafeTransferLib } from "src/base/SafeTransferLib.sol";
import { DepositRouterV2 as DepositRouter } from "src/DepositRouterV2.sol";
import { ConvexPositionVault, BasePositionVault } from "src/positions/ConvexPositionVault.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { PriceOps } from "src/PricingOperations/PriceOps.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { ICurvePool } from "src/interfaces/Curve/ICurvePool.sol";
import { UniswapV3Pool } from "src/interfaces/Uniswap/UniswapV3Pool.sol";
import { CurveV1Extension } from "src/PricingOperations/Extensions/CurveV1Extension.sol";
import { CurveV2Extension } from "src/PricingOperations/Extensions/CurveV2Extension.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// import { MockGasFeed } from "src/mocks/MockGasFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract PriceOpsTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    uint256 public ETH_PRICE_USD;
    uint256 public USDC_PRICE_USD;
    uint256 public FRAX_PRICE_USD;

    PriceOps private priceOps;
    CurveV1Extension private curveV1Extension;
    CurveV2Extension private curveV2Extension;
    // MockGasFeed private gasFeed;

    address private operatorAlpha = vm.addr(111);
    address private ownerAlpha = vm.addr(1110);
    address private operatorBeta = vm.addr(222);
    address private ownerBeta = vm.addr(2220);

    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    // Data feeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address private STETH_ETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address private USDC_ETH_FEED = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // Mock Data Feeds
    MockDataFeed private MOCK_WETH_USD_FEED;
    MockDataFeed private MOCK_STETH_USD_FEED;
    MockDataFeed private MOCK_STETH_ETH_FEED;
    MockDataFeed private MOCK_USDT_USD_FEED;
    MockDataFeed private MOCK_USDC_USD_FEED;
    MockDataFeed private MOCK_USDC_ETH_FEED;
    MockDataFeed private MOCK_DAI_USD_FEED;

    uint64 public usdcUsdSource;

    // Uniswap V3 Pools
    address private WBTC_WETH_05_POOL = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0;
    address private FRAX_USDC_05_POOL = 0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52;

    // Curve Assets
    address private CRV_DAI_USDC_USDT = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address private curve3CrvPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address private CRV_3_CRYPTO = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;
    address private curve3CryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;

    ICurvePool stEthEth = ICurvePool(payable(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022));

    function setUp() external {
        ETH_PRICE_USD = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        USDC_PRICE_USD = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        FRAX_PRICE_USD = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());

        MOCK_WETH_USD_FEED = new MockDataFeed(WETH_USD_FEED);
        MOCK_STETH_USD_FEED = new MockDataFeed(STETH_USD_FEED);
        MOCK_STETH_ETH_FEED = new MockDataFeed(STETH_ETH_FEED);
        MOCK_USDT_USD_FEED = new MockDataFeed(USDT_USD_FEED);
        MOCK_USDC_USD_FEED = new MockDataFeed(USDC_USD_FEED);
        MOCK_USDC_ETH_FEED = new MockDataFeed(USDC_ETH_FEED);
        MOCK_DAI_USD_FEED = new MockDataFeed(DAI_USD_FEED);

        PriceOps.ChainlinkSourceStorage memory stor;
        stor.inUsd = true;

        // Deploy PriceOps.
        priceOps = new PriceOps(address(MOCK_WETH_USD_FEED), abi.encode(stor));

        // curveV1Extension = new CurveV1Extension(priceOps);
        // curveV2Extension = new CurveV2Extension(priceOps);

        // Setup Chainlink Sources.
        // USDC-USD
        usdcUsdSource = priceOps.addSource(
            USDC,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDC_USD_FEED),
            abi.encode(stor)
        );
        // DAI-USD
        uint64 daiUsdSource = priceOps.addSource(
            DAI,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_DAI_USD_FEED),
            abi.encode(stor)
        );
        // USDT-USD
        uint64 usdtUsdSource = priceOps.addSource(
            USDT,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDT_USD_FEED),
            abi.encode(stor)
        );
        // STETH-USD
        // uint64 stethUsdSource = priceOps.addSource(
        //     STETH,
        //     PriceOps.Descriptor.CHAINLINK,
        //     STETH_USD_FEED,
        //     abi.encode(stor)
        // );
        // // STETH-ETH
        // stor.inUsd = false;
        // uint64 stethEthSource = priceOps.addSource(
        //     STETH,
        //     PriceOps.Descriptor.CHAINLINK,
        //     STETH_ETH_FEED,
        //     abi.encode(stor)
        // );
        // // uint64 usdcEthSource = priceOps.addSource(USDC, PriceOps.Descriptor.CHAINLINK, USDC_ETH_FEED, abi.encode(stor));
        // // priceOps.addAsset(WETH, ethUsdSource, 0);
        priceOps.addAsset(USDC, usdcUsdSource, 0, 0);
        priceOps.addAsset(DAI, daiUsdSource, 0, 0);
        priceOps.addAsset(USDT, usdtUsdSource, 0, 0);
        // priceOps.addAsset(STETH, stethUsdSource, stethEthSource);
        // UniswapV3Pool(USDC_WETH_05_POOL).increaseObservationCardinalityNext(900);
    }

    // function testPriceOpsHappyPath() external {
    //     (uint256 upper, uint256 lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(STETH);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);

    //     // WBTC-WETH TWAP
    //     PriceOps.TwapSourceStorage memory twapStor;
    //     twapStor.secondsAgo = 600;
    //     twapStor.baseToken = WBTC;
    //     twapStor.quoteToken = WETH;
    //     twapStor.baseDecimals = ERC20(WBTC).decimals();
    //     uint64 wbtcWethSource_600 = priceOps.addSource(
    //         WBTC,
    //         PriceOps.Descriptor.UNIV3_TWAP,
    //         WBTC_WETH_05_POOL,
    //         abi.encode(twapStor)
    //     );
    //     priceOps.addAsset(WBTC, wbtcWethSource_600, 0);

    //     twapStor.secondsAgo = 3_600;
    //     twapStor.baseToken = WBTC;
    //     twapStor.quoteToken = WETH;
    //     twapStor.baseDecimals = ERC20(WBTC).decimals();
    //     uint64 wbtcWethSource_3_600 = priceOps.addSource(
    //         WBTC,
    //         PriceOps.Descriptor.UNIV3_TWAP,
    //         WBTC_WETH_05_POOL,
    //         abi.encode(twapStor)
    //     );
    //     priceOps.addAsset(WBTC, wbtcWethSource_600, wbtcWethSource_3_600);

    //     (upper, lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(WBTC);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);

    //     uint64 crv3PoolSource = priceOps.addSource(
    //         CRV_DAI_USDC_USDT,
    //         PriceOps.Descriptor.EXTENSION,
    //         address(curveV1Extension),
    //         abi.encode(curve3CrvPool)
    //     );

    //     priceOps.addAsset(CRV_DAI_USDC_USDT, crv3PoolSource, 0);

    //     (upper, lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);

    //     uint64 crvTriCryptoSource = priceOps.addSource(
    //         CRV_3_CRYPTO,
    //         PriceOps.Descriptor.EXTENSION,
    //         address(curveV2Extension),
    //         abi.encode(curve3CryptoPool)
    //     );

    //     priceOps.addAsset(CRV_3_CRYPTO, crvTriCryptoSource, 0);

    //     (upper, lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_3_CRYPTO);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);
    // }

    function testChainlinkSourceErrorCodes() external {
        // USDC pricing is currently fine.
        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD, ETH_PRICE_USD),
            0.000001e18,
            "USDC price should equal 1/ETH_PRICE_USD."
        );
        assertEq(upper, lower, "Upper and lower should be equal since USDC has a single source.");
        assertEq(errorCode, 0, "There should be no error code.");

        // Warp time so that answer is stale.
        vm.warp(block.timestamp + 1 days);

        // Subsequent USDC pricing calls should return an error code of 2.
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertEq(upper, 0, "USDC price should be zero since the source is bad.");
        assertEq(upper, lower, "Upper and lower should be equal since USDC has a single source.");
        assertEq(errorCode, 2, "The errorCode should be BAD_SOURCE.");

        // Alter mock feed so that answer is not stale, but reported answer is above the max.
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp);
        MOCK_USDC_USD_FEED.setMockAnswer(101e8);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertEq(upper, 0, "USDC price should be zero since the source is bad.");
        assertEq(upper, lower, "Upper and lower should be equal since USDC has a single source.");
        assertEq(errorCode, 2, "The errorCode should be BAD_SOURCE.");

        // Alter mock feed so that answer is below the min.
        MOCK_USDC_USD_FEED.setMockAnswer(0.009e8);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertEq(upper, 0, "USDC price should be zero since the source is bad.");
        assertEq(upper, lower, "Upper and lower should be equal since USDC has a single source.");
        assertEq(errorCode, 2, "The errorCode should be BAD_SOURCE.");

        // Alter mock feed so that price USDC pricing is fine, but underlying Eth Usd feed is stale, so price still reverts.
        MOCK_USDC_USD_FEED.setMockAnswer(0);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertEq(upper, 0, "USDC price should be zero since the source is bad.");
        assertEq(upper, lower, "Upper and lower should be equal since USDC has a single source.");
        assertEq(errorCode, 2, "The errorCode should be BAD_SOURCE.");

        // Update Eth Usd feed so price is not stale.
        MOCK_WETH_USD_FEED.setMockUpdatedAt(block.timestamp);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD, ETH_PRICE_USD),
            0.000001e18,
            "USDC price should equal 1/ETH_PRICE_USD."
        );
        assertEq(upper, lower, "Upper and lower should be equal since USDC has a single source.");
        assertEq(errorCode, 0, "There should be no error code.");
    }

    function testChainlinkSourcesErrorCodes() external {
        // Update USDC feed to use 2 chainlink oracle feeds.
        PriceOps.ChainlinkSourceStorage memory stor;

        // Add Chainlink Source.
        // USDC-ETH
        uint64 usdcEthSource = priceOps.addSource(
            USDC,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDC_ETH_FEED),
            abi.encode(stor)
        );

        // Edit the existing USDC sources.
        uint16 sourceDivergence = 100;
        priceOps.proposeEditAsset(USDC, usdcUsdSource, usdcEthSource, sourceDivergence);

        // Advance time so we can edit the asset.
        vm.warp(block.timestamp + priceOps.EDIT_ASSET_DELAY() + 1);

        // Update Mock Feeds so that prices are not stale.
        MOCK_WETH_USD_FEED.setMockUpdatedAt(block.timestamp);
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp);
        MOCK_USDC_ETH_FEED.setMockUpdatedAt(block.timestamp);

        // Complete edit asset.
        priceOps.editAsset(USDC, usdcUsdSource, usdcEthSource, sourceDivergence);

        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD, ETH_PRICE_USD),
            0.001e18,
            "USDC price should equal 1/ETH_PRICE_USD."
        );
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should be approx equal.");
        assertGt(upper, lower, "Upper should be greater than the lower.");
        assertEq(errorCode, 0, "There should be no error code.");

        uint256 originalUpper = upper;
        uint256 originalLower = lower;

        // If primary source is bad, errorCode should be 1.
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD, ETH_PRICE_USD),
            0.001e18,
            "USDC price should equal 1/ETH_PRICE_USD."
        );
        assertEq(upper, lower, "Upper and lower should be equal since primary is bad.");
        assertTrue(upper == originalUpper || upper == originalLower, "Values reported should be 1 of the original.");
        assertEq(errorCode, 1, "Error code should be 1.");

        // Alter primary source so price is not stale.
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp);
        // Alter secondary source so that price is stale.
        MOCK_USDC_ETH_FEED.setMockUpdatedAt(block.timestamp - 2 days);

        // If secondary source is, bad errorCode should be 1.
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(USDC_PRICE_USD, ETH_PRICE_USD),
            0.001e18,
            "USDC price should equal 1/ETH_PRICE_USD."
        );
        assertEq(upper, lower, "Upper and lower should be equal since primary is bad.");
        assertTrue(upper == originalUpper || upper == originalLower, "Values reported should be 1 of the original.");
        assertEq(errorCode, 1, "Error code should be 1.");

        // At this point we already know the chainlink checks will return BAD_SOURCE for prices outside the min/max.
        // So now check that if the sources diverge in value a 2 error code is returned.

        // Alter secondary source so price is not stale.
        MOCK_USDC_ETH_FEED.setMockUpdatedAt(block.timestamp);

        // Set secondary price to be more than 1% away from the primary price.
        // Current primary price in ETH is equal to upper.
        uint256 divergedSecondaryPrice = upper.mulDivDown(1.05e4, 1e4);

        MOCK_USDC_ETH_FEED.setMockAnswer(int256(divergedSecondaryPrice));

        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertGt(upper, 0, "USDC price upper should be nonzero since the source is bad.");
        assertGt(lower, 0, "USDC price lower should be nonzero since the source is bad.");
        assertTrue(upper != lower, "Upper and lower should not be equal since USDC prices have diverged.");
        assertEq(errorCode, 1, "The errorCode should be CAUTION.");

        // Finally if both sources are bad, a 2 error code should be returned.
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        MOCK_USDC_ETH_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(USDC);
        assertEq(upper, 0, "USDC price should be zero since the source is bad.");
        assertEq(lower, 0, "USDC price should be zero since the source is bad.");
        assertEq(errorCode, 2, "The errorCode should be BAD_SOURCE.");
    }

    // Twaps reporting assets in ETH only return error codes of 0.
    // But if the Twap reports assets in something else, then pricing the quote
    // Can lead to both CAUTION and BAD_SOURCE error codes.
    function testTwapSourceErrorCodes() external {
        // USDC-WETH TWAP
        PriceOps.TwapSourceStorage memory twapStor;
        twapStor.secondsAgo = 600;
        twapStor.baseToken = FRAX;
        twapStor.quoteToken = USDC;
        twapStor.baseDecimals = ERC20(FRAX).decimals();
        twapStor.quoteDecimals = ERC20(USDC).decimals();
        uint64 fraxUsdcSource_300 = priceOps.addSource(
            FRAX,
            PriceOps.Descriptor.UNIV3_TWAP,
            FRAX_USDC_05_POOL,
            abi.encode(twapStor)
        );
        priceOps.addAsset(FRAX, fraxUsdcSource_300, 0, 0);

        // Edit USDC so that it uses 2 Chainlink sources.
        // Update USDC feed to use 2 chainlink oracle feeds.
        PriceOps.ChainlinkSourceStorage memory stor;

        // Add Chainlink Source.
        // USDC-ETH
        uint64 usdcEthSource = priceOps.addSource(
            USDC,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDC_ETH_FEED),
            abi.encode(stor)
        );

        // Edit the existing USDC sources.
        uint16 sourceDivergence = 100;
        priceOps.proposeEditAsset(USDC, usdcUsdSource, usdcEthSource, sourceDivergence);

        // Advance time so we can edit the asset.
        vm.warp(block.timestamp + priceOps.EDIT_ASSET_DELAY() + 1);

        // Update Mock Feeds so that prices are not stale.
        MOCK_WETH_USD_FEED.setMockUpdatedAt(block.timestamp);
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp);
        MOCK_USDC_ETH_FEED.setMockUpdatedAt(block.timestamp);

        // Complete edit asset.
        priceOps.editAsset(USDC, usdcUsdSource, usdcEthSource, sourceDivergence);

        // Now make sure that if the USDC price source returns a CAUTION or BAD_SOURCE the error is bubbled up.
        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(FRAX);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(FRAX_PRICE_USD, ETH_PRICE_USD),
            0.001e18,
            "FRAX price should equal 1/ETH_PRICE_USD."
        );
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should be approx equal.");
        assertGt(upper, lower, "Upper should be greater than the lower.");
        assertEq(errorCode, 0, "There should be no error code.");

        uint256 originalUpper = upper;
        uint256 originalLower = lower;

        // If primary source is bad, errorCode should be 1.
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(FRAX);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(FRAX_PRICE_USD, ETH_PRICE_USD),
            0.001e18,
            "FRAX price should equal 1/ETH_PRICE_USD."
        );
        assertEq(upper, lower, "Upper and lower should be equal since primary is bad.");
        assertTrue(upper == originalUpper || upper == originalLower, "Values reported should be 1 of the original.");
        assertEq(errorCode, 1, "Error code should be 1.");

        // Alter secondary source so that price is stale.
        MOCK_USDC_ETH_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(FRAX);
        assertTrue(upper == 0 && lower == 0, "Values reported should be 0.");
        assertEq(errorCode, 2, "Error code should be 2.");

        // Fixing the underlying feeds allows FRAX to be priced.
        MOCK_USDC_USD_FEED.setMockUpdatedAt(block.timestamp);
        MOCK_USDC_ETH_FEED.setMockUpdatedAt(block.timestamp);

        // Now make sure that if the USDC price source returns a CAUTION or BAD_SOURCE the error is bubbled up.
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(FRAX);
        assertApproxEqRel(
            upper,
            uint256(1e18).mulDivDown(FRAX_PRICE_USD, ETH_PRICE_USD),
            0.001e18,
            "FRAX price should equal 1/ETH_PRICE_USD."
        );
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should be approx equal.");
        assertGt(upper, lower, "Upper should be greater than the lower.");
        assertEq(errorCode, 0, "There should be no error code.");
    }
}
