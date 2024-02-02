// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { ITokenBridge } from "contracts/interfaces/external/wormhole/ITokenBridge.sol";

contract BridgeVeCVELockTest is TestBaseVeCVE {
    ITokenBridge public tokenBridge = ITokenBridge(_TOKEN_BRIDGE);

    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        centralRegistry.addChainSupport(
            address(this),
            address(protocolMessagingHub),
            address(cve),
            42161,
            1,
            1,
            23
        );

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(42161);
        wormholeChainIDs.push(23);

        centralRegistry.registerWormholeChainIDs(chainIDs, wormholeChainIDs);

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(30e18, false, rewardsData, "", 0);
    }

    function test_bridgeVeCVELock_fail_whenLockIndexExceeds(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.bridgeVeCVELock(1, 42161, true, rewardsData, "", 0);
    }

    function test_bridgeVeCVELock_fail_whenNativeTokenIsNotEnoughToCoverFee(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(23, false);

        vm.expectRevert();
        veCVE.bridgeVeCVELock{ value: messageFee - 1 }(
            1,
            42161,
            true,
            rewardsData,
            "",
            0
        );
    }

    function test_bridgeVeCVELock_success(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(23, false);

        centralRegistry.setEarlyUnlockPenaltyMultiplier(3000);

        uint256 veCVEBalance = veCVE.balanceOf(address(this));
        uint256 cveBalance = cve.balanceOf(address(this));
        uint256 cveTotalSupply = cve.totalSupply();

        veCVE.bridgeVeCVELock{ value: messageFee }(
            0,
            42161,
            true,
            rewardsData,
            "",
            0
        );

        assertEq(veCVE.balanceOf(address(this)), 0);
        assertEq(cve.balanceOf(address(this)), cveBalance);
        assertEq(cve.totalSupply(), cveTotalSupply - veCVEBalance);
    }
}
