// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ERC20 } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { VelodromeStablePositionVault, BasePositionVault, IVeloGauge, IVeloRouter, IVeloPairFactory } from "contracts/deposits/adaptors/VelodromeStablePositionVault.sol";

import "tests/market/TestBaseMarket.sol";

contract TestVelodromeStablePositionVault is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public owner;
    address public user;

    VelodromeStablePositionVault positionVault;

    IVeloPairFactory private veloPairFactory =
        IVeloPairFactory(0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746);
    IVeloRouter private veloRouter =
        IVeloRouter(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);
    address private optiSwap = 0x6108FeAA628155b073150F408D0b390eC3121834;

    ERC20 private USDC = ERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    ERC20 private DAI = ERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    ERC20 private VELO = ERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);

    ERC20 private USDC_DAI = ERC20(0x4F7ebc19844259386DBdDB7b2eB759eeFc6F8353);
    IVeloGauge private gauge =
        IVeloGauge(0xc4fF55A961bC04b880e60219CCBBDD139c6451A4);

    receive() external payable {}

    fallback() external payable {}

    // this is to use address(this) as mock CToken address
    function tokenType() external pure returns (uint256) {
        return 1;
    }

    function setUp() public override {
        _fork("ETH_NODE_URI_OPTIMISM", 109095500);

        owner = address(this);
        user = user1;

        _deployCentralRegistry();
        centralRegistry.addHarvester(address(this));
        centralRegistry.setFeeAccumulator(address(this));

        positionVault = new VelodromeStablePositionVault(
            USDC_DAI,
            ICentralRegistry(address(centralRegistry)),
            gauge,
            veloPairFactory,
            veloRouter
        );
        positionVault.initiateVault(address(this));
    }

    function testUsdcDaiStablePool() public {
        uint256 assets = 100e18;
        deal(address(USDC_DAI), address(this), assets);
        USDC_DAI.approve(address(positionVault), assets);

        positionVault.deposit(assets, address(this));

        assertEq(
            positionVault.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Mint some extra rewards for Vault.
        deal(address(VELO), address(positionVault), 100e18);
        deal(address(DAI), address(positionVault), 100e18);
        deal(address(USDC), address(positionVault), 100e6);

        positionVault.harvest(abi.encode(new SwapperLib.Swap[](0)));

        assertEq(
            positionVault.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );

        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        deal(address(VELO), address(positionVault), 100e18);
        deal(address(DAI), address(positionVault), 100e18);
        deal(address(USDC), address(positionVault), 100e6);
        positionVault.harvest(abi.encode(new SwapperLib.Swap[](0)));
        vm.warp(block.timestamp + 7 days);

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
