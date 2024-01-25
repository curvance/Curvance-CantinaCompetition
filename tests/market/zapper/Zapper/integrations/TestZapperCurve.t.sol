// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestZapperCurve is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address _CURVE_STETH_LP = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
    address _CURVE_STETH_MINTER = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
    address _STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

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
        address[] memory tokens = new address[](2);
        tokens[0] = _ETH_ADDRESS;
        tokens[1] = _STETH_ADDRESS;
        zapper.curveIn{ value: ethAmount }(
            address(0),
            Zapper.ZapperData(
                _ETH_ADDRESS,
                ethAmount,
                _CURVE_STETH_LP,
                1,
                false
            ),
            new SwapperLib.Swap[](0),
            _CURVE_STETH_MINTER,
            tokens,
            user
        );
        vm.stopPrank();

        assertEq(user.balance, 0);
        assertGt(IERC20(_CURVE_STETH_LP).balanceOf(user), 0);
    }

    function testCurveOut() public {
        testCurveInWithETH();

        uint256 withdrawAmount = IERC20(_CURVE_STETH_LP).balanceOf(user);

        vm.startPrank(user);
        address[] memory tokens = new address[](2);
        tokens[0] = _ETH_ADDRESS;
        tokens[1] = _STETH_ADDRESS;
        IERC20(_CURVE_STETH_LP).approve(address(zapper), withdrawAmount);
        zapper.curveOut(
            _CURVE_STETH_MINTER,
            Zapper.ZapperData(
                _CURVE_STETH_LP,
                withdrawAmount,
                _ETH_ADDRESS,
                0,
                false
            ),
            tokens,
            2,
            0,
            new SwapperLib.Swap[](0),
            user
        );
        vm.stopPrank();

        assertApproxEqRel(user.balance, 3 ether, 0.01 ether);
        assertEq(IERC20(_CURVE_STETH_LP).balanceOf(user), 0);
    }
}
