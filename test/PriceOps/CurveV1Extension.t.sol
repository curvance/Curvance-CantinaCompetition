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

contract CurveV1ExtensionTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    uint256 public ETH_PRICE_USD;
    uint256 public WBTC_PRICE_ETH;
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
    address private WBTC_ETH_FEED = 0xdeb288F737066589598e9214E782fa5A8eD689e8;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address private USDC_ETH_FEED = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private DAI_ETH_FEED = 0x773616E4d11A78F511299002da57A0a94577F1f4;
    address private USDT_ETH_FEED = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;

    // Mock Data Feeds
    MockDataFeed private MOCK_WETH_USD_FEED;
    MockDataFeed private MOCK_STETH_USD_FEED;
    MockDataFeed private MOCK_STETH_ETH_FEED;
    MockDataFeed private MOCK_USDT_USD_FEED;
    MockDataFeed private MOCK_USDC_USD_FEED;
    MockDataFeed private MOCK_USDC_ETH_FEED;
    MockDataFeed private MOCK_USDT_ETH_FEED;
    MockDataFeed private MOCK_DAI_ETH_FEED;
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
        WBTC_PRICE_ETH = uint256(IChainlinkAggregator(WBTC_ETH_FEED).latestAnswer());
        USDC_PRICE_USD = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        FRAX_PRICE_USD = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());

        MOCK_WETH_USD_FEED = new MockDataFeed(WETH_USD_FEED);
        MOCK_USDT_USD_FEED = new MockDataFeed(USDT_USD_FEED);
        MOCK_USDC_USD_FEED = new MockDataFeed(USDC_USD_FEED);
        MOCK_USDC_ETH_FEED = new MockDataFeed(USDC_ETH_FEED);
        MOCK_DAI_ETH_FEED = new MockDataFeed(DAI_ETH_FEED);
        MOCK_USDT_ETH_FEED = new MockDataFeed(USDT_ETH_FEED);
        MOCK_DAI_USD_FEED = new MockDataFeed(DAI_USD_FEED);

        PriceOps.ChainlinkSourceStorage memory stor;
        stor.inUsd = true;

        // Deploy PriceOps.
        priceOps = new PriceOps(address(MOCK_WETH_USD_FEED), abi.encode(stor));

        curveV1Extension = new CurveV1Extension(priceOps);

        // Setup Chainlink Sources.
        // USDC-USD
        usdcUsdSource = priceOps.addSource(
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

        uint64 usdcEthSource = priceOps.addSource(
            USDC,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDC_ETH_FEED),
            abi.encode(stor)
        );

        uint16 divergence = 0.01e4;

        priceOps.addAsset(USDC, usdcUsdSource, usdcEthSource, divergence);
        priceOps.addAsset(DAI, daiEthSource, 0, 0);
        priceOps.addAsset(USDT, usdtEthSource, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        CURVE V1 SOURCE PRICING 
    //////////////////////////////////////////////////////////////*/

    function testCurveV1Source() external {
        ICurvePool pool = ICurvePool(curve3CrvPool);
        uint64 crv3PoolSource = priceOps.addSource(
            CRV_DAI_USDC_USDT,
            PriceOps.Descriptor.EXTENSION,
            address(curveV1Extension),
            abi.encode(curve3CrvPool)
        );
        priceOps.addAsset(CRV_DAI_USDC_USDT, crv3PoolSource, 0, 0);
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
