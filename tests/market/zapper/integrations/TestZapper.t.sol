// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestZapper is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address _CURVE_TRICRYPTO_LP = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;
    address _CURVE_TRICRYPTO_MINTER =
        0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;

    address public owner;
    address public user;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        owner = address(this);
        user = user1;
    }

    function testInitialize() public {
        assertEq(address(zapper.marketManager()), address(marketManager));
    }

    function testCurveInWithETH() public {
        uint256 ethAmount = 3 ether;
        vm.deal(user, ethAmount);

        vm.startPrank(user);
        address[] memory tokens = new address[](3);
        tokens[0] = _USDT_ADDRESS;
        tokens[1] = _WBTC_ADDRESS;
        tokens[2] = _WETH_ADDRESS;
        zapper.curveIn{ value: ethAmount }(
            address(0),
            Zapper.ZapperData(
                address(0),
                ethAmount,
                _CURVE_TRICRYPTO_LP,
                1,
                true
            ),
            new SwapperLib.Swap[](0),
            _CURVE_TRICRYPTO_MINTER,
            tokens,
            user
        );
        vm.stopPrank();

        assertEq(user.balance, 0);
        assertGt(IERC20(_CURVE_TRICRYPTO_LP).balanceOf(user), 0);
    }

    function testCurveInWithWETH() public {
        uint256 wethAmount = 3 ether;
        deal(_WETH_ADDRESS, user, wethAmount);

        vm.startPrank(user);
        IERC20(_WETH_ADDRESS).approve(address(zapper), wethAmount);
        address[] memory tokens = new address[](3);
        tokens[0] = _USDT_ADDRESS;
        tokens[1] = _WBTC_ADDRESS;
        tokens[2] = _WETH_ADDRESS;
        zapper.curveIn(
            address(0),
            Zapper.ZapperData(
                _WETH_ADDRESS,
                wethAmount,
                _CURVE_TRICRYPTO_LP,
                1,
                false
            ),
            new SwapperLib.Swap[](0),
            _CURVE_TRICRYPTO_MINTER,
            tokens,
            user
        );
        vm.stopPrank();

        assertEq(user.balance, 0);
        assertGt(IERC20(_CURVE_TRICRYPTO_LP).balanceOf(user), 0);
    }

    function testCurveOut() public {
        testCurveInWithETH();

        uint256 withdrawAmount = IERC20(_CURVE_TRICRYPTO_LP).balanceOf(user);

        vm.startPrank(user);
        address[] memory tokens = new address[](3);
        tokens[0] = _USDT_ADDRESS;
        tokens[1] = _WBTC_ADDRESS;
        tokens[2] = _WETH_ADDRESS;
        IERC20(_CURVE_TRICRYPTO_LP).approve(address(zapper), withdrawAmount);
        zapper.curveOut(
            _CURVE_TRICRYPTO_MINTER,
            Zapper.ZapperData(
                _CURVE_TRICRYPTO_LP,
                withdrawAmount,
                _WETH_ADDRESS,
                0,
                false
            ),
            tokens,
            1,
            2,
            new SwapperLib.Swap[](0),
            user
        );
        vm.stopPrank();

        assertApproxEqRel(
            IERC20(_WETH_ADDRESS).balanceOf(user),
            3 ether,
            0.01 ether
        );
        assertEq(IERC20(_CURVE_TRICRYPTO_LP).balanceOf(user), 0);
    }
}
