// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCTokenCompoundingBase } from "../TestBaseCTokenCompoundingBase.sol";
import { CTokenCompoundingBase } from "contracts/market/collateral/CTokenCompoundingBase.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CTokenCompoundingBase_SetLendtrollerTest is TestBaseCTokenCompoundingBase {
    Lendtroller public newLendtroller;

    function setUp() public override {
        super.setUp();

        newLendtroller = new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );
    }

    function test_CTokenCompoundingBase_SetLendtroller_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(CTokenCompoundingBase.CTokenCompoundingBase__Unauthorized.selector);
        cBALRETH.setLendtroller(address(newLendtroller));
    }

    function test_CTokenCompoundingBase_SetLendtroller_fail_whenLendtrollerIsInvalid() public {
        vm.expectRevert(CTokenCompoundingBase.CTokenCompoundingBase__LendtrollerIsNotLendingMarket.selector);
        cBALRETH.setLendtroller(address(1));
    }

    function test_CTokenCompoundingBase_SetLendtroller_success() public {
        centralRegistry.addLendingMarket(address(newLendtroller), 0);

        assertEq(address(cBALRETH.lendtroller()), address(lendtroller));

        cBALRETH.setLendtroller(address(newLendtroller));

        assertEq(address(cBALRETH.lendtroller()), address(newLendtroller));
    }
}
