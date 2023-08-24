// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract SetPositionFoldingTest is TestBaseLendtroller {
    event NewPositionFoldingContract(address oldPF, address newPF);

    function test_setPositionFolding_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("Lendtroller: UNAUTHORIZED");
        lendtroller.setPositionFolding(address(positionFolding));
    }

    function test_setPositionFolding_fail_whenPositionFoldingIsInvalid()
        public
    {
        vm.expectRevert(
            Lendtroller.Lendtroller__PositionFoldingIsInvalid.selector
        );
        lendtroller.setPositionFolding(address(1));
    }

    function test_setPositionFolding_success() public {
        address oldPositionFolding = lendtroller.positionFolding();

        _deployPositionFolding();

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit NewPositionFoldingContract(
            oldPositionFolding,
            address(positionFolding)
        );

        lendtroller.setPositionFolding(address(positionFolding));

        assertEq(lendtroller.positionFolding(), address(positionFolding));
    }
}
