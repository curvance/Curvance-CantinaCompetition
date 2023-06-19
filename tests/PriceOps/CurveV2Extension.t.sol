// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { ERC20 } from "contracts/base/ERC20.sol";
import { SafeTransferLib } from "contracts/base/SafeTransferLib.sol";
import { PriceOps } from "contracts/PricingOperations/PriceOps.sol";
import { IChainlinkAggregator } from "contracts/interfaces/IChainlinkAggregator.sol";
import { ICurveFi } from "contracts/interfaces/Curve/ICurveFi.sol";
import { ICurvePool } from "contracts/interfaces/Curve/ICurvePool.sol";
import { CurveV2Extension } from "contracts/PricingOperations/Extensions/CurveV2Extension.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "contracts/utils/Math.sol";

contract CurveV2ExtensionTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    uint256 public USDT_PRICE_ETH;

    PriceOps private priceOps;
    CurveV2Extension private curveV2Extension;

    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Data feeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private USDT_ETH_FEED = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;

    // Mock Data Feeds
    MockDataFeed private MOCK_WETH_USD_FEED;
    MockDataFeed private MOCK_USDT_USD_FEED;
    MockDataFeed private MOCK_USDT_ETH_FEED;

    // Curve Assets
    address private TRI_CRYPTO = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;
    address private curve3CryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address private CBETH_WETH = 0x5b6C539b224014A09B3388e51CaAA8e354c959C8;
    address private CBETH_WETH_POOL = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;

    function setUp() external {
        USDT_PRICE_ETH = uint256(IChainlinkAggregator(USDT_ETH_FEED).latestAnswer());

        MOCK_WETH_USD_FEED = new MockDataFeed(WETH_USD_FEED);
        MOCK_USDT_USD_FEED = new MockDataFeed(USDT_USD_FEED);
        MOCK_USDT_ETH_FEED = new MockDataFeed(USDT_ETH_FEED);

        PriceOps.ChainlinkSourceStorage memory stor;
        stor.inUsd = true;

        // Deploy PriceOps.
        priceOps = new PriceOps(address(MOCK_WETH_USD_FEED), abi.encode(stor));

        curveV2Extension = new CurveV2Extension(priceOps);

        // Setup Chainlink Sources.
        // USDT-USD
        uint64 usdtUsdSource = priceOps.addSource(
            USDT,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDT_USD_FEED),
            abi.encode(stor)
        );
        stor.inUsd = false;
        // USDT-ETH
        uint64 usdtEthSource = priceOps.addSource(
            USDT,
            PriceOps.Descriptor.CHAINLINK,
            address(MOCK_USDT_ETH_FEED),
            abi.encode(stor)
        );

        // Allowed divergence for USDT sources, 1%
        uint16 divergence = 0.01e4;

        priceOps.addAsset(USDT, usdtUsdSource, usdtEthSource, divergence);
    }

    /*//////////////////////////////////////////////////////////////
                        CURVE V2 SOURCE PRICING 
    //////////////////////////////////////////////////////////////*/

    function testCurveV2SourceTriCrypto(uint256 usdtIn) external {
        usdtIn = bound(usdtIn, 1e6, 1_000_000e6);
        uint64 triCryptoSource = priceOps.addSource(
            TRI_CRYPTO,
            PriceOps.Descriptor.EXTENSION,
            address(curveV2Extension),
            abi.encode(curve3CryptoPool)
        );
        priceOps.addAsset(TRI_CRYPTO, triCryptoSource, 0, 0);

        // Query price.
        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(TRI_CRYPTO);
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 0, "There should be no error.");

        // Add liquidity to TriCrypto.
        ICurveFi triPool = ICurveFi(curve3CryptoPool);

        deal(USDT, address(this), usdtIn);
        ERC20(USDT).safeApprove(curve3CryptoPool, usdtIn);
        uint256[3] memory amounts = [usdtIn, 0, 0];
        triPool.add_liquidity(amounts, 0);

        uint256 lpReceived = ERC20(TRI_CRYPTO).balanceOf(address(this));

        uint256 valueIn = usdtIn.mulDivDown(USDT_PRICE_ETH, 10 ** ERC20(USDT).decimals());
        uint256 valueOut = lpReceived.mulDivDown(upper, 10 ** ERC20(TRI_CRYPTO).decimals());

        assertApproxEqRel(valueIn, valueOut, 0.01e18, "Value in should approximately equal value out.");
    }

    function testCurveV2SourceCbEth_Eth(uint256 ethIn) external {
        ethIn = bound(ethIn, 0.1 ether, 1_000 ether);
        uint64 cbEthWethSource = priceOps.addSource(
            CBETH_WETH,
            PriceOps.Descriptor.EXTENSION,
            address(curveV2Extension),
            abi.encode(CBETH_WETH_POOL)
        );
        priceOps.addAsset(CBETH_WETH, cbEthWethSource, 0, 0);

        // Query price.
        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(CBETH_WETH);
        if (upper != lower) {
            assertGt(upper, lower, "Upper should be greater than lower.");
            assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        }
        assertEq(errorCode, 0, "There should be no error.");

        // Add liquidity to Curve Pool.
        ICurveFi pool = ICurveFi(CBETH_WETH_POOL);
        uint256[2] memory amounts = [ethIn, 0];
        pool.add_liquidity{ value: ethIn }(amounts, 0, true);

        uint256 lpReceived = ERC20(CBETH_WETH).balanceOf(address(this));

        uint256 valueIn = ethIn;
        uint256 valueOut = lpReceived.mulDivDown(upper, 10 ** ERC20(CBETH_WETH).decimals());

        assertApproxEqRel(valueIn, valueOut, 0.02e18, "Value in should approximately equal value out.");
    }

    // TODO add any other curve V2 pools we want to use.

    /*//////////////////////////////////////////////////////////////
                    CURVE V2 SOURCE ERRORS 
    //////////////////////////////////////////////////////////////*/

    function testCurveV2SourceErrorCodes() external {
        uint64 triCryptoSource = priceOps.addSource(
            TRI_CRYPTO,
            PriceOps.Descriptor.EXTENSION,
            address(curveV2Extension),
            abi.encode(curve3CryptoPool)
        );
        priceOps.addAsset(TRI_CRYPTO, triCryptoSource, 0, 0);

        // Price should be okay.
        (uint256 upper, uint256 lower, uint8 errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(TRI_CRYPTO);
        assertGt(upper, lower, "Upper should be greater than lower.");
        assertApproxEqRel(upper, lower, 0.01e18, "Upper and lower should approximately by equal.");
        assertEq(errorCode, 0, "There should be no error.");

        // make one USDT source go bad.
        MOCK_USDT_USD_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(TRI_CRYPTO);
        assertEq(upper, lower, "Upper and lower should be equal since 1 USDT source is bad.");
        assertEq(errorCode, 1, "There should be a CAUTION error.");

        // have both sources go bad
        MOCK_USDT_ETH_FEED.setMockUpdatedAt(block.timestamp - 2 days);
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(TRI_CRYPTO);
        assertEq(errorCode, 2, "There should be a BAD_SOURCE error.");
        assertEq(upper, 0, "Upper should be zero.");
        assertEq(lower, 0, "Lower should be zero.");

        // Reset sources so they are both good.
        MOCK_USDT_ETH_FEED.setMockUpdatedAt(0);
        MOCK_USDT_USD_FEED.setMockUpdatedAt(0);

        // But have sources diverge.
        MOCK_USDT_ETH_FEED.setMockAnswer(int256(USDT_PRICE_ETH.mulDivDown(1.02e4, 1e4)));
        (upper, lower, errorCode) = priceOps.getPriceInBaseEnforceNonZeroLower(TRI_CRYPTO);
        assertGt(upper, lower, "Upper should be greater than the lower.");
        assertEq(errorCode, 1, "There should be a CAUTION error.");
    }
}
