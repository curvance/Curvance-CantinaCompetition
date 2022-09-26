// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/lib/DSTestPlus.sol";

contract TestExample is DSTestPlus {
    uint256 number;

    function setUp() public {
        number = 10;
    }

    function testNumber() public {
        assertEq(number, 10);
    }
}
