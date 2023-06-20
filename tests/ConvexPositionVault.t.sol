// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { ERC20 } from "contracts/base/ERC20.sol";
import { SafeTransferLib } from "contracts/base/SafeTransferLib.sol";
import { DepositRouterV2 as DepositRouter } from "contracts/DepositRouterV2.sol";
import { ConvexPositionVault, BasePositionVault } from "contracts/positions/ConvexPositionVault.sol";
import { IBaseRewardPool } from "contracts/interfaces/Convex/IBaseRewardPool.sol";
import { PriceRouter } from "contracts/PricingOperations/PriceRouter.sol";
import { IChainlinkAggregator } from "contracts/interfaces/IChainlinkAggregator.sol";
import { ICurvePool } from "contracts/interfaces/Curve/ICurvePool.sol";
import { Math } from "contracts/utils/Math.sol";
import "tests/utils/TestBase.sol";

contract ConvexPositionVaultTest is TestBase {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    PriceRouter private priceRouter;
    DepositRouter private router;
    ConvexPositionVault private cvxPositionTriCrypto;
    ConvexPositionVault private cvxPosition3Pool;
    // MockGasFeed private gasFeed;

    address private operatorAlpha = vm.addr(111);
    address private ownerAlpha = vm.addr(1110);
    address private operatorBeta = vm.addr(222);
    address private ownerBeta = vm.addr(2220);

    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    ERC20 private CRV_3_CRYPTO = ERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
    uint256 private curve3PoolConvexPid = 38;
    address private curve3CryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address private curve3PoolReward = 0x9D5C5E364D81DaB193b72db9E9BE9D8ee669B652;
    address private booster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    ERC20 CRV_DAI_USDC_USDT = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    uint256 private curve3CRVConvexPid = 9;
    address private curve3CrvPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address private curve3CrvReward = 0x689440f2Ff927E1f24c72F1087E1FAF471eCe1c8;

    address private curveRegistryExchange = 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7;

    // use curve's new CRV-ETH crypto pool to sell our CRV
    address private constant crveth = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    // use curve's new CVX-ETH crypto pool to sell our CVX
    address private constant cvxeth = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

    address private accumulator = vm.addr(555);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant CURVE_DERIVATIVE = 2;
    uint8 private constant CURVEV2_DERIVATIVE = 3;

    // Datafeeds
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address private CVX_USD_FEED = 0xd962fC30A72A84cE50161031391756Bf2876Af5D;
    address private CRV_USD_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;
    address private ETH_FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    function setUp() public {
        // Should figure out
        // Setup fails when it forks current block instead of 15_000_000.
        _fork(15000000);

        // gasFeed = new MockGasFeed();
        priceRouter = new PriceRouter();
        // USDT
        // Set heart beat to 5 days so we don't run into stale price reverts.
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            0,
            0,
            150 days,
            false
        );
        // USDT
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // USDC
        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // DAI
        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // WETH
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // WBTC
        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // CVX
        price = uint256(IChainlinkAggregator(CVX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CVX_USD_FEED);
        priceRouter.addAsset(CVX, settings, abi.encode(stor), price);

        // CRV
        price = uint256(IChainlinkAggregator(CRV_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CRV_USD_FEED);
        priceRouter.addAsset(CRV, settings, abi.encode(stor), price);

        // TriCryptoPool
        settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, curve3CryptoPool);
        uint256 vp = ICurvePool(curve3CryptoPool).get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_3_CRYPTO, settings, abi.encode(vpBound), 862e8);

        // Add 3Pool
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, curve3CrvPool);
        vp = ICurvePool(curve3CrvPool).get_virtual_price().changeDecimals(18, 8);
        vpBound = PriceRouter.VirtualPriceBound(uint96(vp), 0, uint32(1.01e8), uint32(0.99e8), 0);
        priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.02e8);

        cvxPositionTriCrypto = new ConvexPositionVault(CRV_3_CRYPTO, address(this), "Tri Crypto Vault", "TCV", 18);

        cvxPositionTriCrypto.setWatchdog(address(this));
        BasePositionVault.PositionVaultMetaData memory metaData = BasePositionVault.PositionVaultMetaData({
            platformFee: 0.2e18,
            upkeepFee: 0.03e18,
            minHarvestYieldInUSD: 1_000e8,
            maxGasPriceForHarvest: 1_000e9,
            feeAccumulator: accumulator,
            positionWatchdog: address(this),
            ethFastGasFeed: 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C,
            priceRouter: priceRouter,
            automationRegistry: address(this),
            isShutdown: false
        });

        // Need to initialize Vault.
        {
            ConvexPositionVault.CurveDepositParams memory depositParams = ConvexPositionVault.CurveDepositParams(
                WETH,
                3,
                2,
                false,
                curve3CryptoPool
            );
            ConvexPositionVault.CurveSwapParams[] memory swapsToETH = new ConvexPositionVault.CurveSwapParams[](2);
            address[9] memory route0 = [
                address(CRV),
                crveth,
                address(WETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            uint256[3][4] memory swaps;
            swaps[0] = [uint256(1), 0, 3];
            swapsToETH[0] = ConvexPositionVault.CurveSwapParams(route0, swaps, CRV, 1e8);
            address[9] memory route1 = [
                address(CVX),
                cvxeth,
                address(WETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            swapsToETH[1] = ConvexPositionVault.CurveSwapParams(route1, swaps, CVX, 1e8);
            ERC20[] memory assetsToETH = new ERC20[](2);
            assetsToETH[0] = CRV;
            assetsToETH[1] = CVX;
            ConvexPositionVault.CurveSwapParams memory emptySwaps;
            bytes memory initializeData = abi.encode(
                curve3PoolConvexPid,
                curve3PoolReward,
                booster,
                depositParams,
                curveRegistryExchange,
                swapsToETH,
                assetsToETH,
                emptySwaps
            );
            cvxPositionTriCrypto.initialize(
                CRV_3_CRYPTO,
                address(this),
                "Tri Crypto Vault",
                "TCV",
                18,
                metaData,
                initializeData
            );
        }

        cvxPosition3Pool = new ConvexPositionVault(CRV_DAI_USDC_USDT, address(this), "3 Pool Vault", "3PV", 18);

        cvxPosition3Pool.setWatchdog(address(this));

        {
            ConvexPositionVault.CurveDepositParams memory depositParams = ConvexPositionVault.CurveDepositParams(
                USDT,
                3,
                2,
                false,
                curve3CrvPool
            );

            ConvexPositionVault.CurveSwapParams[] memory swapsToETH = new ConvexPositionVault.CurveSwapParams[](2);
            address[9] memory route0 = [
                address(CRV),
                crveth,
                address(WETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            uint256[3][4] memory swaps;
            swaps[0] = [uint256(1), 0, 3];
            swapsToETH[0] = ConvexPositionVault.CurveSwapParams(route0, swaps, CRV, 1e8);
            address[9] memory route1 = [
                address(CVX),
                cvxeth,
                address(WETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            swapsToETH[1] = ConvexPositionVault.CurveSwapParams(route1, swaps, CVX, 1e8);
            ERC20[] memory assetsToETH = new ERC20[](2);
            assetsToETH[0] = CRV;
            assetsToETH[1] = CVX;
            ConvexPositionVault.CurveSwapParams memory swapsToTarget;
            address[9] memory route = [
                address(WETH),
                curve3CryptoPool,
                address(USDT),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            uint256[3][4] memory swaps0;
            swaps0[0] = [uint256(2), 0, 3];
            swapsToTarget = ConvexPositionVault.CurveSwapParams(route, swaps0, WETH, 0);
            bytes memory initializeData = abi.encode(
                curve3CRVConvexPid,
                curve3CrvReward,
                booster,
                depositParams,
                curveRegistryExchange,
                swapsToETH,
                assetsToETH,
                swapsToTarget
            );
            cvxPosition3Pool.initialize(
                CRV_DAI_USDC_USDT,
                address(this),
                "3 Pool Vault",
                "3PV",
                18,
                metaData,
                initializeData
            );
        }

        // stdstore.target(address(router)).sig(router.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testConvexPositionVaultTriCrypto() public {
        uint256 assets = 100e18;
        deal(address(CRV_3_CRYPTO), address(this), assets);
        CRV_3_CRYPTO.approve(address(cvxPositionTriCrypto), assets);

        cvxPositionTriCrypto.deposit(assets, address(this));

        // uint256 vaultBalance = IBaseRewardPool(curve3PoolReward).balanceOf(address(cvxPositionTriCrypto));

        assertEq(cvxPositionTriCrypto.totalAssets(), assets, "Total Assets should equal user deposit.");

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Mint some extra rewards for Vault.
        deal(address(CRV), address(cvxPositionTriCrypto), 100e18);
        deal(address(CVX), address(cvxPositionTriCrypto), 100e18);

        cvxPositionTriCrypto.harvest();

        assertEq(cvxPositionTriCrypto.totalAssets(), assets, "Total Assets should equal user deposit.");

        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        deal(address(CRV), address(cvxPositionTriCrypto), 100e18);
        deal(address(CVX), address(cvxPositionTriCrypto), 100e18);
        cvxPositionTriCrypto.harvest();
        vm.warp(block.timestamp + 7 days);

        assertGt(cvxPositionTriCrypto.totalAssets(), assets, "Total Assets should greater than original deposit.");

        cvxPositionTriCrypto.withdraw(cvxPositionTriCrypto.totalAssets(), address(this), address(this));
    }

    function testConvexPositionVault3Pool() public {
        uint256 assets = 1_000_000e18;
        deal(address(CRV_DAI_USDC_USDT), address(this), assets);
        CRV_DAI_USDC_USDT.approve(address(cvxPosition3Pool), assets);

        cvxPosition3Pool.deposit(assets, address(this));

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Mint some extra rewards for Vault.
        deal(address(CRV), address(cvxPosition3Pool), 100e18);
        deal(address(CVX), address(cvxPositionTriCrypto), 100e18);

        uint256 shareValue = cvxPosition3Pool.previewRedeem(_ONE);
        cvxPosition3Pool.harvest();
        assertEq(cvxPosition3Pool.previewRedeem(_ONE), shareValue, "Share Price should be constant through harvest.");

        vm.warp(block.timestamp + 7 days);

        assertGt(
            cvxPosition3Pool.previewRedeem(_ONE),
            shareValue,
            "Share Price should have increased as rewards vest."
        );

        cvxPosition3Pool.harvest();

        cvxPosition3Pool.withdraw(cvxPosition3Pool.totalAssets(), address(this), address(this));
    }

    function testMultipleDepositors(uint256 assetsA, uint256 assetsB) public {
        assetsA = bound(assetsA, _ONE, type(uint96).max);
        assetsB = bound(assetsB, _ONE, type(uint96).max);

        address userA = vm.addr(23);
        address userB = vm.addr(24);

        // Give users funds to deposit.
        deal(address(CRV_3_CRYPTO), userA, assetsA);
        deal(address(CRV_3_CRYPTO), userB, assetsB);

        // Have users approve and deposit.
        vm.startPrank(userA);
        CRV_3_CRYPTO.safeApprove(address(cvxPositionTriCrypto), assetsA);
        cvxPositionTriCrypto.deposit(assetsA, userA);
        vm.stopPrank();

        vm.startPrank(userB);
        CRV_3_CRYPTO.safeApprove(address(cvxPositionTriCrypto), assetsB);
        cvxPositionTriCrypto.deposit(assetsB, userB);
        vm.stopPrank();

        assertEq(cvxPositionTriCrypto.maxWithdraw(userA), assetsA, "User should be able to withdraw their deposit.");
        assertEq(cvxPositionTriCrypto.maxWithdraw(userB), assetsB, "User should be able to withdraw their deposit.");

        assertEq(
            CRV_3_CRYPTO.balanceOf(address(cvxPositionTriCrypto)),
            0,
            "Assets should have been invested in Convex."
        );

        // Have position earn some yield.
        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 1 days);

        // Mint some extra rewards for Vault.
        deal(address(CRV), address(cvxPositionTriCrypto), 100e18);
        deal(address(CVX), address(cvxPositionTriCrypto), 10e18);

        uint256 yield = cvxPositionTriCrypto.harvest();

        assertEq(cvxPositionTriCrypto.maxWithdraw(userA), assetsA, "User should be able to withdraw their deposit.");
        assertEq(cvxPositionTriCrypto.maxWithdraw(userB), assetsB, "User should be able to withdraw their deposit.");

        // Make sure yield is distributed linearly into totalAssets.
        // Advance time to 1/4 way through the vesting period.
        vm.warp(block.timestamp + 7 days / 4);

        uint256 expectedTotalAssets = assetsA + assetsB + yield / 4;
        assertApproxEqAbs(
            cvxPositionTriCrypto.totalAssets(),
            expectedTotalAssets,
            1,
            "Total assets should equal expected."
        );

        // Advance time to 2/4 way through the vesting period.
        vm.warp(block.timestamp + 7 days / 4);

        expectedTotalAssets = assetsA + assetsB + yield / 2;
        assertApproxEqAbs(
            cvxPositionTriCrypto.totalAssets(),
            expectedTotalAssets,
            1,
            "Total assets should equal expected."
        );

        // Trying to harvest again while rewards are pending should return 0 for yield.
        uint256 zeroYield = cvxPositionTriCrypto.harvest();
        assertEq(zeroYield, 0, "Yield earned should be yield because previous rewards are vesting.");

        // Advance time to 3/4 way through the vesting period.
        vm.warp(block.timestamp + 7 days / 4);

        expectedTotalAssets = assetsA + assetsB + ((3 * yield) / 4);
        assertApproxEqAbs(
            cvxPositionTriCrypto.totalAssets(),
            expectedTotalAssets,
            2,
            "Total assets should equal expected."
        );

        // Advance time to 4/4 way through the vesting period.
        vm.warp(block.timestamp + 7 days / 4);

        expectedTotalAssets = assetsA + assetsB + yield;
        assertApproxEqAbs(
            cvxPositionTriCrypto.totalAssets(),
            expectedTotalAssets,
            2,
            "Total assets should equal expected."
        );

        // Have both users withdraw all their assets.
        vm.startPrank(userA);
        uint256 userAWithdraw = cvxPositionTriCrypto.maxWithdraw(userA);
        cvxPositionTriCrypto.withdraw(userAWithdraw, userA, userA);
        vm.stopPrank();
        assertEq(CRV_3_CRYPTO.balanceOf(userA), userAWithdraw, "User did not receive full withdraw.");

        vm.startPrank(userB);
        uint256 userBWithdraw = cvxPositionTriCrypto.maxWithdraw(userB);
        cvxPositionTriCrypto.withdraw(userBWithdraw, userB, userB);
        vm.stopPrank();
        assertEq(CRV_3_CRYPTO.balanceOf(userB), userBWithdraw, "User did not receive full withdraw.");
    }

    function testAttackerGettingMoreOutThanTheyPutIn() public {
        // Normal Users join the vault.
        uint256 assets = 1_000_000e18;
        deal(address(CRV_DAI_USDC_USDT), address(this), assets);
        CRV_DAI_USDC_USDT.approve(address(cvxPosition3Pool), assets);

        cvxPosition3Pool.deposit(assets, address(this));

        // Attacker joins.
        address attacker = vm.addr(10);
        uint256 attackerAssets = 1_000e18;
        deal(address(CRV_DAI_USDC_USDT), attacker, attackerAssets);
        vm.startPrank(attacker);
        CRV_DAI_USDC_USDT.approve(address(cvxPosition3Pool), attackerAssets);
        cvxPosition3Pool.deposit(attackerAssets, attacker);
        vm.stopPrank();

        // All should be well and checkUpkeep should return false.
        (bool upkeepNeeded, bytes memory performData) = cvxPosition3Pool.checkUpkeep(abi.encode(0));
        assertEq(upkeepNeeded, false, "Upkeep should not be needed.");

        // But if attacker was somehow able to mint more shares.
        uint256 attackerNewBalance = cvxPosition3Pool.balanceOf(attacker) + 10 ** cvxPosition3Pool.decimals();
        deal(address(cvxPosition3Pool), attacker, attackerNewBalance, true);

        // Then withdrew their initial capital plus stolen.
        vm.startPrank(attacker);
        uint256 amountToWithdraw = cvxPosition3Pool.maxWithdraw(attacker);
        cvxPosition3Pool.withdraw(amountToWithdraw, attacker, attacker);
        vm.stopPrank();

        (upkeepNeeded, performData) = cvxPosition3Pool.checkUpkeep(abi.encode(0));
        assertEq(upkeepNeeded, true, "Upkeep should  be needed.");
        bool circuitBreaker = abi.decode(performData, (bool));
        assertEq(circuitBreaker, true, "Circuit Breaker should be true.");

        cvxPosition3Pool.performUpkeep(performData);

        assertEq(cvxPosition3Pool.isShutdown(), true, "Vault should be shutdown.");
    }

    function testStoredTotalAssetsGreaterThanRealTotalAssets() public {
        (bool upkeepNeeded, bytes memory performData) = cvxPosition3Pool.checkUpkeep(abi.encode(0));
        assertEq(upkeepNeeded, false, "Upkeep should not be needed.");

        // Normal Users join the vault.
        uint256 assets = 1_000_000e18;
        deal(address(CRV_DAI_USDC_USDT), address(this), assets);
        CRV_DAI_USDC_USDT.approve(address(cvxPosition3Pool), assets);

        cvxPosition3Pool.deposit(assets, address(this));

        (upkeepNeeded, performData) = cvxPosition3Pool.checkUpkeep(abi.encode(0));
        assertEq(upkeepNeeded, false, "Upkeep should not be needed.");

        vm.startPrank(address(cvxPosition3Pool));
        IBaseRewardPool(curve3CrvReward).withdrawAndUnwrap(1, false);
        vm.stopPrank();

        (upkeepNeeded, performData) = cvxPosition3Pool.checkUpkeep(abi.encode(0));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");

        bool circuitBreaker = abi.decode(performData, (bool));
        assertEq(circuitBreaker, true, "Circuit Breaker should be true.");

        cvxPosition3Pool.performUpkeep(performData);

        assertEq(cvxPosition3Pool.isShutdown(), true, "Vault should be shutdown.");
    }
}
