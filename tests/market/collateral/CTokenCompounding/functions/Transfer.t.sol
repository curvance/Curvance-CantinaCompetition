// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";
// import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
// import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
// import { MarketManager } from "contracts/market/MarketManager.sol";

// contract CTokenCompounding_TransferTest is TestBaseCTokenCompounding {
//     event Transfer(address indexed from, address indexed to, uint256 amount);

//     function test_CTokenCompounding_Transfer_fail_whenSenderAndReceiverAreSame() public {
//         vm.expectRevert(CTokenCompounding.CTokenCompounding__TransferError.selector);
//         cBALRETH.transfer(address(this), 100);
//     }

//     function test_CTokenCompounding_Transfer_fail_whenTransferZeroAmount() public {
//         vm.expectRevert(GaugeErrors.InvalidAmount.selector);
//         cBALRETH.transfer(user1, 0);
//     }

//     function test_CTokenCompounding_Transfer_fail_whenTransferIsNotAllowed() public {
//         marketManager.setTransferPaused(true);

//         vm.expectRevert(MarketManager.MarketManager__Paused.selector);
//         cBALRETH.transfer(user1, 0);
//     }

//     function test_CTokenCompounding_Transfer_success() public {
//         cBALRETH.mint(100);

//         uint256 balance = cBALRETH.balanceOf(address(this));
//         uint256 user1Balance = cBALRETH.balanceOf(user1);

//         vm.expectEmit(true, true, true, true, address(cBALRETH));
//         emit Transfer(address(this), user1, 100);

//         cBALRETH.transfer(user1, 100);

//         assertEq(cBALRETH.balanceOf(address(this)), balance - 100);
//         assertEq(cBALRETH.balanceOf(user1), user1Balance + 100);
//     }
// }
