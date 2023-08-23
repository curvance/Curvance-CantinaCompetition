// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract SetMarketTokenBorrowCapsTest is TestBaseLendtroller {
    IMToken[] public mTokens;
    uint256[] public borrowCaps;

    event NewBorrowCap(IMToken mToken, uint256 newBorrowCap);

    function setUp() public override {
        super.setUp();

        mTokens.push(IMToken(address(dUSDC)));
        mTokens.push(IMToken(address(dDAI)));
        mTokens.push(IMToken(address(cBALRETH)));
        borrowCaps.push(100e6);
        borrowCaps.push(100e18);
        borrowCaps.push(100e18);
    }

    function test_setMarketTokenBorrowCaps_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("Lendtroller: UNAUTHORIZED");
        lendtroller.setMarketTokenBorrowCaps(mTokens, borrowCaps);
    }

    function test_setMarketTokenBorrowCaps_fail_whenMTokenLengthIsZero()
        public
    {
        // `bytes4(keccak256(bytes("Lendtroller__InvalidValue()")))`
        vm.expectRevert(0x74ebdb4f);
        lendtroller.setMarketTokenBorrowCaps(new IMToken[](0), borrowCaps);
    }

    function test_setMarketTokenBorrowCaps_fail_whenMTokenAndBorrowCapsLengthsDismatch()
        public
    {
        mTokens.push(IMToken(address(dUSDC)));

        // `bytes4(keccak256(bytes("Lendtroller__InvalidValue()")))`
        vm.expectRevert(0x74ebdb4f);
        lendtroller.setMarketTokenBorrowCaps(mTokens, borrowCaps);
    }

    function test_setMarketTokenBorrowCaps_success() public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            vm.expectEmit(true, true, true, true, address(lendtroller));
            emit NewBorrowCap(mTokens[i], borrowCaps[i]);
        }

        lendtroller.setMarketTokenBorrowCaps(mTokens, borrowCaps);

        for (uint256 i = 0; i < mTokens.length; i++) {
            assertEq(
                lendtroller.borrowCaps(address(mTokens[i])),
                borrowCaps[i]
            );
        }
    }
}
