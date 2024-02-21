// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseSimpleRewardZaper } from "../TestBaseSimpleRewardZaper.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { SimpleRewardZapper } from "contracts/architecture/utils/SimpleRewardZapper.sol";

contract RemoveAuthorizedRewardTokenTest is TestBaseSimpleRewardZaper {
    function test_removeAuthorizedRewardToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(
            SimpleRewardZapper.SimpleRewardZapper__Unauthorized.selector
        );
        simpleRewardZapper.removeAuthorizedOutputToken(_USDC_ADDRESS);
    }

    function test_removeAuthorizedRewardToken_fail_whenTokenIsZeroAddress()
        public
    {
        vm.expectRevert(
            SimpleRewardZapper.SimpleRewardZapper__UnknownOutputToken.selector
        );
        simpleRewardZapper.removeAuthorizedOutputToken(address(0));
    }

    function test_removeAuthorizedRewardToken_fail_whenTokenIsNotAuthorized()
        public
    {
        vm.expectRevert(
            SimpleRewardZapper.SimpleRewardZapper__IsNotAuthorized.selector
        );
        simpleRewardZapper.removeAuthorizedOutputToken(_USDC_ADDRESS);
    }

    function test_removeAuthorizedRewardToken_success() public {
        simpleRewardZapper.addAuthorizedOutputToken(_USDC_ADDRESS);

        assertEq(simpleRewardZapper.authorizedOutputToken(_USDC_ADDRESS), 2);

        simpleRewardZapper.removeAuthorizedOutputToken(_USDC_ADDRESS);

        assertEq(simpleRewardZapper.authorizedOutputToken(_USDC_ADDRESS), 1);
    }
}
