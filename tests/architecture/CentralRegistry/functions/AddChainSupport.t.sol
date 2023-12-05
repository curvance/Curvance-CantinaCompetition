// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract AddChainSupportTest is TestBaseMarket {
    event NewChainAdded(uint256 chainId, address operatorAddress);

    function test_addChainSupport_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            23,
            1,
            1,
            42161
        );
        vm.stopPrank();
    }

    function test_addChainSupport_fail_whenChainOperatorAlreadyAdded() public {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            23,
            1,
            1,
            42161
        );
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            23,
            1,
            1,
            42161
        );
    }

    function test_addChainSupport_fail_whenChainAlreadyAdded() public {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            23,
            1,
            1,
            42161
        );
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.addChainSupport(
            user1,
            address(this),
            address(1),
            23,
            1,
            1,
            42161
        );
    }

    function test_addChainSupport_success() public {
        assertEq(centralRegistry.messagingToGETHChainId(42161), 0);
        assertEq(centralRegistry.GETHToMessagingChainId(23), 0);
        uint256 prevSupportedChains = centralRegistry.supportedChains();

        vm.expectEmit(true, true, true, true);
        emit NewChainAdded(23, user1);
        centralRegistry.addChainSupport(
            user1,
            address(this),
            address(1),
            23,
            1,
            1,
            42161
        );

        (
            uint256 isSupported,
            address messagingHub,
            uint256 asSourceAux,
            uint256 asDestinationAux,
            address cveAddress
        ) = centralRegistry.supportedChainData(23);
        assertEq(isSupported, 2);
        assertEq(messagingHub, address(this));
        assertEq(asSourceAux, 1);
        assertEq(asDestinationAux, 1);
        assertEq(cveAddress, address(1));

        (
            uint256 isAuthorized,
            uint256 chainId,
            uint256 messagingChainId,
            address cveAddress_
        ) = centralRegistry.omnichainOperators(user1, 23);
        assertEq(isAuthorized, 2);
        assertEq(chainId, 23);
        assertEq(messagingChainId, 42161);
        assertEq(cveAddress_, address(1));

        assertEq(centralRegistry.messagingToGETHChainId(42161), 23);
        assertEq(centralRegistry.GETHToMessagingChainId(23), 42161);
        assertEq(prevSupportedChains + 1, centralRegistry.supportedChains());
    }
}
