// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CTokenSetLendtrollerTest is TestBaseCToken {
    Lendtroller public newLendtroller;

    function setUp() public override {
        super.setUp();

        newLendtroller = new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );
    }

    function test_cTokenSetLendtroller_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("CToken: UNAUTHORIZED");
        cBALRETH.setLendtroller(address(newLendtroller));
    }

    function test_cTokenSetLendtroller_fail_whenLendtrollerIsInvalid() public {
        vm.expectRevert(CToken.CToken__LendtrollerIsNotLendingMarket.selector);
        cBALRETH.setLendtroller(address(1));
    }

    function test_cTokenSetLendtroller_success() public {
        centralRegistry.addLendingMarket(address(newLendtroller));

        assertEq(address(cBALRETH.lendtroller()), address(lendtroller));

        cBALRETH.setLendtroller(address(newLendtroller));

        assertEq(address(cBALRETH.lendtroller()), address(newLendtroller));
    }
}
