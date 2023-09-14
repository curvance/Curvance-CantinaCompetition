// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestZapperVelodrome is TestBaseMarket {
    address _VELODROME_FACTORY = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;
    address _VELODROME_ROUTER = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;
    address _VELODROME_WETH_USDC = 0x0493Bf8b6DBB159Ce2Db2E0E8403E753Abd1235b;
    address _WETH = 0x4200000000000000000000000000000000000006;
    address _USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    bool _IS_STABLE = false;

    address public owner;
    address public user;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        _fork("ETH_NODE_URI_OPTIMISM", 109095500);

        _deployCentralRegistry();
        _deployCVE();
        _deployGaugePool();
        _deployLendtroller();

        zapper = new Zapper(
            ICentralRegistry(address(centralRegistry)),
            address(lendtroller),
            _WETH
        );
        centralRegistry.addZapper(address(zapper));

        owner = address(this);
        user = user1;
    }

    function testInitialize() public {
        assertEq(address(zapper.lendtroller()), address(lendtroller));
    }

    function testVelodromeIn() public {
        uint256 ethAmount = 3 ether;
        vm.deal(user, ethAmount);

        vm.startPrank(user);
        zapper.velodromeIn{ value: ethAmount }(
            address(0),
            Zapper.ZapperData(address(0), ethAmount, _VELODROME_WETH_USDC, 1),
            new SwapperLib.Swap[](0),
            _VELODROME_ROUTER,
            _VELODROME_FACTORY,
            user
        );
        vm.stopPrank();

        assertEq(user.balance, 0);
        assertGt(IERC20(_VELODROME_WETH_USDC).balanceOf(user), 0);
    }

    function testVelodromeOut() public {
        testVelodromeIn();

        uint256 withdrawAmount = IERC20(_VELODROME_WETH_USDC).balanceOf(user);

        vm.startPrank(user);
        IERC20(_VELODROME_WETH_USDC).approve(address(zapper), withdrawAmount);
        zapper.velodromeOut(
            _VELODROME_ROUTER,
            Zapper.ZapperData(_VELODROME_WETH_USDC, withdrawAmount, _WETH, 0),
            new SwapperLib.Swap[](0),
            user
        );
        vm.stopPrank();

        assertGt(IERC20(_WETH).balanceOf(user), 0);
        // assertGt(IERC20(_USDC).balanceOf(user), 0);
        assertEq(IERC20(_VELODROME_WETH_USDC).balanceOf(user), 0);
    }
}
