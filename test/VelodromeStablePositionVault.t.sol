// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { ERC20 } from "src/base/ERC20.sol";
import { SafeTransferLib } from "src/base/SafeTransferLib.sol";
import { DepositRouterV2 as DepositRouter } from "src/DepositRouterV2.sol";
import { VelodromeStablePositionVault, BasePositionVault, IVeloGauge, IVeloRouter, IVeloPairFactory } from "src/positions/VelodromeStablePositionVault.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { PriceRouter } from "src/PricingOperations/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { ICurvePool } from "src/interfaces/Curve/ICurvePool.sol";
// import { MockGasFeed } from "src/mocks/MockGasFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract VelodromeStablePositionVaultTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    PriceRouter private priceRouter;
    DepositRouter private router;
    VelodromeStablePositionVault private positionVault;
    // MockGasFeed private gasFeed;

    address private operatorAlpha = vm.addr(111);
    address private ownerAlpha = vm.addr(1110);
    address private operatorBeta = vm.addr(222);
    address private ownerBeta = vm.addr(2220);

    IVeloPairFactory private veloPairFactory = IVeloPairFactory(0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746);
    IVeloRouter private veloRouter = IVeloRouter(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);
    address private optiSwap = 0x6108FeAA628155b073150F408D0b390eC3121834;

    ERC20 private USDC = ERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    ERC20 private DAI = ERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    ERC20 private VELO = ERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);

    ERC20 private USDC_DAI = ERC20(0x4F7ebc19844259386DBdDB7b2eB759eeFc6F8353);
    IVeloGauge private gauge = IVeloGauge(0xc4fF55A961bC04b880e60219CCBBDD139c6451A4);

    address private accumulator = vm.addr(555);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant CURVE_DERIVATIVE = 2;
    uint8 private constant CURVEV2_DERIVATIVE = 3;

    // Datafeeds
    address private USDC_USD_FEED = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
    address private DAI_USD_FEED = 0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6;

    function setUp() external {
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
        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // WETH
        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // VELO
        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED); // TODO no chainlink oracle for Velo, use USDC for testing
        priceRouter.addAsset(VELO, settings, abi.encode(stor), price);

        positionVault = new VelodromeStablePositionVault(
            USDC_DAI,
            address(this),
            "WETH/USDC Vault",
            "WETH/USDC Vault",
            18
        );

        positionVault.setWatchdog(address(this));
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
            address[] memory rewards = new address[](3);
            rewards[0] = address(USDC);
            rewards[1] = address(DAI);
            rewards[2] = address(VELO);

            bytes memory initializeData = abi.encode(
                address(USDC),
                address(DAI),
                rewards,
                gauge,
                veloRouter,
                veloPairFactory,
                optiSwap
            );
            positionVault.initialize(
                USDC_DAI,
                address(this),
                "WETH/USDC Vault",
                "WETH/USDC Vault",
                18,
                metaData,
                initializeData
            );
        }
    }

    function testVelodromeStablePositionVaultWETHUSDC() external {
        positionVault.updateHarvestSlippage(0.9e18); // 90% slippage for testing

        uint256 assets = 1e18;
        deal(address(USDC_DAI), address(this), assets);
        USDC_DAI.approve(address(positionVault), assets);

        positionVault.deposit(assets, address(this));

        assertEq(positionVault.totalAssets(), assets, "Total Assets should equal user deposit.");

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Mint some extra rewards for Vault.
        deal(address(USDC), address(positionVault), 100e6);
        deal(address(DAI), address(positionVault), 100e18);
        deal(address(VELO), address(positionVault), 100e18);

        positionVault.harvest();

        assertEq(positionVault.totalAssets(), assets, "Total Assets should equal user deposit.");

        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        deal(address(USDC), address(positionVault), 100e6);
        deal(address(DAI), address(positionVault), 100e18);
        deal(address(VELO), address(positionVault), 100e18);

        positionVault.harvest();

        vm.warp(block.timestamp + 7 days);

        assertGt(positionVault.totalAssets(), assets, "Total Assets should greater than original deposit.");

        positionVault.withdraw(positionVault.totalAssets(), address(this), address(this));
    }
}
