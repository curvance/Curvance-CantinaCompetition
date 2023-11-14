// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseChildCVE } from "../TestBaseChildCVE.sol";
import { CVE } from "contracts/token/ChildCVE.sol";
import { ICommonOFT } from "contracts/layerzero/ICommonOFT.sol";

contract SendAndCallTest is TestBaseChildCVE {
    function test_sendAndCall_fail_whenUnauthorized() public {
        ICommonOFT.LzCallParams memory callParams = ICommonOFT.LzCallParams({
            refundAddress: payable(user1),
            zroPaymentAddress: address(0),
            adapterParams: bytes("")
        });

        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        childCVE.sendAndCall(
            user1,
            1,
            bytes32(uint256(uint160(user2)) << 96),
            1000,
            "",
            10_000,
            callParams
        );
    }

    function test_sendAndCall_success() public {
        ICommonOFT.LzCallParams memory callParams = ICommonOFT.LzCallParams({
            refundAddress: payable(user1),
            zroPaymentAddress: address(0),
            adapterParams: bytes("")
        });

        address messagingHub = centralRegistry.protocolMessagingHub();

        deal(address(childCVE), user1, 1000);
        vm.prank(user1);
        childCVE.approve(messagingHub, type(uint256).max);

        vm.startPrank(messagingHub);
        vm.expectRevert("LzApp: destination chain is not a trusted source");
        childCVE.sendAndCall(
            user1,
            1,
            bytes32(uint256(uint160(user2)) << 96),
            1000,
            "",
            10_000,
            callParams
        );
        vm.stopPrank();
    }
}
