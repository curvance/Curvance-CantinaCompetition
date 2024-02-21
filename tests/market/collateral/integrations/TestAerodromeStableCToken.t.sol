// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { AerodromeStableCToken, IVeloGauge, IVeloRouter, IVeloPairFactory, IERC20 } from "contracts/market/collateral/AerodromeStableCToken.sol";
import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";

contract TestAerodromeStableCToken is TestBaseMarket {
    IERC20 public USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20 public DAI = IERC20(0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb);
    IERC20 public AERO = IERC20(0x940181a94A35A4569E4529A3CDfB74e38FD98631);
    IERC20 public USDC_DAI =
        IERC20(0x67b00B46FA4f4F24c03855c5C8013C0B938B3eEc);
    IVeloGauge public gauge =
        IVeloGauge(0x640e9ef68e1353112fF18826c4eDa844E1dC5eD0);
    IVeloPairFactory public veloPairFactory =
        IVeloPairFactory(0x420DD381b31aEf6683db6B902084cB0FFECe40Da);
    IVeloRouter public veloRouter =
        IVeloRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    AerodromeStableCToken cUSDCDAI;

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

        cUSDCDAI = new AerodromeStableCToken(
            ICentralRegistry(address(centralRegistry)),
            USDC_DAI,
            address(marketManager),
            gauge,
            veloPairFactory,
            veloRouter
        );

        gaugePool.start(address(marketManager));
        vm.warp(veCVE.nextEpochStartTime());
    }

    function testUsdcDaiStablePool() public {
        uint256 assets = 100e18;
        deal(address(USDC_DAI), user1, assets);
        deal(address(USDC_DAI), address(this), 42069);

        USDC_DAI.approve(address(cUSDCDAI), 42069);
        marketManager.listToken(address(cUSDCDAI));

        vm.prank(user1);
        USDC_DAI.approve(address(cUSDCDAI), assets);

        vm.prank(user1);
        cUSDCDAI.deposit(assets, user1);

        assertEq(
            cUSDCDAI.totalAssets(),
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
        uint256 earned = gauge.earned(address(cUSDCDAI));
        uint256 amount = (earned * 84) / 100;
        SwapperLib.Swap memory swapData;
        swapData.inputToken = address(AERO);
        swapData.inputAmount = amount;
        swapData.outputToken = address(DAI);
        swapData.target = address(veloRouter);
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = address(AERO);
        routes[0].to = address(DAI);
        routes[0].stable = false;
        routes[0].factory = address(veloPairFactory);
        swapData.call = abi.encodeWithSelector(
            IVeloRouter.swapExactTokensForTokens.selector,
            amount,
            0,
            routes,
            address(cUSDCDAI),
            type(uint256).max
        );

        cUSDCDAI.harvest(abi.encode(swapData));

        assertEq(
            cUSDCDAI.totalAssets(),
            assets + 42069,
            "Total Assets should equal user deposit plus initial mint."
        );

        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        earned = gauge.earned(address(cUSDCDAI));
        amount = (earned * 84) / 100;
        swapData.inputAmount = amount;
        swapData.call = abi.encodeWithSelector(
            IVeloRouter.swapExactTokensForTokens.selector,
            amount,
            0,
            routes,
            address(cUSDCDAI),
            type(uint256).max
        );
        cUSDCDAI.harvest(abi.encode(swapData));

        vm.warp(block.timestamp + 7 days);

        assertGt(
            cUSDCDAI.totalAssets(),
            assets + 42069,
            "Total Assets should greater than original deposit plus initial mint."
        );

        vm.prank(user1);
        cUSDCDAI.withdraw(assets, user1, user1);
    }
}
