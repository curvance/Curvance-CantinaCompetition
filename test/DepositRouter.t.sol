// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { DepositRouter } from "src/DepositRouter.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { PriceRouter } from "src/PricingOperations/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { ICurvePool } from "src/interfaces/Curve/ICurvePool.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract DepositRouterTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    PriceRouter private priceRouter;
    DepositRouter private router;

    address private operatorAlpha = vm.addr(111);
    address private ownerAlpha = vm.addr(1110);
    address private operatorBeta = vm.addr(222);
    address private ownerBeta = vm.addr(2220);

    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    ERC20 private CRV_3_CRYPTO = ERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
    uint256 curve3PoolConvexPid = 38;
    address private curve3CryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address private curve3PoolReward = 0x9D5C5E364D81DaB193b72db9E9BE9D8ee669B652;

    // use curve's new CRV-ETH crypto pool to sell our CRV
    address private constant crveth = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    // use curve's new CVX-ETH crypto pool to sell our CVX
    address private constant cvxeth = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

    address private accumulator = vm.addr(555);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant CURVEV2_DERIVATIVE = 3;

    // Datafeeds
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address private CVX_USD_FEED = 0xd962fC30A72A84cE50161031391756Bf2876Af5D;
    address private CRV_USD_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;

    function setUp() external {
        priceRouter = new PriceRouter();
        // USDT
        // Set heart beat to 5 days so we don't run into stale price reverts.
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            0,
            0,
            5 days,
            false
        );
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

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

        router = new DepositRouter(priceRouter);

        address[8] memory pools;
        uint16[8] memory froms;
        uint16[8] memory tos;
        DepositRouter.DepositData memory depositData;

        pools[0] = crveth;
        pools[1] = cvxeth;
        froms = [uint16(1), 1, 0, 0, 0, 0, 0, 0];
        // tos should be all zeros.

        uint8 coinsLength = 3;
        uint8 targetIndex = 2;
        bool useUnderlying = false;
        depositData = DepositRouter.DepositData(address(WETH), coinsLength, targetIndex, useUnderlying);

        router.addPosition(
            CRV_3_CRYPTO,
            DepositRouter.Platform.CONVEX,
            abi.encode(curve3PoolConvexPid, curve3PoolReward, curve3CryptoPool),
            pools,
            froms,
            tos,
            depositData
        );

        uint32[8] memory positions = [uint32(0), 1, 0, 0, 0, 0, 0, 0];
        uint32[8] memory positionRatios = [uint32(0.2e8), 0.8e8, 0, 0, 0, 0, 0, 0];
        router.addOperator(address(this), address(this), CRV_3_CRYPTO, 100e9, positions, positionRatios, 0.3e8, 0, 0);

        positionRatios = [uint32(0.5e8), 0.5e8, 0, 0, 0, 0, 0, 0];
        router.addOperator(
            operatorAlpha,
            ownerAlpha,
            CRV_3_CRYPTO,
            50e9,
            positions,
            positionRatios,
            0.2e8,
            10e8,
            uint64(1 days) / 4
        );

        positionRatios = [uint32(0.6e8), 0.4e8, 0, 0, 0, 0, 0, 0];
        router.addOperator(
            operatorBeta,
            ownerBeta,
            CRV_3_CRYPTO,
            25e9,
            positions,
            positionRatios,
            0.4e8,
            100e8,
            uint64(1 days) / 2
        );

        router.allowRebalancing(address(this), true);

        router.setFeeAccumulator(accumulator);

        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // ========================================= STATE TESTS =========================================
    function testAddPosition() external {
        // uint32 oldCount = router.positionCount();
        // uint32[] memory oldPositions = router.getActivePositions();

        // Setup position
        ERC20 CRV_3_POOL = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
        address curve3Pool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        uint256 pid = 9;
        address rewarderContract = 0x689440f2Ff927E1f24c72F1087E1FAF471eCe1c8;

        address[8] memory pools;
        uint16[8] memory froms;
        uint16[8] memory tos;
        DepositRouter.DepositData memory depositData;

        pools[0] = crveth;
        pools[1] = cvxeth;
        froms = [uint16(1), 1, 0, 0, 0, 0, 0, 0];
        // tos should be all zeros.

        uint8 coinsLength = 3;
        uint8 targetIndex = 2;
        bool useUnderlying = false;
        depositData = DepositRouter.DepositData(address(WETH), coinsLength, targetIndex, useUnderlying);

        router.addPosition(
            CRV_3_POOL,
            DepositRouter.Platform.CONVEX,
            abi.encode(pid, rewarderContract, curve3Pool),
            pools,
            froms,
            tos,
            depositData
        );

        // TODO check state.
        // uint32 newCount = router.positionCount();
        // uint32[] memory newPositions = router.getActivePositions();

        // assertEq(newCount, oldCount + 1, "Should have added one to positionCount.");
        // // assertEq(newPositions.length(), oldPositions.length() + 1, "Should have added one to activePositions array.");

        // (
        //     uint256 totalSupply,
        //     uint256 totalBalance,
        //     uint128 rewardRate,
        //     uint64 lastAccrualTimestamp,
        //     uint64 endTimestamp,
        //     DepositRouter.Platform platform,
        //     ERC20 asset,
        //     bytes memory positionData,

        // ) = router.positions(newCount);

        // assertEq(totalSupply, 0, "Total supply should be zero.");
        // assertEq(totalBalance, 0, "Total balance should be zero.");
        // assertEq(rewardRate, 0, "Reward rate should be zero.");
        // assertEq(lastAccrualTimestamp, uint64(block.timestamp), "Last accrual should be current block timestamp.");
        // assertEq(uint8(platform), 0, "Platform should be Convex.");
        // assertEq(
        //     positionData,
        //     abi.encode(pid, rewarderContract, curve3Pool),
        //     "Position data should be the same as input."
        // );
        // assertTrue(asset == CRV_3_POOL, "Asset should be the same as input.");
    }

    function testSetFeeAccumulator() external {
        address newAccumulator = vm.addr(1234);
        router.setFeeAccumulator(newAccumulator);

        assertEq(router.feeAccumulator(), newAccumulator, "Fee Accumulator should have been updated to new.");
    }

    // TODO test add operator

    // TODO test adjustming min yield for harvest and max gas for harvest

    // TODO test operator changing positions

    // TODO test operatorOwnerRebalance

    // TODO test allow rebalancing

    // ========================================= CORE TESTS =========================================
    // Check Happy Paths first.
    function testConvexDeposit(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint96).max);

        deal(address(CRV_3_CRYPTO), address(this), assets);
        CRV_3_CRYPTO.safeApprove(address(router), assets);

        router.deposit(assets);

        assertApproxEqAbs(router.balanceOf(address(this)), assets, 1, "Operator balance should be equal to assets in.");
        assertEq(CRV_3_CRYPTO.balanceOf(address(router)), assets, "Deposit Router should have been given assets.");
        assertEq(CRV_3_CRYPTO.balanceOf(address(this)), 0, "Operator should have taken all of callers assets.");

        // Perform rebalance Upkeep.
        uint32[8] memory from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        uint32[8] memory to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        uint256[8] memory amount = [uint256(assets.mulDivDown(8, 10)), 0, 0, 0, 0, 0, 0, 0];
        bytes memory upkeepData = abi.encode(address(this), from, to, amount);
        router.performUpkeep(upkeepData);

        assertApproxEqAbs(
            router.balanceOf(address(this)),
            assets,
            100000,
            "Operator balance should be constant through rebalance."
        );
        assertApproxEqAbs(
            CRV_3_CRYPTO.balanceOf(address(router)),
            assets.mulDivDown(2, 10),
            1,
            "Deposit Router should have sent 80% of assets to Convex."
        );
    }

    function testConvexWithdraw(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint96).max);

        deal(address(CRV_3_CRYPTO), address(this), assets);
        CRV_3_CRYPTO.safeApprove(address(router), assets);

        router.deposit(assets);

        uint256 assetsToWithdraw = router.balanceOf(address(this));

        // Perform rebalance Upkeep.
        uint32[8] memory from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        uint32[8] memory to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        uint256[8] memory amount = [uint256(assets.mulDivDown(8, 10)), 0, 0, 0, 0, 0, 0, 0];
        bytes memory upkeepData = abi.encode(address(this), from, to, amount);
        router.performUpkeep(upkeepData);

        assetsToWithdraw = router.balanceOf(address(this));

        router.withdraw(assetsToWithdraw);

        assertEq(router.balanceOf(address(this)), 0, "Operator balance should be zero.");
        assertEq(CRV_3_CRYPTO.balanceOf(address(router)), 0, "Deposit Router should have sent all assets to operator.");
        assertApproxEqAbs(CRV_3_CRYPTO.balanceOf(address(this)), assets, 2000, "Operator should have all assets back.");
    }

    function testConvexHarvest(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint96).max);

        deal(address(CRV_3_CRYPTO), address(this), assets);
        CRV_3_CRYPTO.safeApprove(address(router), assets);

        router.deposit(assets);

        // Perform rebalance Upkeep.
        uint32[8] memory from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        uint32[8] memory to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        uint256[8] memory amount = [uint256(assets.mulDivDown(8, 10)), 0, 0, 0, 0, 0, 0, 0];
        bytes memory upkeepData = abi.encode(address(this), from, to, amount);
        router.performUpkeep(upkeepData);

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Harvest rewards.
        upkeepData = abi.encode(address(router), 1);
        router.performUpkeep(upkeepData);

        assertEq(router.balanceOf(address(this)), assets, "Operator balance should be equal to assets in.");

        // Fully vest rewards
        vm.warp(block.timestamp + 7 days);

        assertGt(router.balanceOf(address(this)), assets, "Operator balance should have increased from vested yield.");

        uint256 assetsToWithdraw = router.balanceOf(address(this));
        deal(address(CRV_3_CRYPTO), address(this), 0);
        router.withdraw(assetsToWithdraw);

        assertEq(CRV_3_CRYPTO.balanceOf(address(this)), assetsToWithdraw, "Should have recieved full balance.");
        assertGt(assetsToWithdraw, assets, "Assets should have increased from yield.");
        assertTrue(CRV.balanceOf(accumulator) > 0, "Accumulator should have CRV.");
        assertTrue(CVX.balanceOf(accumulator) > 0, "Accumulator should have CVX.");
    }

    function testKeeperRebalance(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint96).max);

        deal(address(CRV_3_CRYPTO), address(this), assets);
        CRV_3_CRYPTO.safeApprove(address(router), assets);

        router.deposit(assets);
        (bool upkeepNeeded, bytes memory performData) = router.checkUpkeep(abi.encode(address(this)));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        router.performUpkeep(performData);

        assertEq(router.balanceOf(address(this)), assets, "Operator balance should be constant through rebalance.");
    }

    // ========================================= MULTI-OPERATOR TESTS =========================================
    function testDepositWithMultipleOperators(uint256 assetsAlpha, uint256 assetsBeta) external {
        assetsAlpha = bound(assetsAlpha, 1e18, type(uint96).max);
        assetsBeta = bound(assetsBeta, 1e18, type(uint96).max);

        deal(address(CRV_3_CRYPTO), operatorAlpha, assetsAlpha);
        deal(address(CRV_3_CRYPTO), operatorBeta, assetsBeta);

        // Operator Alpha deposits.
        vm.startPrank(operatorAlpha);
        CRV_3_CRYPTO.safeApprove(address(router), assetsAlpha);
        router.deposit(assetsAlpha);
        vm.stopPrank();

        // Operator Beta deposits.
        vm.startPrank(operatorBeta);
        CRV_3_CRYPTO.safeApprove(address(router), assetsBeta);
        router.deposit(assetsBeta);
        vm.stopPrank();

        // Check balances.
        assertEq(router.balanceOf(operatorAlpha), assetsAlpha, "Operator Alpha balance should be equal to assets in.");
        assertEq(CRV_3_CRYPTO.balanceOf(operatorAlpha), 0, "Operator Alpha should have taken all of callers assets.");

        assertEq(router.balanceOf(operatorBeta), assetsBeta, "Operator Beta balance should be equal to assets in.");
        assertEq(CRV_3_CRYPTO.balanceOf(operatorBeta), 0, "Operator Beta should have taken all of callers assets.");

        assertEq(
            CRV_3_CRYPTO.balanceOf(address(router)),
            assetsAlpha + assetsBeta,
            "Deposit Router should have been given Alpha and Beta assets."
        );

        // Perform rebalance Upkeep for each operator.
        uint32[8] memory from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        uint32[8] memory to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        uint256[8] memory amount = [uint256(assetsAlpha.mulDivDown(5, 10)), 0, 0, 0, 0, 0, 0, 0];
        bytes memory upkeepData = abi.encode(operatorAlpha, from, to, amount);
        vm.prank(ownerAlpha);
        // Have owner allow rebalancing.
        router.allowRebalancing(operatorAlpha, true);
        // Warp time forward so rate limit check is valid.
        vm.warp(block.timestamp + 1 days / 2);
        router.performUpkeep(upkeepData);

        from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        amount = [uint256(assetsBeta.mulDivDown(4, 10)), 0, 0, 0, 0, 0, 0, 0];
        upkeepData = abi.encode(operatorBeta, from, to, amount);
        vm.prank(ownerBeta);
        // Have owner allow rebalancing.
        router.allowRebalancing(operatorBeta, true);
        // No need to warp time because beta rate limit is 1/4 days.
        router.performUpkeep(upkeepData);

        // Check balances in Deposit Router.
        assertEq(router.balanceOf(operatorAlpha), assetsAlpha, "Operator Alpha balance should be constant.");
        assertEq(router.balanceOf(operatorBeta), assetsBeta, "Operator Beta balance should be constant.");

        assertApproxEqAbs(
            CRV_3_CRYPTO.balanceOf(address(router)),
            assetsAlpha.mulDivDown(5, 10) + assetsBeta.mulDivDown(6, 10),
            2,
            "Deposit Router should have sent 50% of assetsAlpha to Convex and 40% assetsBeta to Convex."
        );
    }

    function testWithdrawWithMultipleOperators(uint256 assetsAlpha, uint256 assetsBeta) external {
        assetsAlpha = bound(assetsAlpha, 1e18, type(uint96).max);
        assetsBeta = bound(assetsBeta, 1e18, type(uint96).max);

        deal(address(CRV_3_CRYPTO), operatorAlpha, assetsAlpha);
        deal(address(CRV_3_CRYPTO), operatorBeta, assetsBeta);

        // Operator Alpha deposits.
        vm.startPrank(operatorAlpha);
        CRV_3_CRYPTO.safeApprove(address(router), assetsAlpha);
        router.deposit(assetsAlpha);
        vm.stopPrank();

        // Operator Beta deposits.
        vm.startPrank(operatorBeta);
        CRV_3_CRYPTO.safeApprove(address(router), assetsBeta);
        router.deposit(assetsBeta);
        vm.stopPrank();

        // Perform rebalance Upkeep for each operator.
        uint32[8] memory from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        uint32[8] memory to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        uint256[8] memory amount = [uint256(assetsAlpha.mulDivDown(5, 10)), 0, 0, 0, 0, 0, 0, 0];
        bytes memory upkeepData = abi.encode(operatorAlpha, from, to, amount);
        vm.prank(ownerAlpha);
        // Have owner allow rebalancing.
        router.allowRebalancing(operatorAlpha, true);
        // Warp time forward so rate limit check is valid.
        vm.warp(block.timestamp + 1 days / 2);
        router.performUpkeep(upkeepData);

        from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        amount = [uint256(assetsBeta.mulDivDown(4, 10)), 0, 0, 0, 0, 0, 0, 0];
        upkeepData = abi.encode(operatorBeta, from, to, amount);
        vm.prank(ownerBeta);
        // Have owner allow rebalancing.
        router.allowRebalancing(operatorBeta, true);
        // No need to warp time because beta rate limit is 1/4 days.
        router.performUpkeep(upkeepData);

        // Operator Alpha withdraws.
        vm.startPrank(operatorAlpha);
        uint256 assetsToWithdrawAlpha = router.balanceOf(operatorAlpha);
        router.withdraw(assetsToWithdrawAlpha);
        vm.stopPrank();
        assertEq(router.balanceOf(operatorAlpha), 0, "Operator Alpha balance should be zero.");
        assertEq(CRV_3_CRYPTO.balanceOf(operatorAlpha), assetsAlpha, "Operator Alpha should have all assets back.");

        // Operator Beta withdraws.
        vm.startPrank(operatorBeta);
        uint256 assetsToWithdrawBeta = router.balanceOf(operatorBeta);
        router.withdraw(assetsToWithdrawBeta);
        vm.stopPrank();
        assertEq(router.balanceOf(operatorBeta), 0, "Operator Beta balance should be zero.");
        assertEq(CRV_3_CRYPTO.balanceOf(operatorBeta), assetsBeta, "Operator Alpha should have all assets back.");

        assertEq(
            CRV_3_CRYPTO.balanceOf(address(router)),
            0,
            "Deposit Router should have sent all assets to operators."
        );
    }

    function testConvexHarvestWithMultipleOperators(uint256 assetsAlpha, uint256 assetsBeta) external {
        assetsAlpha = bound(assetsAlpha, 1e18, type(uint96).max);
        assetsBeta = bound(assetsBeta, 1e18, type(uint96).max);
        // assetsAlpha = 1000000000000000000;
        // assetsBeta = 35799006209555501558;
        deal(address(CRV_3_CRYPTO), operatorAlpha, assetsAlpha);
        deal(address(CRV_3_CRYPTO), operatorBeta, assetsBeta);

        // Operator Alpha deposits.
        vm.startPrank(operatorAlpha);
        CRV_3_CRYPTO.safeApprove(address(router), assetsAlpha);
        router.deposit(assetsAlpha);
        vm.stopPrank();

        // Operator Beta deposits.
        vm.startPrank(operatorBeta);
        CRV_3_CRYPTO.safeApprove(address(router), assetsBeta);
        router.deposit(assetsBeta);
        vm.stopPrank();

        // Perform rebalance Upkeep for each operator.
        uint32[8] memory from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        uint32[8] memory to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        uint256[8] memory amount = [uint256(assetsAlpha.mulDivDown(5, 10)), 0, 0, 0, 0, 0, 0, 0];
        bytes memory upkeepData = abi.encode(operatorAlpha, from, to, amount);
        vm.prank(ownerAlpha);
        // Have owner allow rebalancing.
        router.allowRebalancing(operatorAlpha, true);
        // Warp time forward so rate limit check is valid.
        vm.warp(block.timestamp + 1 days / 2);
        router.performUpkeep(upkeepData);

        from = [uint32(0), 0, 0, 0, 0, 0, 0, 0];
        to = [uint32(1), 0, 0, 0, 0, 0, 0, 0];
        amount = [uint256(assetsBeta.mulDivDown(4, 10)), 0, 0, 0, 0, 0, 0, 0];
        upkeepData = abi.encode(operatorBeta, from, to, amount);
        vm.prank(ownerBeta);
        // Have owner allow rebalancing.
        router.allowRebalancing(operatorBeta, true);
        // No need to warp time because beta rate limit is 1/4 days.
        router.performUpkeep(upkeepData);

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Harvest rewards.
        upkeepData = abi.encode(address(router), 1);
        router.performUpkeep(upkeepData);

        assertApproxEqAbs(
            router.balanceOf(operatorAlpha),
            assetsAlpha,
            1,
            "Operator Alpha balance should be equal to assets in."
        );
        assertApproxEqAbs(
            router.balanceOf(operatorBeta),
            assetsBeta,
            1,
            "Operator Beta balance should be equal to assets in."
        );

        // Fully vest rewards
        vm.warp(block.timestamp + 8 days);

        assertGt(
            router.balanceOf(operatorAlpha),
            assetsAlpha,
            "Operator Alpha balance should have increased from vested yield."
        );
        assertGt(
            router.balanceOf(operatorBeta),
            assetsBeta,
            "Operator Beta balance should have increased from vested yield."
        );

        // Operator Alpha withdraws.
        vm.startPrank(operatorAlpha);
        uint256 assetsToWithdrawAlpha = router.balanceOf(operatorAlpha);
        router.withdraw(assetsToWithdrawAlpha);
        vm.stopPrank();
        assertApproxEqAbs(router.balanceOf(operatorAlpha), 0, 10, "Operator Alpha balance should be zero.");
        assertEq(
            CRV_3_CRYPTO.balanceOf(operatorAlpha),
            assetsToWithdrawAlpha,
            "Operator Alpha should have all assets back."
        );

        // Operator Beta withdraws.
        vm.startPrank(operatorBeta);
        uint256 assetsToWithdrawBeta = router.balanceOf(operatorBeta);
        router.withdraw(assetsToWithdrawBeta);
        vm.stopPrank();
        assertApproxEqAbs(router.balanceOf(operatorBeta), 0, 10, "Operator Beta balance should be zero.");
        assertEq(
            CRV_3_CRYPTO.balanceOf(operatorBeta),
            assetsToWithdrawBeta,
            "Operator Beta should have all assets back."
        );

        assertEq(
            CRV_3_CRYPTO.balanceOf(address(router)),
            0,
            "Deposit Router should have sent all assets to operators."
        );
    }

    // TODO add test where one operator tries to withdraw too much to steal another operators assets.

    // ========================================= INTEGRATION TESTS =========================================
    function testMultipleOperators() external {}
    // TODO add test for multiple operators with different assets and like assets.

    // ========================================= HELPER FUNCTIONS =========================================
}
