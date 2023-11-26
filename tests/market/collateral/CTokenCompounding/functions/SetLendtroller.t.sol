// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";
// import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
// import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
// import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

// contract CTokenCompounding_SetLendtrollerTest is TestBaseCTokenCompounding {
//     Lendtroller public newLendtroller;

//     function setUp() public override {
//         super.setUp();

//         newLendtroller = new Lendtroller(
//             ICentralRegistry(address(centralRegistry)),
//             address(gaugePool)
//         );
//     }

//     function test_CTokenCompounding_SetLendtroller_fail_whenCallerIsNotAuthorized()
//         public
//     {
//         vm.prank(address(1));

//         vm.expectRevert(CTokenCompounding.CTokenCompounding__Unauthorized.selector);
//         cBALRETH.setLendtroller(address(newLendtroller));
//     }

//     function test_CTokenCompounding_SetLendtroller_fail_whenLendtrollerIsInvalid() public {
//         vm.expectRevert(CTokenCompounding.CTokenCompounding__LendtrollerIsNotLendingMarket.selector);
//         cBALRETH.setLendtroller(address(1));
//     }

//     function test_CTokenCompounding_SetLendtroller_success() public {
//         centralRegistry.addLendingMarket(address(newLendtroller), 0);

//         assertEq(address(cBALRETH.lendtroller()), address(lendtroller));

//         cBALRETH.setLendtroller(address(newLendtroller));

//         assertEq(address(cBALRETH.lendtroller()), address(newLendtroller));
//     }
// }
