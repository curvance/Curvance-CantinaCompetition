// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";

contract RemoveAuthorizedRewardTokenTest is TestBaseCVELocker {
    function test_removeAuthorizedRewardToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.removeAuthorizedRewardToken(_USDC_ADDRESS);
    }

    function test_removeAuthorizedRewardToken_fail_whenTokenIsZeroAddress()
        public
    {
        vm.expectRevert(CVELocker.CVELocker__ParametersareInvalid.selector);
        cveLocker.removeAuthorizedRewardToken(address(0));
    }

    function test_removeAuthorizedRewardToken_fail_whenTokenIsNotAuthorized()
        public
    {
        vm.expectRevert(CVELocker.CVELocker__ParametersareInvalid.selector);
        cveLocker.removeAuthorizedRewardToken(_USDC_ADDRESS);
    }

    function test_removeAuthorizedRewardToken_success() public {
        cveLocker.addAuthorizedRewardToken(_USDC_ADDRESS);

        assertEq(cveLocker.authorizedRewardToken(_USDC_ADDRESS), 2);

        cveLocker.removeAuthorizedRewardToken(_USDC_ADDRESS);

        assertEq(cveLocker.authorizedRewardToken(_USDC_ADDRESS), 1);
    }
}
