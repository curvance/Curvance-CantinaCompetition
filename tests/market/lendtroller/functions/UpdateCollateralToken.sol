// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract UpdateCollateralTokenTest is TestBaseLendtroller {
    event CollateralTokenUpdated(
        IMToken mToken,
        uint256 newLI,
        uint256 newLF,
        uint256 newCR
    );

    function test_updateCollateralToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("Lendtroller: UNAUTHORIZED");
        lendtroller.updateCollateralToken(
            IMToken(address(dUSDC)),
            200,
            0,
            9000
        );
    }

    function test_updateCollateralToken_fail_whenNewValueExceedsMaximum()
        public
    {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(dUSDC)),
            200,
            0,
            9100 + 1
        );
    }

    function test_updateCollateralToken_fail_whenMTokenIsNotListed() public {
        _deployCBALRETH();

        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            200,
            0,
            9000
        );
    }

    function test_updateCollateralToken_success() public {
        balRETH.approve(address(cBALRETH), 1e18);
        lendtroller.listMarketToken(address(cBALRETH));

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit CollateralTokenUpdated(
            IMToken(address(cBALRETH)),
            0.02e18,
            0,
            0.9e18
        );

        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            200,
            0,
            9000
        );

        (, , uint256 collateralizationRatio) = lendtroller.getMTokenData(
            address(cBALRETH)
        );
        assertEq(collateralizationRatio, 0.9e18);
    }
}
