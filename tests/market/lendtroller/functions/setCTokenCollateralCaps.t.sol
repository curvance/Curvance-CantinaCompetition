// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract SetCTokenCollateralCapsTest is TestBaseLendtroller {
    address[] public mTokens;
    uint256[] public collateralCaps;

    event NewCollateralCap(address mToken, uint256 newCollateralCap);

    function setUp() public override {
        super.setUp();

        mTokens.push(address(dUSDC));
        mTokens.push(address(dDAI));
        mTokens.push(address(cBALRETH));
        collateralCaps.push(100e6);
        collateralCaps.push(100e18);
        collateralCaps.push(100e18);
    }

    function test_setCTokenCollateralCaps_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));
        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.setCTokenCollateralCaps(mTokens, collateralCaps);
    }

    function test_setCTokenCollateralCaps_fail_whenMTokenLengthIsZero()
        public
    {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.setCTokenCollateralCaps(new address[](0), collateralCaps);
    }

    function test_setCTokenCollateralCaps_fail_whenMTokenAndCapsLengthsMismatch()
        public
    {
        mTokens.push(address(dUSDC));
        assertNotEq(mTokens.length, collateralCaps.length);
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.setCTokenCollateralCaps(mTokens, collateralCaps);
        mTokens.pop();
    }

    function test_setCTokenCollateralCaps_fail_whenNotCToken() public {
        assertEq(mTokens.length, collateralCaps.length);
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.setCTokenCollateralCaps(mTokens, collateralCaps);
    }

    function test_setCTokenCollateralCaps_success() public {
        deal(_BALANCER_WETH_RETH, address(this), 1 ether);
        balRETH.approve(address(cBALRETH), 1 ether);
        lendtroller.listToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000,
            4000,
            3000,
            200,
            200,
            100,
            1000
        );

        address[] memory validMTokens = new address[](2);
        validMTokens[0] = address(cBALRETH);
        validMTokens[1] = address(cBALRETH);
        uint256[] memory validCollateralCaps = new uint256[](2);
        validCollateralCaps[0] = 100e18;
        validCollateralCaps[1] = 10e18;

        for (uint256 i = 0; i < validMTokens.length; i++) {
            vm.expectEmit(address(lendtroller));
            emit NewCollateralCap(validMTokens[i], validCollateralCaps[i]);
        }

        lendtroller.setCTokenCollateralCaps(validMTokens, validCollateralCaps);

        assertEq(
            lendtroller.collateralCaps(address(cBALRETH)),
            validCollateralCaps[1]
        );
    }
}
