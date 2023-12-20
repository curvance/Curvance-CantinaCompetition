// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { DENOMINATOR, WAD } from "contracts/libraries/Constants.sol";

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
        amount = clampBetween(amount, WAD, type(uint64).max);
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

    function create_lock_with_less_than_wad_should_fail(
        uint256 amount
    ) public {
        require(veCVE.isShutdown() != 2);
        amount = clampBetween(amount, 1, WAD - 1);

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
<<<<<<< HEAD
            // VE_CVE.createLock() with zero amount is expected to fail
=======
>>>>>>> e1e615a5 (Increased hit coverage on VeCVE to 67%)
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

    function extend_lock_should_fail_if_continuous(
        uint256 seed,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(seed);

        require(
            veCVE.getUnlockTime(address(this), lockIndex) ==
                veCVE.CONTINUOUS_LOCK_VALUE()
        );

        try
            veCVE.extendLock(
                lockIndex,
                continuousLock,
                RewardsData(address(0), true, true, true),
                bytes(""),
                0
            )
        {
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

<<<<<<< HEAD
    function increaseAmountAndExtendLock_should_succeed_if_continuous(
        uint256 amount,
        uint256 number
    ) public {
        bool continuousLock = true;
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(number);

        amount = clampBetween(amount, WAD, type(uint32).max);
        (, uint256 unlockTime) = get_associated_lock(address(this), lockIndex);
        require(unlockTime == veCVE.CONTINUOUS_LOCK_VALUE());
        // save balance of CVE
        uint256 preLockCVEBalance = cve.balanceOf(address(this));
        // save balance of VE_CVE
        uint256 preLockVECVEBalance = veCVE.balanceOf(address(this));
=======
    function increaseAmountAndExtendLock_should_succeed(
        uint256 amount,
        uint256 number
    ) public {
        uint256 lockIndex = get_existing_lock(number);
        amount = clampBetween(amount, 1, type(uint32).max);
>>>>>>> e1e615a5 (Increased hit coverage on VeCVE to 67%)

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

        amount = clampBetween(amount, WAD, type(uint32).max);
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

    function combineAllLocks_for_all_continuous_to_continuous_terminal_should_succeed()
        public
    {
        bool continuous = true;
        require(numLocks >= 2);
        uint256 lockIndex = 0;

        uint256 preCombineUserPoints = veCVE.userPoints(address(this));
        (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        ) = get_all_user_lock_info(address(this));
        require(numberOfExistingContinuousLocks == numLocks);

        try
            veCVE.combineAllLocks(
                continuous,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            // userLocks.amount must sum to the individual amounts for each lock
            (uint216 combinedAmount, uint40 combinedUnlockTime) = veCVE
                .userLocks(address(this), 0);

            uint256 postCombineUserPoints = veCVE.userPoints(address(this));
            // If the existing locks that the user had were all continuous

            // And a user wants to convert it to a single continuous lock
            // Ensure that the user points before and after the combine are identical
            // [continuous, continuous] => continuous terminal; preCombine == postCombine
            assertEq(
                preCombineUserPoints,
                postCombineUserPoints,
                "VE_CVE - combineAllLocks() - user points should be same for all prior continuous => continuous failed"
            );

            emit LogUint256(
                "post combine user points:",
                (postCombineUserPoints * veCVE.CL_POINT_MULTIPLIER())
            );
            assertGte(
                postCombineUserPoints,
                (
                    (veCVE.balanceOf(address(this)) *
                        veCVE.CL_POINT_MULTIPLIER())
                ) / WAD,
                "VE_CVE - combineALlLocks() veCVE balance = userPoints * multiplier/DENOMINATOR failed for all continuous => continuous"
            );
            assert_continuous_locks_has_no_user_or_chain_unlocks(
                combinedUnlockTime
            );
            numLocks = 1;
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - combineAllLocks() failed unexpectedly with correct preconditions"
            );
        }
    }

    function combineAllLocks_non_continuous_to_continuous_terminals_should_succeed()
        public
    {
        bool continuous = true;
        require(numLocks >= 2);
        save_epoch_unlock_values();

        uint256 preCombineUserPoints = veCVE.userPoints(address(this));

        (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        ) = get_all_user_lock_info(address(this));
        require(numberOfExistingContinuousLocks < numLocks);

        try
            veCVE.combineAllLocks(
                continuous,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            // userLocks.amount must sum to the individual amounts for each lock
            (uint216 combinedAmount, uint40 combinedUnlockTime) = veCVE
                .userLocks(address(this), 0);

            assertEq(
                combinedAmount,
                newLockAmount,
                "VE_CVE - combineAllLocks() expected amount sum of new lock to equal calculated"
            );
            uint256 postCombineUserPoints = veCVE.userPoints(address(this));
            // If the existing locks that the user had were all continuous
            // [some continuous locks] -> continuous terminal; preCombine < postCombine
            assertLt(
                preCombineUserPoints,
                postCombineUserPoints,
                "VE_CVE - combineAllLocks() - some or no prior continuous => continuous failed"
            );
            assertGte(
                postCombineUserPoints,
                (
                    (veCVE.balanceOf(address(this)) *
                        veCVE.CL_POINT_MULTIPLIER())
                ) / WAD,
                "VE_CVE - combineALlLocks() veCVE balance = userPoints * multiplier/DENOMINATOR failed for all continuous => continuous"
            );
            // for each existing lock
            // ensure that the post user unlock value for that epoch is < pre user unlock
            // ensure that the post chain unlock for epoch < pre chain unlock
            for (uint i = 0; i < individualEpochs.length; i++) {
                uint256 unlockEpoch = individualEpochs[i];
                assertGt(
                    epochBalances[unlockEpoch].userUnlocksByEpoch,
                    veCVE.userUnlocksByEpoch(address(this), unlockEpoch),
                    "VE_CVE - pre userUnlockByEpoch must exceed post userUnlockByEpoch after noncontinuous -> continuous terminal"
                );
                assertGt(
                    epochBalances[unlockEpoch].chainUnlocksByEpoch,
                    veCVE.chainUnlocksByEpoch(unlockEpoch),
                    "VE_CVE - pre- chainUnlockByEpoch must exceed post chainUnlockByEpoch after noncontinuous -> continuous terminal"
                );
            }
            assert_continuous_locks_has_no_user_or_chain_unlocks(
                combinedUnlockTime
            );
            numLocks = 1;
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - combineAllLocks() failed unexpectedly with correct preconditions"
            );
        }
    }

    function combineAllLocks_should_succeed_to_non_continuous_terminal()
        public
    {
        bool continuous = false;
        require(numLocks >= 2);

        uint256 preCombineUserPoints = veCVE.userPoints(address(this));
        (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        ) = get_all_user_lock_info(address(this));

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

            if (numberOfExistingContinuousLocks > 0) {
                // // [some continuous] -> non-continuous terminal
                assertGt(
                    preCombineUserPoints,
                    postCombineUserPoints,
                    "VE_CVE - combineAllLocks() - ALL continuous => !continuous failed"
                );
            }
            // no locks prior were continuous
            else {
                assertEq(
                    preCombineUserPoints,
                    postCombineUserPoints,
                    "VE_CVE - combineAllLocks() NO continuous locks -> !continuous failed"
                );
            }
            assertEq(
                veCVE.balanceOf(address(this)),
                postCombineUserPoints,
                "VE_CVE - combineAllLocks() balance should equal post combine user points"
            );

            //
            // balance veCVE = userPoints for continuous
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

    // Stateful

    // precondition: userlock is non-continuous
    // for each user lock, amount += lock.amount
    // assert(veCVE.balanceOf(this)== lock.amount)

    function balance_must_equal_lock_amount_for_non_continuous() public {
        (
            uint256 lockAmountSum,
            uint256 numberOfExistingContinuousLocks
        ) = get_all_user_lock_info(address(this));
        require(numberOfExistingContinuousLocks != numLocks);
        assertEq(
            veCVE.balanceOf(address(this)),
            lockAmountSum,
            "VE_CVE - balance = lock.amount for all non-continuous objects"
        );
    }

    function user_unlock_for_epoch_for_continuous_locks_should_be_zero()
        public
    {
        (
            uint256 lockAmountSum,
            uint256 numberOfExistingContinuousLocks
        ) = get_all_user_lock_info(address(this));
        require(numberOfExistingContinuousLocks == numLocks);
        for (uint i = 0; i < individualEpochs.length; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            assertEq(
                veCVE.userUnlocksByEpoch(address(this), epoch),
                0,
                "VE_CVE - user_unlock_for_epoch_for_continuous_locks_should_be_zero"
            );
        }
    }

    function chain_unlock_for_epoch_for_continuous_locks_should_be_zero()
        public
    {
        (
            uint256 lockAmountSum,
            uint256 numberOfExistingContinuousLocks
        ) = get_all_user_lock_info(address(this));
        require(numberOfExistingContinuousLocks == numLocks);
        for (uint i = 0; i < individualEpochs.length; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            assertEq(
                veCVE.chainUnlocksByEpoch(epoch),
                0,
                "VE_CVE - combineAllLocks - chain_unlock_for_epoch_for_continuous_locks_should_be_zero"
            );
        }
    }

    function assert_continuous_locks_has_no_user_or_chain_unlocks(
        uint256 combinedUnlockTime
    ) private {
        uint256 epoch = veCVE.currentEpoch(combinedUnlockTime);

        assertEq(
            veCVE.chainUnlocksByEpoch(epoch),
            0,
            "VE_CVE - combineAllLocks - chain unlocks by epoch should be zero for continuous terminal"
        );
        assertEq(
            veCVE.userUnlocksByEpoch(address(this), epoch),
            0,
            "VE_CVE - combineAllLocks - user unlocks by epoch should be zero for continuous terminal"
        );
    }

    // Helper Functions
    uint256[] individualEpochs;
    mapping(uint256 => CombineBalance) epochBalances;
    struct CombineBalance {
        uint256 chainUnlocksByEpoch;
        uint256 userUnlocksByEpoch;
    }

    function save_epoch_unlock_values() private {
        for (uint i = 0; i < numLocks; i++) {
            (uint216 amount, uint40 unlockTime) = veCVE.userLocks(
                address(this),
                i
            );
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            individualEpochs.push(epoch);
            epochBalances[epoch].chainUnlocksByEpoch += veCVE
                .chainUnlocksByEpoch(epoch);
            epochBalances[epoch].userUnlocksByEpoch += veCVE
                .userUnlocksByEpoch(address(this), epoch);
        }
    }

    function get_all_user_lock_info(
        address addr
    )
        private
        view
        returns (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        )
    {
        for (uint i = 0; i < numLocks; i++) {
            (uint216 amount, uint40 unlockTime) = veCVE.userLocks(
                address(this),
                i
            );
            newLockAmount += amount;

            if (unlockTime == veCVE.CONTINUOUS_LOCK_VALUE()) {
                numberOfExistingContinuousLocks++;
            }
        }
    }

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
