// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseSimpleRewardZaper } from "../TestBaseSimpleRewardZaper.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { SimpleRewardZapper } from "contracts/architecture/utils/SimpleRewardZapper.sol";

contract AddAuthorizedRewardTokenTest is TestBaseSimpleRewardZaper {
    function test_addAuthorizedRewardToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(
            SimpleRewardZapper.SimpleRewardZapper__Unauthorized.selector
        );
        simpleRewardZapper.addAuthorizedOutputToken(_USDC_ADDRESS);
    }

    function test_addAuthorizedRewardToken_fail_whenTokenIsZeroAddress()
        public
    {
        vm.expectRevert(
            SimpleRewardZapper.SimpleRewardZapper__UnknownOutputToken.selector
        );
        simpleRewardZapper.addAuthorizedOutputToken(address(0));
    }

    function test_addAuthorizedRewardToken_fail_whenTokenIsAlreadyAuthorized()
        public
    {
        simpleRewardZapper.addAuthorizedOutputToken(_USDC_ADDRESS);

        vm.expectRevert(
            SimpleRewardZapper.SimpleRewardZapper__IsAlreadyAuthorized.selector
        );
        simpleRewardZapper.addAuthorizedOutputToken(_USDC_ADDRESS);
    }

    function test_addAuthorizedRewardToken_success() public {
        assertEq(simpleRewardZapper.authorizedOutputToken(_USDC_ADDRESS), 0);

        simpleRewardZapper.addAuthorizedOutputToken(_USDC_ADDRESS);

        assertEq(simpleRewardZapper.authorizedOutputToken(_USDC_ADDRESS), 2);
    }
}
