// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract DTokenSetLendtrollerTest is TestBaseDToken {
    Lendtroller public newLendtroller;

    function setUp() public override {
        super.setUp();

        newLendtroller = new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );
    }

    function test_dTokenSetLendtroller_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(DToken.DToken__Unauthorized.selector);
        dUSDC.setLendtroller(address(newLendtroller));
    }

    function test_dTokenSetLendtroller_fail_whenLendtrollerIsInvalid() public {
        vm.expectRevert(DToken.DToken__LendtrollerIsNotLendingMarket.selector);
        dUSDC.setLendtroller(address(1));
    }

    function test_dTokenSetLendtroller_success() public {
        centralRegistry.addLendingMarket(address(newLendtroller), 0);

        assertEq(address(dUSDC.lendtroller()), address(lendtroller));

        dUSDC.setLendtroller(address(newLendtroller));

        assertEq(address(dUSDC.lendtroller()), address(newLendtroller));
    }
}
