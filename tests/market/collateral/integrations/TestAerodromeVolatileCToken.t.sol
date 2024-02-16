// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { AerodromeVolatileCToken, IVeloGauge, IVeloRouter, IVeloPairFactory, IERC20 } from "contracts/market/collateral/AerodromeVolatileCToken.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";

import "tests/market/TestBaseMarket.sol";

contract TestAerodromeVolatileCToken is TestBaseMarket {
    IERC20 public WETH = IERC20(0x4200000000000000000000000000000000000006);
    IERC20 public USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20 public AERO = IERC20(0x940181a94A35A4569E4529A3CDfB74e38FD98631);
    IERC20 public WETH_USDC =
        IERC20(0xcDAC0d6c6C59727a65F871236188350531885C43);
    IVeloGauge public gauge =
        IVeloGauge(0x519BBD1Dd8C6A94C46080E24f316c14Ee758C025);
    IVeloPairFactory public veloPairFactory =
        IVeloPairFactory(0x420DD381b31aEf6683db6B902084cB0FFECe40Da);
    IVeloRouter public veloRouter =
        IVeloRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    AerodromeVolatileCToken cWETHUSDC;

    receive() external payable {}

    fallback() external payable {}

    // this is to use address(this) as mock cToken address
    function tokenType() external pure returns (uint256) {
        return 1;
    }

    function setUp() public override {
        _fork("ETH_NODE_URI_BASE", 10585060);

        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();
        _deployVeCVE();
        _deployGaugePool();
        _deployMarketManager();

        centralRegistry.addHarvester(address(this));
        centralRegistry.setFeeAccumulator(address(this));
        centralRegistry.addSwapper(address(veloRouter));
        centralRegistry.setExternalCallDataChecker(
            address(veloRouter),
            address(new MockCallDataChecker(address(veloRouter)))
        );

        cWETHUSDC = new AerodromeVolatileCToken(
            ICentralRegistry(address(centralRegistry)),
            WETH_USDC,
            address(marketManager),
            gauge,
            veloPairFactory,
            veloRouter
        );

        gaugePool.start(address(marketManager));
        vm.warp(veCVE.nextEpochStartTime());
    }

    function testWethUsdcVolatilePool() public {
        uint256 assets = 0.0001e18;
        deal(address(WETH_USDC), user1, assets);
        deal(address(WETH_USDC), address(this), 42069);

        WETH_USDC.approve(address(cWETHUSDC), 42069);
        marketManager.listToken(address(cWETHUSDC));

        vm.prank(user1);
        WETH_USDC.approve(address(cWETHUSDC), assets);

        vm.prank(user1);
        cWETHUSDC.deposit(assets, user1);

        assertEq(
            cWETHUSDC.totalAssets(),
            assets + 42069,
            "Total Assets should equal user deposit plus initial mint."
        );

        vm.startPrank(gauge.voter());
        deal(address(AERO), gauge.voter(), 10e18);
        AERO.approve(address(gauge), 10e18);
        gauge.notifyRewardAmount(10e18);
        vm.stopPrank();

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 1 days);

        // Mint some extra rewards for Vault.
        uint256 earned = gauge.earned(address(cWETHUSDC));
        uint256 amount = (earned * 84) / 100;
        SwapperLib.Swap memory swapData;
        swapData.inputToken = address(AERO);
        swapData.inputAmount = amount;
        swapData.outputToken = address(WETH);
        swapData.target = address(veloRouter);
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = address(AERO);
        routes[0].to = address(WETH);
        routes[0].stable = false;
        routes[0].factory = address(veloPairFactory);
        swapData.call = abi.encodeWithSelector(
            IVeloRouter.swapExactTokensForTokens.selector,
            amount,
            0,
            routes,
            address(cWETHUSDC),
            type(uint256).max
        );

        cWETHUSDC.harvest(abi.encode(swapData));

        assertEq(
            cWETHUSDC.totalAssets(),
            assets + 42069,
            "Total Assets should equal user deposit plus initial mint."
        );

        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        earned = gauge.earned(address(cWETHUSDC));
        amount = (earned * 84) / 100;
        swapData.inputAmount = amount;
        swapData.call = abi.encodeWithSelector(
            IVeloRouter.swapExactTokensForTokens.selector,
            amount,
            0,
            routes,
            address(cWETHUSDC),
            type(uint256).max
        );
        cWETHUSDC.harvest(abi.encode(swapData));

        vm.warp(block.timestamp + 7 days);

        assertGt(
            cWETHUSDC.totalAssets(),
            assets + 42069,
            "Total Assets should greater than original deposit plus initial mint."
        );

        vm.prank(user1);
        cWETHUSDC.withdraw(assets, user1, user1);
    }
}
