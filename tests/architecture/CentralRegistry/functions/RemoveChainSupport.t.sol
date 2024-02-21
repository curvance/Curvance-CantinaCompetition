// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

contract RemoveChainSupportTest is TestBaseMarket {
    using stdStorage for StdStorage;

    event RemovedChain(uint256 chainId, address operatorAddress);

    function setUp() public override {
        super.setUp();

        centralRegistry.addChainSupport(
            user1,
            address(this),
            address(1),
            42161,
            1,
            1,
            23
        );
    }

    function test_removeChainSupport_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.removeChainSupport(user1, 42161);
    }

    function test_removeChainSupport_fail_whenOperatorIsNotAuthorized()
        public
    {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.removeChainSupport(address(1), 42161);
    }

    function test_removeChainSupport_fail_whenChainIdIsNotAuthorized() public {
        stdstore
            .target(address(centralRegistry))
            .sig("supportedChainData(uint256)")
            .with_key(42161)
            .depth(0)
            .checked_write(1);

        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.removeChainSupport(user1, 42161);
    }

    function test_removeChainSupport_success() public {
        uint256 prevSupportedChains = centralRegistry.supportedChains();

        (
            uint256 isSupported,
            address messagingHub,
            uint256 asSourceAux,
            uint256 asDestinationAux,
            address cveAddress
        ) = centralRegistry.supportedChainData(42161);
        assertEq(isSupported, 2);
        assertEq(messagingHub, address(this));
        assertEq(asSourceAux, 1);
        assertEq(asDestinationAux, 1);
        assertEq(cveAddress, address(1));

        (
            uint256 isAuthorized,
            uint256 messagingChainId,
            address cveAddress_
        ) = centralRegistry.omnichainOperators(user1, 42161);
        assertEq(isAuthorized, 2);
        assertEq(messagingChainId, 23);
        assertEq(cveAddress_, address(1));

        assertEq(centralRegistry.messagingToGETHChainId(23), 42161);
        assertEq(centralRegistry.GETHToMessagingChainId(42161), 23);

        vm.expectEmit(true, true, true, true);
        emit RemovedChain(42161, user1);
        centralRegistry.removeChainSupport(user1, 42161);

        assertEq(centralRegistry.messagingToGETHChainId(42161), 0);
        assertEq(centralRegistry.GETHToMessagingChainId(23), 0);

        assertEq(prevSupportedChains - 1, centralRegistry.supportedChains());
    }
}
