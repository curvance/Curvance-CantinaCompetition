// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// import "forge-std/StdStorage.sol";
// import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";
// import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
// import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
// import { IERC20 } from "contracts/interfaces/IERC20.sol";

// contract CTokenCompounding_DeploymentTest is
//     TestBaseCTokenCompounding
// {
//     using stdStorage for StdStorage;

//     event NewLendtroller(address oldLendtroller, address newLendtroller);

//     function test_CTokenCompoundingDeployment_fail_whenCentralRegistryIsInvalid()
//         public
//     {
//         vm.expectRevert(
//             CTokenCompounding
//                 .CTokenCompounding__InvalidCentralRegistry
//                 .selector
//         );
//         new CTokenCompounding(
//             ICentralRegistry(address(0)),
//             _BALANCER_WETH_RETH,
//             address(lendtroller)
//         );
//     }

//     function test_CTokenCompoundingDeployment_fail_whenLendtrollerIsNotSet()
//         public
//     {
//         vm.expectRevert(
//             CTokenCompounding
//                 .CTokenCompounding__LendtrollerIsNotLendingMarket
//                 .selector
//         );
//         new CTokenCompounding(
//             ICentralRegistry(address(centralRegistry)),
//             _BALANCER_WETH_RETH,
//             address(1)
//         );
//     }

//     function test_CTokenCompoundingDeployment_fail_whenUnderlyingTotalSupplyExceedsMaximum()
//         public
//     {
//         stdstore
//             .target(_BALANCER_WETH_RETH)
//             .sig(IERC20.totalSupply.selector)
//             .checked_write(type(uint232).max);

//         vm.expectRevert(
//             CTokenCompounding
//                 .CTokenCompounding__UnderlyingAssetTotalSupplyExceedsMaximum
//                 .selector
//         );
//         new CTokenCompounding(
//             ICentralRegistry(address(centralRegistry)),
//             _BALANCER_WETH_RETH,
//             address(lendtroller)
//         );
//     }

//     function test_CTokenCompoundingDeployment_success() public {
//         vm.expectEmit(true, true, true, true);
//         emit NewLendtroller(address(0), address(lendtroller));

//         cBALRETH = new CTokenCompounding(
//             ICentralRegistry(address(centralRegistry)),
//             _BALANCER_WETH_RETH,
//             address(lendtroller)
//         );

//         assertEq(
//             address(cBALRETH.centralRegistry()),
//             address(centralRegistry)
//         );
//         assertEq(cBALRETH.underlying(), _BALANCER_WETH_RETH);
//         assertEq(address(cBALRETH.vault()), address(0));
//         assertEq(address(cBALRETH.lendtroller()), address(lendtroller));
//         //assertEq(cBALRETH.name(), "Curvance collateralized cBAL-WETH-RETH");
//     }
// }
