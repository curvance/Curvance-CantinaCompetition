// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { VelodromeStableCToken, IVeloGauge, IVeloRouter, IVeloPairFactory, IERC20 } from "contracts/market/collateral/VelodromeStableCToken.sol";
import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";

contract TestVelodromeStableCToken is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IERC20 public USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    IERC20 public DAI = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    IERC20 public VELO = IERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    IERC20 public USDC_DAI =
        IERC20(0x19715771E30c93915A5bbDa134d782b81A820076);
    IVeloGauge public gauge =
        IVeloGauge(0x6998089F6bDd9c74C7D8d01b99d7e379ccCcb02D);
    IVeloPairFactory public veloPairFactory =
        IVeloPairFactory(0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a);
    IVeloRouter public veloRouter =
        IVeloRouter(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    address public optiSwap = 0x6108FeAA628155b073150F408D0b390eC3121834;

    VelodromeStableCToken cUSDCDAI;

    receive() external payable {}

    fallback() external payable {}

    // this is to use address(this) as mock cToken address
    function tokenType() external pure returns (uint256) {
        return 1;
    }

    function setUp() public override {
        _fork("ETH_NODE_URI_OPTIMISM", 109095500);

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

        cUSDCDAI = new VelodromeStableCToken(
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
        VELO.approve(address(gauge), 10e18);
        gauge.notifyRewardAmount(10e18);
        vm.stopPrank();

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 1 days);

        // Mint some extra rewards for Vault.
        uint256 earned = gauge.earned(address(cUSDCDAI));
        uint256 amount = (earned * 84) / 100;
        SwapperLib.Swap memory swapData;
        swapData.inputToken = address(VELO);
        swapData.inputAmount = amount;
        swapData.outputToken = address(USDC);
        swapData.target = address(veloRouter);
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = address(VELO);
        routes[0].to = address(USDC);
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
