// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";

contract AddAuthorizedRewardTokenTest is TestBaseCVELocker {
    function test_addAuthorizedRewardToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("CVELocker: UNAUTHORIZED");
        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);
    }

    function test_addAuthorizedRewardToken_fail_whenTokenIsZeroAddress()
        public
    {
        vm.expectRevert("CVELocker: Invalid Token Address");
        cveLocker.addAuthorizedRewardToken(address(0));
    }

    function test_addAuthorizedRewardToken_fail_whenTokenIsAlreadyAuthorized()
        public
    {
        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);

        vm.expectRevert("CVELocker: Invalid Operation");
        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);
    }

    function test_addAuthorizedRewardToken_success() public {
        assertEq(cveLocker.authorizedRewardToken(_USDC_ADDRESS), 0);

        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);

        assertEq(cveLocker.authorizedRewardToken(_USDC_ADDRESS), 2);
    }
}
