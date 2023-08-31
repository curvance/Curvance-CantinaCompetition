// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestZapper is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

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
        assertEq(address(zapper.lendtroller()), address(lendtroller));
    }
}
