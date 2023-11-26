// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";
// import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
// import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";

// contract CTokenCompounding_MintTest is TestBaseCTokenCompounding {
//     event Transfer(address indexed from, address indexed to, uint256 amount);

//     function test_CTokenCompounding_Mint_fail_whenTransferZeroAmount()
//         public
//     {
//         vm.expectRevert(
//             CTokenCompounding.CTokenCompounding__ZeroShares.selector
//         );
//         cBALRETH.mint(0);
//     }

//     function test_CTokenCompounding_Mint_fail_whenMintIsNotAllowed()
//         public
//     {
//         lendtroller.setMintPaused(address(cBALRETH), true);

//         vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
//         cBALRETH.mint(100);
//     }

//     function test_CTokenCompounding_Mint_success() public {
//         uint256 underlyingBalance = balRETH.balanceOf(address(this));
//         uint256 balance = cBALRETH.balanceOf(address(this));
//         uint256 totalSupply = cBALRETH.totalSupply();

//         vm.expectEmit(true, true, true, true, address(cBALRETH));
//         emit Transfer(address(0), address(this), 100);

//         cBALRETH.mint(100);

//         assertEq(balRETH.balanceOf(address(this)), underlyingBalance - 100);
//         assertEq(cBALRETH.balanceOf(address(this)), balance + 100);
//         assertEq(cBALRETH.totalSupply(), totalSupply + 100);
//     }
// }
