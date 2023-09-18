// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.17;

// import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
// import { IMToken } from "contracts/interfaces/market/IMToken.sol";

// contract SetCTokenCollateralCapsTest is TestBaseLendtroller {
//     IMToken[] public mTokens;
//     uint256[] public collateralCaps;

//     event NewCollateralCap(IMToken mToken, uint256 newCollateralCap);

//     function setUp() public override {
//         super.setUp();

//         mTokens.push(IMToken(address(dUSDC)));
//         mTokens.push(IMToken(address(dDAI)));
//         mTokens.push(IMToken(address(cBALRETH)));
//         collateralCaps.push(100e6);
//         collateralCaps.push(100e18);
//         collateralCaps.push(100e18);
//     }

//     function test_setCTokenCollateralCaps_fail_whenCallerIsNotAuthorized()
//         public
//     {
//         vm.prank(address(1));

//         vm.expectRevert("Lendtroller: UNAUTHORIZED");
//         lendtroller.setCTokenCollateralCaps(mTokens, collateralCaps);
//     }

//     function test_setCTokenCollateralCaps_fail_whenMTokenLengthIsZero()
//         public
//     {
//         // `bytes4(keccak256(bytes("Lendtroller__InvalidValue()")))`
//         vm.expectRevert(0x74ebdb4f);
//         lendtroller.setCTokenCollateralCaps(new IMToken[](0), collateralCaps);
//     }

//     function test_setCTokenCollateralCaps_fail_whenMTokenAndCollateralCapsLengthsDismatch()
//         public
//     {
//         mTokens.push(IMToken(address(dUSDC)));

//         // `bytes4(keccak256(bytes("Lendtroller__InvalidValue()")))`
//         vm.expectRevert(0x74ebdb4f);
//         lendtroller.setCTokenCollateralCaps(mTokens, collateralCaps);
//     }

//     function test_setCTokenCollateralCaps_success() public {
//         for (uint256 i = 0; i < mTokens.length; i++) {
//             vm.expectEmit(true, true, true, true, address(lendtroller));
//             emit NewCollateralCap(mTokens[i], collateralCaps[i]);
//         }

//         lendtroller.setCTokenCollateralCaps(mTokens, collateralCaps);

//         for (uint256 i = 0; i < mTokens.length; i++) {
//             assertEq(
//                 lendtroller.collateralCaps(address(mTokens[i])),
//                 collateralCaps[i]
//             );
//         }
//     }
// }
