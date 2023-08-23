// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract SetCollateralizationRatioTest is TestBaseLendtroller {
    event NewCollateralizationRatio(
        IMToken mToken,
        uint256 oldCR,
        uint256 newCR
    );

    function test_setCollateralizationRatio_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("Lendtroller: UNAUTHORIZED");
        lendtroller.setCollateralizationRatio(IMToken(address(dUSDC)), 0.9e18);
    }

    function test_setCollateralizationRatio_fail_whenNewValueExceedsMaximum()
        public
    {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidValue.selector);
        lendtroller.setCollateralizationRatio(
            IMToken(address(dUSDC)),
            0.9e18 + 1
        );
    }

    function test_setCollateralizationRatio_fail_whenMTokenIsNotListed()
        public
    {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.setCollateralizationRatio(IMToken(address(dUSDC)), 0.9e18);
    }

    function test_setCollateralizationRatio_success() public {
        lendtroller.listMarketToken(address(dUSDC));

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit NewCollateralizationRatio(IMToken(address(dUSDC)), 0, 0.9e18);

        lendtroller.setCollateralizationRatio(IMToken(address(dUSDC)), 0.9e18);

        (, uint256 collateralizationRatio) = lendtroller.getMarketTokenData(
            address(dUSDC)
        );
        assertEq(collateralizationRatio, 0.9e18);
    }
}
