// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";

contract AddAuthorizedRewardTokenTest is TestBaseCVELocker {
    function test_addAuthorizedRewardToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);
    }

    function test_addAuthorizedRewardToken_fail_whenTokenIsZeroAddress()
        public
    {
        vm.expectRevert(
            CVELocker.CVELocker__RewardTokenIsZeroAddress.selector
        );
        cveLocker.addAuthorizedRewardToken(address(0));
    }

    function test_addAuthorizedRewardToken_fail_whenTokenIsAlreadyAuthorized()
        public
    {
        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);

        vm.expectRevert(
            CVELocker.CVELocker__RewardTokenIsAlreadyAuthorized.selector
        );
        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);
    }

    function test_addAuthorizedRewardToken_success() public {
        assertEq(cveLocker.authorizedRewardToken(_USDC_ADDRESS), 0);

        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);

        assertEq(cveLocker.authorizedRewardToken(_USDC_ADDRESS), 2);
    }
}
