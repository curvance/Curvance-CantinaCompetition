// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { DENOMINATOR } from "contracts/libraries/Constants.sol";

contract FuzzVECVE is StatefulBaseMarket {
    struct CreateLockData {
        bool continuousLock;
        RewardsData rewardsData;
        bytes param;
        uint256 aux;
    }
    CreateLockData defaultContinuous;
    uint256 numLocks;
    bool isAllContinuous;

    constructor() {
        defaultContinuous = CreateLockData(
            true,
            RewardsData(address(usdc), false, false, false),
            bytes(""),
            0
        );
    }

    function create_lock_when_not_shutdown(
        uint256 amount,
        bool continuousLock
    ) public {
        if (!continuousLock) {
            isAllContinuous = false;
        }
        require(veCVE.isShutdown() != 2);
        amount = clampBetween(amount, 1, type(uint32).max);
        // save balance of CVE
        uint256 preLockCVEBalance = cve.balanceOf(address(this));
        // save balance of VE_CVE
        uint256 preLockVECVEBalance = veCVE.balanceOf(address(this));

        approve_cve(
            amount,
            "VE_CVE - createLock call failed on cve token approval bound [1, type(uint32).max]"
        );

        try
            veCVE.createLock(
                amount,
                continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            uint256 postLockCVEBalance = cve.balanceOf(address(this));
            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VE_CVE - createLock CVE token transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(address(this));
            assertEq(
                preLockVECVEBalance + amount,
                postLockVECVEBalance,
                "VE_CVE - createLock VE_CVE token minted"
            );
            numLocks++;
        } catch (bytes memory reason) {
            assertWithMsg(
                false,
                "VE_CVE - createLock call failed unexpectedly"
            );
        }
    }

    function create_lock_with_zero_amount_should_fail() public {
        require(veCVE.isShutdown() != 2);
        uint256 amount = 0;

        approve_cve(
            amount,
            "VE_CVE - createLock call failed on cve token approval for ZERO"
        );

        try
            veCVE.createLock(
                amount,
                defaultContinuous.continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            // VE_CVE.createLock() with zero amount is expected to fail
            assertWithMsg(
                false,
                "VE_CVE - createLock should have failed for ZERO amount"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_invalidLockSelectorHash,
                "VE_CVE - createLock() should fail when creating with 0"
            );
        }
    }

    function extendLock_should_succeed_if_not_shutdown(
        uint256 seed,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(seed);

        (, uint256 preExtendLockTime) = get_associated_lock(
            address(this),
            lockIndex
        );
        emit LogUint256("preextended lock time", preExtendLockTime);
        require(preExtendLockTime > block.timestamp);
        require(preExtendLockTime != veCVE.CONTINUOUS_LOCK_VALUE());
        if (!continuousLock) {
            isAllContinuous = false;
        }

        try
            veCVE.extendLock(
                lockIndex,
                continuousLock,
                defaultContinuous.rewardsData,
                bytes(""),
                defaultContinuous.aux
            )
        {
            (, uint256 postExtendLockTime) = get_associated_lock(
                address(this),
                lockIndex
            );
            if (continuousLock) {
                assertWithMsg(
                    postExtendLockTime == veCVE.CONTINUOUS_LOCK_VALUE(),
                    "VE_CVE - extendLock() should set veCVE.userPoints(address(this))[index].unlockTime to CONTINUOUS"
                );
            } else {
                emit LogUint256(
                    "pre extend epoch",
                    veCVE.currentEpoch(preExtendLockTime)
                );
                emit LogUint256(
                    "post extend epoch",
                    veCVE.currentEpoch(postExtendLockTime)
                );
                emit LogUint256("preExtendLockTime", preExtendLockTime);
                emit LogUint256("postExtendLockTime", postExtendLockTime);
                if (
                    veCVE.currentEpoch(preExtendLockTime) ==
                    veCVE.currentEpoch(postExtendLockTime)
                ) {
                    assertEq(
                        preExtendLockTime,
                        postExtendLockTime,
                        "VE_CVE - extendLock() when extend is called in same epoch should be the same"
                    );
                } else {
                    assertGt(
                        postExtendLockTime,
                        preExtendLockTime,
                        "VE_CVE - extendLock() when called in later epoch should increase unlock time"
                    );
                }
            }
        } catch {}
    }

    function extend_lock_should_fail_if_already_continuous(
        uint256 seed,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(seed);
        (, uint256 unlockTime) = get_associated_lock(address(this), lockIndex);

        require(unlockTime == veCVE.CONTINUOUS_LOCK_VALUE());

        try
            veCVE.extendLock(
                lockIndex,
                continuousLock,
                RewardsData(address(0), true, true, true),
                bytes(""),
                0
            )
        {
            // VECVE.extendLock() is expected to fail if a lock is already continuous
            assertWithMsg(
                false,
                "VE_CVE - extendLock() should not be successful"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_lockTypeMismatchHash,
                "VE_CVE - extendLock() failed unexpectedly"
            );
        }
    }

    function extend_lock_should_fail_if_shutdown(
        uint256 lockIndex,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() == 2);

        try
            veCVE.extendLock(
                lockIndex,
                continuousLock,
                RewardsData(address(0), true, true, true),
                bytes(""),
                0
            )
        {
            // VECVE.extendLock() should fail if the system is shut down
            assertWithMsg(
                false,
                "VE_CVE - extendLock() should not be successful"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_shutdownSelectorHash,
                "VE_CVE - extendLock() failed unexpectedly"
            );
        }
    }

    function increaseAmountAndExtendLock_should_succeed_if_continuous(
        uint256 amount,
        uint256 number
    ) public {
        bool continuousLock = true;
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(number);

        amount = clampBetween(amount, 1, type(uint32).max);
        (, uint256 unlockTime) = get_associated_lock(address(this), lockIndex);
        require(unlockTime == veCVE.CONTINUOUS_LOCK_VALUE());
        // save balance of CVE
        uint256 preLockCVEBalance = cve.balanceOf(address(this));
        // save balance of VE_CVE
        uint256 preLockVECVEBalance = veCVE.balanceOf(address(this));

        approve_cve(
            amount,
            "VE_CVE - increaseAmountAndExtendLock() failed on approve cve"
        );

        try
            veCVE.increaseAmountAndExtendLock(
                amount,
                lockIndex,
                continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            uint256 postLockCVEBalance = cve.balanceOf(address(this));
            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VE_CVE - increaseAmountAndExtendLock CVE transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(address(this));
            assertEq(
                preLockVECVEBalance + amount,
                postLockVECVEBalance,
                "VE_CVE - increaseAmountAndExtendLock VE_CVE token minted"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - increaseAmountAndExtendLock() failed unexpectedly"
            );
        }
    }

    function increaseAmountAndExtendLock_should_succeed_if_non_continuous(
        uint256 amount,
        uint256 number
    ) public {
        bool continuousLock = false;
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(number);
        isAllContinuous = false;

        amount = clampBetween(amount, 1, type(uint32).max);
        (, uint256 unlockTime) = get_associated_lock(address(this), lockIndex);
        require(unlockTime >= block.timestamp);
        // save balance of CVE
        uint256 preLockCVEBalance = cve.balanceOf(address(this));
        // save balance of VE_CVE
        uint256 preLockVECVEBalance = veCVE.balanceOf(address(this));

        approve_cve(
            amount,
            "VE_CVE - increaseAmountAndExtendLock() failed on approve cve"
        );

        try
            veCVE.increaseAmountAndExtendLock(
                amount,
                lockIndex,
                continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            uint256 postLockCVEBalance = cve.balanceOf(address(this));
            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VE_CVE - increaseAmountAndExtendLock CVE transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(address(this));
            assertEq(
                preLockVECVEBalance + amount,
                postLockVECVEBalance,
                "VE_CVE - increaseAmountAndExtendLock VE_CVE token minted"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - increaseAmountAndExtendLock() failed unexpectedly"
            );
        }
    }

    function combineAllLocks_should_succeed(bool continuous) public {
        require(numLocks >= 2);
        uint256 lockIndex = 0;

        uint256 newLockAmount = 0;
        bool isCurrentListAllContinuous = true;
        uint256 userPointsAdjustmentForContinuous;
        uint256 preCombineUserPoints = veCVE.userPoints(address(this));

        for (uint i = 0; i < numLocks; i++) {
            (uint216 amount, uint40 unlockTime) = veCVE.userLocks(
                address(this),
                i
            );
            emit LogUint256("amount added", amount);
            newLockAmount += amount;

            if (unlockTime != veCVE.CONTINUOUS_LOCK_VALUE()) {
                isCurrentListAllContinuous = false;
            } else {
                userPointsAdjustmentForContinuous +=
                    (amount * veCVE.clPointMultiplier()) /
                    DENOMINATOR -
                    amount;
            }

            emit LogUint256("current new lock amount", newLockAmount);
        }

        try
            veCVE.combineAllLocks(
                continuous,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            numLocks = 1;
            // userLocks.amount must sum to the individual amounts for each lock
            (uint216 combinedAmount, uint40 combinedUnlockTime) = veCVE
                .userLocks(address(this), 0);

            assertEq(
                combinedAmount,
                newLockAmount,
                "VE_CVE - combineAllLocks() expected amount sum of new lock to equal calculated"
            );
            uint256 postCombineUserPoints = veCVE.userPoints(address(this));
            if (isCurrentListAllContinuous) {
                // If the existing locks that the user had were all continuous
                if (continuous) {
                    // And a user wants to convert it to a single continuous lock
                    // Ensure that the user points before and after the combine are identical
                    assertEq(
                        preCombineUserPoints,
                        postCombineUserPoints,
                        "VE_CVE - combineAllLocks() - if all locks prior continuous => combine into continuous failed"
                    );
                } else {
                    // A user wants to convert it into a non-continuous lock
                    assertEq( // Ensure that the previous all-combined user points - merged points is equivalent to the-
                        preCombineUserPoints -
                            userPointsAdjustmentForContinuous,
                        postCombineUserPoints,
                        "VE_CVE - combineAllLocks() - if all locks prior continuous => combine into !continuous failed"
                    );
                }
            } else {}
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - combineAllLocks() failed unexpectedly with correct preconditions"
            );
        }
    }

    function processExpiredLock_should_succeed(uint256 seed) public {
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(seed);
        try
            veCVE.processExpiredLock(
                lockIndex,
                false,
                defaultContinuous.continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {} catch {}
    }

    function processExpiredLock_should_fail_if_lock_index_exceeds_length(
        uint256 seed
    ) public {
        uint256 lockIndex = clampBetween(seed, numLocks, type(uint256).max);
        try
            veCVE.processExpiredLock(
                lockIndex,
                false,
                defaultContinuous.continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {} catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_invalidLockSelectorHash,
                "VE_CVE - createLock() should fail when creating with 0"
            );
        }
    }

    // function processExpiredLock_should_fail_

    function disableContinuousLock_should_succeed_if_lock_exists(
        uint256 number
    ) public {
        uint256 lockIndex = get_existing_lock(number);
        // require(
        //     veCVE.locks(lockIndex).unlockTime == veCVE.CONTINUOUS_LOCK_VALUE()
        // );

        try
            veCVE.disableContinuousLock(
                lockIndex,
                defaultContinuous.rewardsData,
                bytes(""),
                0
            )
        {} catch {}
    }

    function shutdown_success_if_elevated_permission() public {
        // should be true on setup unless revoked
        require(centralRegistry.hasElevatedPermissions(address(this)));
        // should not be shut down already
        require(veCVE.isShutdown() != 2);
        emit LogAddress("msg.sender from call", address(this));
        // call central registry from addr(this)
        try veCVE.shutdown() {
            assertWithMsg(
                veCVE.isShutdown() == 2,
                "VE_CVE - shutdown() did not set isShutdown variable"
            );
            assertWithMsg(
                cveLocker.isShutdown() == 2,
                "VE_CVE - shutdown() should also set cveLocker"
            );
        } catch (bytes memory reason) {
            uint256 errorSelector = extractErrorSelector(reason);

            assertWithMsg(
                errorSelector == vecve_unauthorizedSelectorHash,
                "VE_CVE - shutdown() by elevated permission failed unexpectedly"
            );
        }
    }

    function earlyExpireLock_shoud_succeed(uint256 seed) public {
        uint256 lockIndex = get_existing_lock(seed);

        try
            veCVE.earlyExpireLock(
                lockIndex,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {} catch {}
    }

    // Getter functions

    function getVotesForEpoch_correct_calculation(uint256 epoch) public {
        uint256 votesForEpoch = veCVE.getVotesForEpoch(address(this), epoch);
    }

    function getVotesForSingleLockForTime_correct_calculation(
        uint256 number,
        uint256 time,
        uint256 currentLockBoost
    ) public {
        address user = address(this);
        uint256 lockIndex = get_existing_lock(number);

        uint256 votes = veCVE.getVotesForSingleLockForTime(
            user,
            lockIndex,
            time,
            currentLockBoost
        );
    }

    function getUnlockPenalty_correct_calculation(uint256 number) public {
        address user = address(this);
        uint256 lockIndex = get_existing_lock(number);

        uint256 unlockPenalty = veCVE.getUnlockPenalty(user, lockIndex);
    }

    function getVotes_correct_calculation(address user) public {
        uint256 votes = veCVE.getVotes(user);
    }

    // Helper Functions

    function get_associated_lock(
        address addr,
        uint256 lockIndex
    ) private returns (uint216, uint40) {
        (uint216 amount, uint40 unlockTime) = veCVE.userLocks(addr, lockIndex);
    }

    function get_existing_lock(uint256 seed) private returns (uint256) {
        if (numLocks == 0) {
            create_lock_when_not_shutdown(seed, true);
            return 0;
        }
        return clampBetween(seed, 0, numLocks);
    }

    function approve_cve(uint256 amount, string memory error) private {
        try cve.approve(address(veCVE), amount) {} catch {
            assertWithMsg(false, error);
        }
    }
}
