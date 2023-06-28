// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { ERC20 } from "contracts/libraries/ERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { DepositRouterV2 as DepositRouter } from "contracts/deposits/DepositRouterV2.sol";
import { AuraPositionVault, BasePositionVault } from "contracts/deposits/adaptors/AuraPositionVault.sol";
import { PriceRouter } from "contracts/oracles/PriceRouterV2.sol";
import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";
import { Math } from "contracts/libraries/Math.sol";
import "tests/utils/TestBase.sol";

contract AuraPositionVaultTest is TestBase {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    PriceRouter private priceRouter;
    DepositRouter private router;
    AuraPositionVault private positionVault;
    // MockGasFeed private gasFeed;

    address private operatorAlpha = vm.addr(111);
    address private ownerAlpha = vm.addr(1110);
    address private operatorBeta = vm.addr(222);
    address private ownerBeta = vm.addr(2220);

    address public uniswapV2Router =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    ERC20 private constant AURA =
        ERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    ERC20 private constant BAL =
        ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private BALANCER_LP_WETH_AURA =
        ERC20(0xCfCA23cA9CA720B6E98E3Eb9B6aa0fFC4a5C08B9);

    address private accumulator = vm.addr(555);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    // Datafeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private BAL_USD_FEED = 0xdF2917806E30300537aEB49A7663062F4d1F2b5F;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    function setUp() public {
        _fork("ETH_NODE_URI_MAINNET");

        // gasFeed = new MockGasFeed();
        priceRouter = new PriceRouter();
        // USDT
        // Set heart beat to 5 days so we don't run into stale price reverts.
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter
            .ChainlinkDerivativeStorage(0, 0, 150 days, false);

        // WETH
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(
            IChainlinkAggregator(WETH_USD_FEED).latestAnswer()
        );
        settings = PriceRouter.AssetSettings(
            CHAINLINK_DERIVATIVE,
            WETH_USD_FEED
        );
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);
        // BAL
        price = uint256(IChainlinkAggregator(BAL_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(
            CHAINLINK_DERIVATIVE,
            BAL_USD_FEED
        );
        priceRouter.addAsset(BAL, settings, abi.encode(stor), price);
        // AURA -> use DAI price as for testing
        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(
            CHAINLINK_DERIVATIVE,
            DAI_USD_FEED
        );
        priceRouter.addAsset(AURA, settings, abi.encode(stor), price);

        positionVault = new AuraPositionVault(
            BALANCER_LP_WETH_AURA,
            address(this),
            "WETH/AURA Vault",
            "WETH/AURA Vault",
            18
        );

        positionVault.setWatchdog(address(this));
        BasePositionVault.PositionVaultMetaData
            memory metaData = BasePositionVault.PositionVaultMetaData({
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
            address[] memory underlyingTokens = new address[](2);
            underlyingTokens[0] = address(WETH);
            underlyingTokens[1] = address(AURA);
            address[] memory rewardTokens = new address[](2);
            rewardTokens[0] = address(BAL);
            rewardTokens[1] = address(AURA);

            bytes memory initializeData = abi.encode(
                address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), // Balancer Vault
                0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274, // Balancer PID
                underlyingTokens, // Balancer LP underlying tokens
                100, // Aura PID
                address(0x1204f5060bE8b716F5A62b4Df4cE32acD01a69f5), // Aura rewarder
                address(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234), // Aura Booster
                rewardTokens // Reward tokens
            );
            positionVault.initialize(
                BALANCER_LP_WETH_AURA,
                address(this),
                "WETH/AURA Vault",
                "WETH/AURA Vault",
                18,
                metaData,
                initializeData
            );
        }

        positionVault.setIsApprovedTarget(uniswapV2Router, true);
    }

    function testAuraPositionVaultWethAura() public {
        positionVault.updateHarvestSlippage(0.9e18); // 90% slippage for testing
        uint256 assets = _ONE;
        deal(address(BALANCER_LP_WETH_AURA), address(this), assets);
        BALANCER_LP_WETH_AURA.approve(address(positionVault), assets);
        positionVault.deposit(assets, address(this));
        assertEq(
            positionVault.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );
        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);
        // Mint some extra rewards for Vault.
        deal(address(BAL), address(positionVault), 100e18);
        deal(address(AURA), address(positionVault), 100e18);
        deal(address(WETH), address(positionVault), 1e18);

        AuraPositionVault.Swap[]
            memory swapDataArray = new AuraPositionVault.Swap[](2);
        swapDataArray[0].target = uniswapV2Router;
        address[] memory path = new address[](2);
        path[0] = address(BAL);
        path[1] = address(WETH);
        swapDataArray[0].call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            80e18,
            0,
            path,
            address(positionVault),
            block.timestamp
        );

        positionVault.harvest(abi.encode(swapDataArray));
        assertEq(
            positionVault.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );
        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        deal(address(BAL), address(positionVault), 100e18);
        deal(address(AURA), address(positionVault), 100e18);
        deal(address(WETH), address(positionVault), 1e18);

        swapDataArray[0].call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            80e18,
            0,
            path,
            address(positionVault),
            block.timestamp
        );
        positionVault.harvest(abi.encode(swapDataArray));
        assertGt(
            positionVault.totalAssets(),
            assets,
            "Total Assets should greater than original deposit."
        );

        positionVault.withdraw(
            positionVault.totalAssets(),
            address(this),
            address(this)
        );
    }
}
