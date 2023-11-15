// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { VelodromeVolatileCToken, IVeloGauge, IVeloRouter, IVeloPairFactory, ERC20 } from "contracts/market/collateral/VelodromeVolatileCToken.sol";

import "tests/market/TestBaseMarket.sol";

contract TestVelodromeVolatileCToken is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ERC20 public WETH = ERC20(0x4200000000000000000000000000000000000006);
    ERC20 public USDC = ERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    ERC20 public VELO = ERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    ERC20 public WETH_USDC = ERC20(0x0493Bf8b6DBB159Ce2Db2E0E8403E753Abd1235b);

    IVeloPairFactory public veloPairFactory =
        IVeloPairFactory(0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a);
    IVeloRouter public veloRouter =
        IVeloRouter(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    address public optiSwap = 0x6108FeAA628155b073150F408D0b390eC3121834;
    IVeloGauge public gauge =
        IVeloGauge(0xE7630c9560C59CCBf5EEd8f33dd0ccA2E67a3981);

    VelodromeVolatileCToken cToken;
    CToken public cWETHUSDC;

    receive() external payable {}

    fallback() external payable {}

    // this is to use address(this) as mock CToken address
    function tokenType() external pure returns (uint256) {
        return 1;
    }

    function setUp() public override {
        _fork("ETH_NODE_URI_OPTIMISM", 109095500);

        _deployCentralRegistry();
        _deployGaugePool();
        _deployLendtroller();

        centralRegistry.addHarvester(address(this));
        centralRegistry.setFeeAccumulator(address(this));
        centralRegistry.addSwapper(address(veloRouter));

        cToken = new VelodromeVolatileCToken(
            WETH_USDC,
            ICentralRegistry(address(centralRegistry)),
            gauge,
            veloPairFactory,
            veloRouter
        );

        cWETHUSDC = new CToken(
            ICentralRegistry(address(centralRegistry)),
            address(WETH_USDC),
            address(lendtroller),
            address(cToken)
        );
        cToken.initiateVault(address(cWETHUSDC));
    }

    function testWethUsdcVolatilePool() public {
        uint256 assets = 0.0001e18;
        deal(address(WETH_USDC), address(cWETHUSDC), assets);

        vm.prank(address(cWETHUSDC));
        WETH_USDC.approve(address(cToken), assets);

        vm.prank(address(cWETHUSDC));
        cToken.deposit(assets, address(this));

        assertEq(
            cToken.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 1 days);

        // Mint some extra rewards for Vault.
        uint256 earned = gauge.earned(address(cToken));
        uint256 amount = (earned * 84) / 100;
        SwapperLib.Swap memory swapData;
        swapData.inputToken = address(VELO);
        swapData.inputAmount = amount;
        swapData.outputToken = address(WETH);
        swapData.target = address(veloRouter);
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = address(VELO);
        routes[0].to = address(WETH);
        routes[0].stable = false;
        routes[0].factory = address(veloPairFactory);
        swapData.call = abi.encodeWithSelector(
            IVeloRouter.swapExactTokensForTokens.selector,
            amount,
            0,
            routes,
            address(cToken),
            type(uint256).max
        );

        cToken.harvest(abi.encode(swapData));

        assertEq(
            cToken.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );

        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        earned = gauge.earned(address(cToken));
        amount = (earned * 84) / 100;
        swapData.inputAmount = amount;
        swapData.call = abi.encodeWithSelector(
            IVeloRouter.swapExactTokensForTokens.selector,
            amount,
            0,
            routes,
            address(cToken),
            type(uint256).max
        );
        cToken.harvest(abi.encode(swapData));
        vm.warp(block.timestamp + 7 days);

        uint256 totalAssets = cToken.totalAssets();

        assertGt(
            totalAssets,
            assets,
            "Total Assets should greater than original deposit."
        );

        vm.prank(address(cWETHUSDC));
        cToken.withdraw(totalAssets, address(this), address(this));
    }
}
