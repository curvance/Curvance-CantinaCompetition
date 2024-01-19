// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBaseVeCVE} from "../TestBaseVeCVE.sol";
import {VeCVE} from "contracts/token/VeCVE.sol";

contract VotesTest is TestBaseVeCVE {
    function test_getVotes_zero() public {
        assertEq(veCVE.getVotes(address(this)), 0);
    }

    function test_getVotes_zero_whenLockIsExpired(uint256 amount) public {
        amount = bound(amount, _MIN_FUZZ_AMOUNT, _MAX_FUZZ_AMOUNT);
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);

        veCVE.createLock(amount, false, rewardsData, "", 0);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime * 2);
        assertEq(veCVE.getVotes(address(this)), 0);
    }

    function test_getVotes_continous_lock_withBoost(uint256 amount, uint16 boost) public {
        uint256 denominator = 1e4;
        amount = bound(amount, _MIN_FUZZ_AMOUNT, _MAX_FUZZ_AMOUNT);
        boost = uint16(bound(boost, denominator, type(uint16).max));
        centralRegistry.setVoteBoostMultiplier(boost);
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);

        veCVE.createLock(amount, true, rewardsData, "", 0);
        vm.warp(1000);

        // current boost is x2
        assertEq(veCVE.getVotes(address(this)), (amount * boost) / denominator);
    }

    function test_getVotes_after_lock(uint256 amount, uint16 timeWarp) public {
        amount = bound(amount, _MIN_FUZZ_AMOUNT, _MAX_FUZZ_AMOUNT);
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);

        veCVE.createLock(amount, false, rewardsData, "", 0);
        vm.warp(timeWarp);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        if (block.timestamp > unlockTime) {
            assertEq(veCVE.getVotes(address(this)), 0);
            return;
        }
        uint256 epoch = (unlockTime - block.timestamp) / veCVE.EPOCH_DURATION();
        uint256 votes = (amount * epoch) / veCVE.LOCK_DURATION_EPOCHS();

        assertEq(veCVE.getVotes(address(this)), votes);
    }
}
