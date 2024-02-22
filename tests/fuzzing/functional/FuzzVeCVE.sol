// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { DENOMINATOR, WAD } from "contracts/libraries/Constants.sol";

contract FuzzVeCVE is StatefulBaseMarket {
    RewardsData defaultRewardData;
    // uint256.max to represent no locks existing
    uint256 NO_LOCKS = type(uint256).max;
    // caller address set to address(this) for execution
    address caller;

    constructor() {
        caller = address(this);
        defaultRewardData = RewardsData(false, false, false, false);
        // seeds the execution with creating a lock
        create_lock_when_not_shutdown(uint(0), false);
    }

    /// @custom:property  vecve-1 - Creating a lock with a specified amount when the system is not in a shutdown state should succeed, with preLockCVEBalance matching postLockCVEBalance + amount and preLockVECVEBalance + amount matching postLockVECVEBalance.
    /// @custom:property vecve-X - Creating a lock with the correct preconditions should fail
    /// @custom:precondition  veCVE contract must not be shut down
    /// @custom:precondition  amount clamped between [WAD, uint64.max]
    /// @custom:precondition  CVE token must approve VeCVE token contract
    /// @custom:limitations this fuzzing function only tests bounds of WAD-uint64.max, and is missing upper bounds
    function create_lock_when_not_shutdown(
        uint256 amount,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() != 2);
        amount = clampBetween(amount, WAD, type(uint64).max);
        uint256 preLockCVEBalance = cve.balanceOf(caller);
        uint256 preLockVECVEBalance = veCVE.balanceOf(caller);

        _approve_cve_tokens(
            amount,
            "VE_CVE - createLock call failed on cve token approval bound [1, type(uint32).max]"
        );

        try
            veCVE.createLock(
                amount,
                continuousLock,
                RewardsData(false, false, false, false),
                bytes(""),
                0
            )
        {
            uint256 postLockCVEBalance = cve.balanceOf(caller);
            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VECVE-1 - CVE token transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(caller);
            assertEq(
                preLockVECVEBalance + amount,
                postLockVECVEBalance,
                "VECVE-1 - createLock VE_CVE token minted"
            );
        } catch {
            assertWithMsg(
                false,
                "VECVE-X - createLock call failed unexpectedly"
            );
        }
    }

    /// @custom:property  vecve-2 – Creating a lock with an amount less than WAD should fail and revert with an error message indicating invalid lock amount.
    /// @custom:precondition  VeCVE contract is not shut down
    /// @custom:precondition  amount is clamped between [1, WAD-1]
    /// @custom:precondition  VeCVE contract is approved for CVE
    function create_lock_with_less_than_wad_should_fail(
        uint256 amount
    ) public {
        require(veCVE.isShutdown() != 2);
        // between 1-(wad-1) is considered 'illegal'
        amount = clampBetween(amount, 1, WAD - 1);

        _approve_cve_tokens(
            amount,
            "VECVE - createLock call failed on cve token approval for ZERO"
        );

        try veCVE.createLock(amount, true, defaultRewardData, bytes(""), 0) {
            // VE_CVE.createLock() with zero amount is expected to fail
            assertWithMsg(
                false,
                "VECVE-2 - createLock should have failed for any amount between 1 to WAD-1"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_invalidLockSelectorHash,
                "VECVE-2 - createLock() should fail when creating with 0"
            );
        }
    }

    ///@custom:property  vecve-3 – Creating a lock with zero amount should fail and revert with an error message indicating an invalid lock amount.
    /// @custom:precondition  VeCVE contract is not shut down
    /// @custom:precondition  amount is 0
    /// @custom:precondition  VeCVE contract is approved for CVE
    function create_lock_with_zero_amount_should_fail() public {
        require(veCVE.isShutdown() != 2);
        uint256 amount = 0;

        _approve_cve_tokens(
            amount,
            "VECVE - createLock call failed on cve token approval for ZERO"
        );

        try veCVE.createLock(amount, true, defaultRewardData, bytes(""), 0) {
            // VE_CVE.createLock() with zero amount is expected to fail
            assertWithMsg(
                false,
                "VECVE-3 - createLock should have failed for ZERO amount"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_invalidLockSelectorHash,
                "VECVE-3 - createLock() should fail when creating with 0"
            );
        }
    }

    /// @custom:property vecve-4 – Combining all continuous locks into a single continuous lock should result in identical user points before and after the operation.
    /// @custom:property vecve-5 – Combining all continuous locks into a single continuous lock should result in an increase in user points being greater than veCVE balance * MULTIPLIER / WAD.
    /// @custom:property vecve-6 – Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.
    /// @custom:property vecve-7 – Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.
    /// @custom:precondition  User must have more than 2 locks created
    /// @custom:precondition  All previous locks must be continuous
    /// @custom:precondition vecVE contract is not shut down
    function combineAllLocks_for_all_continuous_to_continuous_terminal_should_succeed()
        public
    {
        require(veCVE.isShutdown() != 2);
        bool continuous = true;
        require(_get_locks_length() >= 2);

        uint256 preCombineUserPoints = veCVE.userPoints(caller);
        (
            ,
            uint256 numberOfExistingContinuousLocks
        ) = _get_sum_and_count_continuous_locks(caller);
        require(numberOfExistingContinuousLocks == _get_locks_length());

        try
            veCVE.combineAllLocks(continuous, defaultRewardData, bytes(""), 0)
        {
            // userLocks.amount must sum to the individual amounts for each lock
            (, uint40 combinedUnlockTime) = _get_user_locks_info(caller, 0);

            uint256 postCombineUserPoints = veCVE.userPoints(caller);
            // If the existing locks that the user had were all continuous

            // And a user wants to convert it to a single continuous lock
            // Ensure that the user points before and after the combine are identical
            // [continuous, continuous] => continuous terminal; preCombine == postCombine
            assertEq(
                preCombineUserPoints,
                postCombineUserPoints,
                "VECVE-4 - combineAllLocks() - user points should be same for all prior continuous => continuous failed"
            );

            assertGte(
                postCombineUserPoints,
                ((veCVE.balanceOf(caller) * veCVE.CL_POINT_MULTIPLIER())) /
                    WAD,
                "VECVE-5 - combineALlLocks() veCVE balance = userPoints * multiplier/DENOMINATOR failed for all continuous => continuous"
            );
            _check_continuous_lock_has_no_user_or_chain_points(
                combinedUnlockTime,
                "VECVE-6 - combineAllLocks() chainUnlocksByEpoch should be zero for continuous terminal",
                "VECVE-7 - combineAllLocks()  userUnlocksByEpoch should be zero for continuous terminal"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - combineAllLocks() failed unexpectedly with correct preconditions"
            );
        }
    }

    /// @custom:property vecve-8 – Combining all non-continuous locks into a single non-continuous lock should result in the combined lock amount matching the sum of original lock amounts.
    /// @custom:property vecve-9 – Combining all continuous locks into a single continuous lock should result in resulting user points times the CL_POINT_MULTIPLIER being greater than or equal to the balance of veCVE.
    /// @custom:property vecve-10 – Combining non-continuous locks into continuous lock terminals should result in increased post combine user points compared to the pre combine user points.
    /// @custom:property vecve-11 – Combining non-continuous locks into continuous lock terminals should result in the userUnlockByEpoch value decreasing for each respective epoch.
    /// @custom:property vecve-12 – Combining non-continuous locks into continuous lock terminals should result in chainUnlockByEpoch decreasing for each respective epoch.
    /// @custom:property vecve-13 – Combining non-continuous locks to continuous locks should result in chainUnlockByEpochs being equal to 0.
    /// @custom:property vecve-14 – Combining non-continuous locks to continuous locks should result in the userUnlocksByEpoch being equal to 0.
    /// @custom:precondition  user must have more than 2 existing locks
    /// @custom:precondition  some of the pre-existing locks must be non-cntinuous
    /// @custom:precondition veCVE contract is not shut down
    function combineAllLocks_non_continuous_to_continuous_terminals_should_succeed()
        public
    {
        require(veCVE.isShutdown() != 2);
        bool continuous = true;
        require(_get_locks_length() >= 2);
        _save_epoch_unlock_values();

        uint256 preCombineUserPoints = veCVE.userPoints(caller);

        (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        ) = _get_sum_and_count_continuous_locks(caller);
        require(numberOfExistingContinuousLocks < _get_locks_length());

        try
            veCVE.combineAllLocks(continuous, defaultRewardData, bytes(""), 0)
        {
            (
                uint216 combinedAmount,
                uint40 combinedUnlockTime
            ) = _get_user_locks_info(caller, 0);

            // vecve-8
            assertEq(
                combinedAmount,
                newLockAmount,
                "VECVE-8 - combineAllLocks() expected amount sum of new lock to equal calculated"
            );
            uint256 postCombineUserPoints = veCVE.userPoints(caller);
            // vecve-9
            assertLt(
                preCombineUserPoints,
                postCombineUserPoints,
                "VECVE-9 - combineAllLocks() - some or no prior continuous => continuous failed"
            );
            // vecve-10
            assertGte(
                postCombineUserPoints,
                ((veCVE.balanceOf(caller) * veCVE.CL_POINT_MULTIPLIER())) /
                    WAD,
                "VECVE-10 - combineALlLocks() veCVE balance = userPoints * multiplier/DENOMINATOR failed for all continuous => continuous"
            );
            // for each existing lock's unique epoch
            for (uint i = 0; i < uniqueEpochs.length; i++) {
                uint256 unlockEpoch = uniqueEpochs[i];
                // vecve-11
                assertGte(
                    epochBalances[unlockEpoch].userUnlocksByEpoch,
                    veCVE.userUnlocksByEpoch(caller, unlockEpoch),
                    "VECVE-11 - pre userUnlockByEpoch must exceed post userUnlockByEpoch after noncontinuous -> continuous terminal"
                );
                // vecve-12
                assertGte(
                    epochBalances[unlockEpoch].chainUnlocksByEpoch,
                    veCVE.chainUnlocksByEpoch(unlockEpoch),
                    "VECVE-12 - pre- chainUnlockByEpoch must exceed post chainUnlockByEpoch after noncontinuous -> continuous terminal"
                );
            }
            // vecve-13, vecve-14
            _check_continuous_lock_has_no_user_or_chain_points(
                combinedUnlockTime,
                "VECVE-13 - combineAllLocks() chainUnlocksByEpoch should be zero for continuous terminal",
                "VECVE-14 - combineAllLocks() userUnlocksByEpoch should be zero for continuous terminal"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - combineAllLocks() failed unexpectedly with correct preconditions"
            );
        }
    }

    /// @custom:property vecve-15– Combining any locks to a non continuous terminal should result in the amount for the combined terminal matching the sum of original lock amounts.
    /// @custom:property vecve-16 – Combining some continuous locks to a non continuous terminal should result in user points decreasing.
    /// @custom:property vecve-17 – Combining no prior continuous locks to a non continuous terminal should result in no change in user points.
    /// @custom:property vecve-18 – Combining some prior continuous locks to a non continuous terminal should result in the veCVE balance of a user equaling the user points.
    /// @custom:precondition  User must have at least 2 existing locks
    /// @custom:precondition veCVE contract is not shut down
    function combineAllLocks_should_succeed_to_non_continuous_terminal()
        public
    {
        bool continuous = false;
        require(veCVE.isShutdown() != 2);
        require(_get_locks_length() >= 2);
        _save_epoch_unlock_values();

        uint256 preCombineUserPoints = veCVE.userPoints(caller);
        (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        ) = _get_sum_and_count_continuous_locks(caller);

        try
            veCVE.combineAllLocks(continuous, defaultRewardData, bytes(""), 0)
        {
            // userLocks.amount must sum to the individual amounts for each lock
            (uint216 combinedAmount, ) = _get_user_locks_info(caller, 0);

            // vecve-15
            assertEq(
                combinedAmount,
                newLockAmount,
                "VECVE-15 - combineAllLocks() expected amount sum of new lock to equal calculated"
            );
            uint256 postCombineUserPoints = veCVE.userPoints(caller);

            if (numberOfExistingContinuousLocks > 0) {
                // vecve-16
                assertGt(
                    preCombineUserPoints,
                    postCombineUserPoints,
                    "VECVE-16 - combineAllLocks() - ALL continuous => !continuous failed"
                );
            }
            // no locks prior were continuous
            else {
                // CAN ADD: Post-condition check on the epoch balances
                // vecve-17
                assertEq(
                    preCombineUserPoints,
                    postCombineUserPoints,
                    "VECVE-17 - combineAllLocks() NO continuous locks -> !continuous failed"
                );
            }
            //VECVE-18
            assertEq(
                veCVE.balanceOf(caller),
                postCombineUserPoints,
                "VE_CVE-18 - combineAllLocks() balance should equal post combine user points"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - combineAllLocks() failed unexpectedly with correct preconditions"
            );
        }
    }

    /// @custom:property VECVE-56 combineAllLocks should revert when system is shut down
    /// @custom:precondition vecve is shut down
    /// @custom:preconditio user has more than 2 locks
    function combineAllLocks_called_when_shutdown_should_revert() public {
        bool continuous = true;
        require(_get_locks_length() >= 2);
        require(veCVE.isShutdown() == 2);
        try
            veCVE.combineAllLocks(continuous, defaultRewardData, bytes(""), 0)
        {
            assertWithMsg(
                false,
                "VECVE-56 - combine all locks when shut down should not be possible"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == vecve_shutdownSelectorHash,
                "VECVE-56 - combine all locks when shut down did not fail with error"
            );
        }
    }

    /// @custom:property vecve-29 Calling extendLock with continuousLock set to 'true' should set the post extend lock time to CONTINUOUS_LOCK_VALUE
    /// @custom:property vecve-30 Calling extendLock for noncontinuous extension in the same epoch should not change the unlock epoch
    /// @custom:property vecve-31 Calling extendLock for noncontinuous extension in a future epoch should increase the unlock time
    /// @custom:property vecve-32 Calling extendLock with correct preconditions should not revert
    /// @custom:precondition veCVE is not shut down
    /// @custom:precondition lock to extend is not already continuous
    /// @custom:precondition lock must not already be unlocked
    function extendLock_should_succeed_if_not_shutdown(
        uint256 seed,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = _get_existing_lock(seed);
        require(lockIndex != NO_LOCKS);

        (, uint256 preExtendLockTime) = _get_user_locks_info(
            caller,
            lockIndex
        );
        require(preExtendLockTime > block.timestamp);
        require(preExtendLockTime != veCVE.CONTINUOUS_LOCK_VALUE());

        try
            veCVE.extendLock(
                lockIndex,
                continuousLock,
                defaultRewardData,
                bytes(""),
                0
            )
        {
            (, uint256 postExtendLockTime) = _get_user_locks_info(
                caller,
                lockIndex
            );
            // VECVE-29
            if (continuousLock) {
                assertWithMsg(
                    postExtendLockTime == veCVE.CONTINUOUS_LOCK_VALUE(),
                    "VECVE-29 - extendLock() should set veCVE.userPoints(caller)[index].unlockTime to CONTINUOUS"
                );
            } else {
                if (
                    veCVE.currentEpoch(preExtendLockTime) ==
                    veCVE.currentEpoch(postExtendLockTime)
                ) {
                    // VECVE-30
                    assertEq(
                        preExtendLockTime,
                        postExtendLockTime,
                        "VECVE-30 - extendLock() when extend is called in same epoch should be the same"
                    );
                } else {
                    // VECVE-31
                    assertGt(
                        postExtendLockTime,
                        preExtendLockTime,
                        "VECVE-31 - extendLock() when called in later epoch should increase unlock time"
                    );
                }
            }
        } catch {
            // VECVE-32
            assertWithMsg(
                false,
                "VECVE-32 - extendLock() with correct preconditions should not revert"
            );
        }
    }

    /// @custom:property vecve-24 – Trying to extend a lock that is already continuous should fail and revert with an error message indicating a lock type mismatch.
    /// @custom:precondition  veCVE is not shut down
    /// @custom:precondition  unlock time for lock is CONTINUOUS_LOCK_VALUE
    function extend_lock_should_fail_if_continuous(
        uint256 seed,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = _get_existing_lock(seed);
        require(lockIndex != NO_LOCKS);

        require(lockIndex != NO_LOCKS);
        require(_get_unlock_time(lockIndex) == veCVE.CONTINUOUS_LOCK_VALUE());

        try
            veCVE.extendLock(
                lockIndex,
                continuousLock,
                RewardsData(false, true, true, true),
                bytes(""),
                0
            )
        {
            assertWithMsg(
                false,
                "VECVE-24 - extendLock() should not be successful"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_lockTypeMismatchHash,
                "VECVE-24 - extendLock() failed unexpectedly"
            );
        }
    }

    /// @custom:property vecve-25 – Trying to extend a lock when the system is in shutdown should fail and revert with an error message indicating that the system is shut down.
    /// @custom:precondition  system is shut down
    function extend_lock_should_fail_if_shutdown(
        uint256 lockIndex,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() == 2);

        try
            veCVE.extendLock(
                lockIndex,
                continuousLock,
                RewardsData(false, true, true, true),
                bytes(""),
                0
            )
        {
            // VECVE.extendLock() should fail if the system is shut down
            assertWithMsg(
                false,
                "VECVE-25 - extendLock() should not be successful"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_shutdownSelectorHash,
                "VECVE-25 - extendLock() failed unexpectedly"
            );
        }
    }

    /// @custom:property vecve-33 - Increasing amount and extending lock should succeed when the lock is continuous.
    /// @custom:property vecve-34 – Increasing amount and extending lock decrease of CVE tokens.
    /// @custom:property vecve-35 – Increasing amount and extending lock increase of VECVE lock balance
    /// @custom:precondition  veCVE is not shut down
    /// @custom:precondition  unlock time for lock is CONTINUOUS_LOCK_VALUE
    function increaseAmountAndExtendLock_should_succeed_if_continuous(
        uint256 amount,
        uint256 number
    ) public {
        bool continuousLock = true;
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = _get_existing_lock(number);
        require(lockIndex != NO_LOCKS);

        amount = clampBetween(amount, WAD, type(uint64).max);
        (, uint256 unlockTime) = _get_user_locks_info(caller, lockIndex);
        require(unlockTime == veCVE.CONTINUOUS_LOCK_VALUE());
        // save balance of CVE
        uint256 preLockCVEBalance = cve.balanceOf(caller);
        // save balance of VE_CVE
        uint256 preLockVECVEBalance = veCVE.balanceOf(caller);

        _approve_cve_tokens(
            amount,
            "VE_CVE - increaseAmountAndExtendLock() failed on approve cve"
        );

        try
            veCVE.increaseAmountAndExtendLock(
                amount,
                lockIndex,
                continuousLock,
                defaultRewardData,
                bytes(""),
                0
            )
        {
            uint256 postLockCVEBalance = cve.balanceOf(caller);

            // vecve-34
            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VECVE-34 - increaseAmountAndExtendLock CVE transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(caller);

            // vecve-35
            assertEq(
                preLockVECVEBalance + amount,
                postLockVECVEBalance,
                "VECVE-35 - increaseAmountAndExtendLock VE_CVE token minted"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE-33 - increaseAmountAndExtendLock() failed unexpectedly"
            );
        }
    }

    /// @custom:property vecve-36 - Increasing amount and extending lock should succeed when the lock is non-continuous
    /// @custom:property vecve-37 – Increasing amount and extending lock for a non continuous lock results in decrease of CVE tokens.
    /// @custom:property vecve-38 – Increasing amount and extending lock for a non continuous lock results in increase of VECVE tokens.
    /// @custom:precondition veCVE is not shut down
    /// @custom:precondition unlock time for lock is not continuous
    /// @custom:precondition unlock time is not yet expired
    function increaseAmountAndExtendLock_should_succeed_if_non_continuous(
        uint256 amount,
        uint256 number,
        bool continuousLock
    ) public {
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = _get_existing_lock(number);
        require(lockIndex != NO_LOCKS);

        amount = clampBetween(amount, WAD, type(uint64).max);
        (, uint256 unlockTime) = _get_user_locks_info(caller, lockIndex);
        require(unlockTime != veCVE.CONTINUOUS_LOCK_VALUE());
        require(unlockTime >= block.timestamp);
        // save balance of CVE
        uint256 preLockCVEBalance = cve.balanceOf(caller);
        // save balance of VE_CVE
        uint256 preLockVECVEBalance = veCVE.balanceOf(caller);

        _approve_cve_tokens(
            amount,
            "VE_CVE - increaseAmountAndExtendLock() failed on approve cve"
        );

        try
            veCVE.increaseAmountAndExtendLock(
                amount,
                lockIndex,
                continuousLock,
                defaultRewardData,
                bytes(""),
                0
            )
        {
            uint256 postLockCVEBalance = cve.balanceOf(caller);

            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VECVE-37 - increaseAmountAndExtendLock CVE transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(caller);

            assertEq(
                preLockVECVEBalance + amount,
                postLockVECVEBalance,
                "VECVE-38 - increaseAmountAndExtendLock VE_CVE token minted"
            );
        } catch {
            assertWithMsg(
                false,
                "VECVE-36 - increaseAmountAndExtendLock() failed unexpectedly"
            );
        }
    }

    /// @custom:property vecve-39 - Processing a lock in a shutdown contract should complete successfully
    /// @custom:property vecve-40 – Processing a lock in a shutdown contract results in decreasing user points

    /// @custom:property vecve-41 – Processing a lock in a shutdown contract results in decreasing chain points
    /// @custom:property vecve-42 – Processing a non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch
    /// @custom:property vecve-43 – Processing a non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch

    /// @custom:property vecve-44 – Processing a lock in a shutdown contract results in increasing cve tokens
    /// @custom:property vecve-45 – Processing a lock in a shutdown contract results in decreasing vecve tokens
    /// @custom:property vecve-46 – Processing a lock in a shutdown contract results in decreasing number of user locks
    /// @custom:precondition veCVE is shut down
    function processExpiredLock_should_succeed_if_shutdown(
        uint256 seed
    ) public {
        require(veCVE.isShutdown() == 2);
        uint256 lockIndex = _get_existing_lock(seed);
        require(lockIndex != NO_LOCKS);
        (uint256 amount, uint256 unlockTime) = _get_user_locks_info(
            caller,
            lockIndex
        );
        require(unlockTime < block.timestamp);
        uint256 preUserPoints = veCVE.userPoints(caller);
        uint256 numberOfExistingLocks = _get_locks_length();
        uint256 preChainPoints = veCVE.chainPoints();
        uint256 currentEpoch = veCVE.currentEpoch(unlockTime);
        uint256 preChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
            currentEpoch
        );
        uint256 preUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            caller,
            currentEpoch
        );
        uint256 preLockVECVEBalance = veCVE.balanceOf(caller);
        uint256 preLockCVEBalance = cve.balanceOf(caller);

        try
            veCVE.processExpiredLock(
                lockIndex,
                false,
                true, // continuousLock = true
                defaultRewardData,
                bytes(""),
                0
            )
        {
            uint256 postUserPoints = veCVE.userPoints(caller);

            // vecve-40
            assertGt(
                preUserPoints,
                postUserPoints,
                "VECVE-40 - processExpiredLock() - userPoints should have decreased"
            );
            uint256 postChainPoints = veCVE.chainPoints();
            assertGt(
                preChainPoints,
                postChainPoints,
                "VECVE-41 - processExpiredLock() - chainPoints should have decreased"
            );
            // ve-cve-42, ve-cve-43
            _check_decrease_in_points(
                preChainUnlocksByEpoch,
                preUserUnlocksByEpoch,
                amount,
                currentEpoch,
                true,
                "VECVE-42",
                "VECVE-43"
            );
            // ve-cve-44, vecve-45, ve-cve-46
            _check_no_relock_post_conditions(
                preLockCVEBalance,
                preLockVECVEBalance,
                amount,
                numberOfExistingLocks
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - processExpiredLock() failed unexpected"
            );
        }
    }

    /// @custom:property vecve-47 - Processing a lock should complete successfully if unlock time is expired

    /// @custom:property vecve-48 – Processing a lock in a shutdown contract results in decreasing chain points
    /// @custom:property vecve-49 – Processing a non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch
    /// @custom:property vecve-50 – Processing a non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch

    /// @custom:property vecve-51 – Processing an expired lock without a relocking option results in increasing cve tokens
    /// @custom:property vecve-52 – Processing an expired lock without a relocking option results in decreasing vecve tokens
    /// @custom:property vecve-53 – Processing an expired lock without a relocking option results in decreasing number of user locks

    /// @custom:property ve-cve-54 Processing an expired lock without relocking should result in user points being equal.
    /// @custom:property ve-cve-55 Processing an expired lock without relocking should result in chain points being equal.

    /// @custom:precondition unlock time is expired
    function processExpiredLock_should_succeed_if_unlocktime_expired_and_not_shutdown_no_relock()
        public
    {
        require(veCVE.isShutdown() != 2);
        (uint256[] memory lockAmounts, ) = veCVE.queryUserLocks(caller);
        uint256 numberOfExistingLocks = lockAmounts.length;
        uint256 lockIndex = _get_expired_lock();
        require(lockIndex != NO_LOCKS);
        (uint256 amount, uint256 unlockTime) = _get_user_locks_info(
            caller,
            lockIndex
        );

        uint256 preUserPoints = veCVE.userPoints(caller);
        uint256 preChainPoints = veCVE.chainPoints();
        uint256 currentEpoch = veCVE.currentEpoch(unlockTime);
        uint256 preChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
            currentEpoch
        );
        uint256 preUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            caller,
            currentEpoch
        );
        uint256 preLockVECVEBalance = veCVE.balanceOf(caller);
        uint256 preLockCVEBalance = cve.balanceOf(caller);
        bool hasEpochs = _has_epochs_to_claim();

        try
            veCVE.processExpiredLock(
                lockIndex,
                false,
                true,
                defaultRewardData,
                bytes(""),
                0
            )
        {
            {
                // ve-cve-48, ve-cve-49, ve-cve-50
                _check_no_relock_post_conditions(
                    preLockCVEBalance,
                    preLockVECVEBalance,
                    amount,
                    numberOfExistingLocks
                );
            }
            {
                //ve-cve-51, ve-cve-52, ve-cve-53
                _check_decrease_in_points(
                    preChainUnlocksByEpoch,
                    preUserUnlocksByEpoch,
                    amount,
                    currentEpoch,
                    true,
                    "VECVE-52",
                    "VECVE-53"
                );
            }
            uint256 postUserPoints = veCVE.userPoints(caller);
            if (hasEpochs) {
                assertLt(
                    preUserPoints,
                    postUserPoints,
                    "VECVE-X - processExpiredLock() userPoints should decrease if epochs to claim remain"
                );
            } else {
                assertEq(
                    preUserPoints,
                    postUserPoints,
                    "VECVE-54 - processExpiredLock() - userPoints should be equal"
                );
            }

            uint256 postChainPoints = veCVE.chainPoints();
            assertEq(
                preChainPoints,
                postChainPoints,
                "VECVE-55 - processExpiredLock() - chainPoints should have decreased"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - processExpiredLock() failed unexpected if unlock time expired"
            );
        }
    }

    /// @custom:property ve-cve-56 Processing expired lock with relock should not change the number of locks a user has.
    /// @custom:precondition veCVE is not shut down
    /// @custom:precondition user has a pre-existing, expired lock
    function processExpiredLock_should_succeed_if_unlocktime_expired_and_not_shutdown_with_relock()
        public
    {
        require(veCVE.isShutdown() != 2);
        (uint256[] memory lockAmounts, ) = veCVE.queryUserLocks(caller);
        uint256 numberOfExistingLocks = lockAmounts.length;
        uint256 lockIndex = _get_expired_lock();
        require(lockIndex != NO_LOCKS);

        // Additional preconditions on the following values should also be added
        /*
        (uint256 amount, uint256 unlockTime) = _get_user_locks_info(caller, lockIndex);
        uint256 preUserPoints = veCVE.userPoints(caller);
        uint256 preChainPoints = veCVE.chainPoints();
        uint256 currentEpoch = veCVE.currentEpoch(unlockTime);
        uint256 preChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
            currentEpoch
        );
        uint256 preUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            caller,
            currentEpoch
        );
        uint256 preLockVECVEBalance = veCVE.balanceOf(caller);
        uint256 preLockCVEBalance = cve.balanceOf(caller);
        */

        try
            veCVE.processExpiredLock(
                lockIndex,
                true,
                true,
                defaultRewardData,
                bytes(""),
                0
            )
        {
            assertEq(
                numberOfExistingLocks,
                _get_locks_length(),
                "VECVE-56 - when relocking, the number of locks should be equivalent"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - processExpiredLock() failed unexpected if unlock time expired"
            );
        }
    }

    /// @custom:property vecve-19 – Processing an expired lock should fail when the lock index is incorrect or exceeds the length of created locks.
    function processExpiredLock_should_fail_if_lock_index_exceeds_length(
        uint256 seed
    ) public {
        uint256 lockIndex = clampBetween(
            seed,
            _get_locks_length(),
            type(uint256).max
        );
        emit LogUint256("lock index", lockIndex);
        try
            veCVE.processExpiredLock(
                lockIndex,
                false,
                true,
                defaultRewardData,
                bytes(""),
                0
            )
        {
            assertWithMsg(
                false,
                "VECVE-19 - processExpiredLock expected to fail if lock index exceeds length"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == vecve_invalidLockSelectorHash,
                "VECVE-19 - process() should fail when creating with 0"
            );
        }
    }

    /// @custom:property vecve-20 –  Disabling a continuous lock for a user’s continuous lock results in a decrease of user points.
    /// @custom:property vecve-21 – Disable continuous lock for a user’s continuous lock results in a decrease of chain points.
    /// @custom:property vecve-22 – Disable continuous lock for a user’s continuous lock results in preChainUnlocksByEpoch + amount being equal to postChainUnlocksByEpoch
    /// @custom:property vecve-23 – Disable continuous lock should for a user’s continuous lock results in  preUserUnlocksByEpoch + amount matching postUserUnlocksByEpoch
    /// @custom:precondition user has a continuous lock they intend to disable
    function disableContinuousLock_should_succeed_if_lock_exists() public {
        uint256 lockIndex = _get_continuous_lock();
        require(lockIndex != NO_LOCKS);
        uint256 preUserPoints = veCVE.userPoints(caller);
        uint256 preChainPoints = veCVE.chainPoints();
        uint256 newEpoch = veCVE.freshLockEpoch();
        uint256 preChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(newEpoch);
        uint256 preUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            caller,
            newEpoch
        );

        try
            veCVE.disableContinuousLock(
                lockIndex,
                defaultRewardData,
                bytes(""),
                0
            )
        {
            uint256 postUserPoints = veCVE.userPoints(caller);
            uint256 postChainPoints = veCVE.chainPoints();
            (uint256 amount, ) = _get_user_locks_info(caller, lockIndex);
            uint256 postChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
                newEpoch
            );
            uint256 postUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
                caller,
                newEpoch
            );

            assertGt(
                preUserPoints,
                postUserPoints,
                "VECVE-20 - disableContinuousLock() - userPoints should have decreased"
            );

            assertGt(
                preChainPoints,
                postChainPoints,
                "VECVE-21 - disableContinuousLock() - chainPoints should have decreased"
            );

            assertEq(
                preChainUnlocksByEpoch + amount,
                postChainUnlocksByEpoch,
                "VECVE-22 - disableContinuousLock() - postChainUnlocksByEpoch should be increased by amount"
            );

            assertEq(
                preUserUnlocksByEpoch + amount,
                postUserUnlocksByEpoch,
                "VECVE-23 - disableContinuousLock() - userUnlocksByEpoch should be increased by amount"
            );
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - disableContinuousLock() failed unexpectedly"
            );
        }
    }

    /// @custom:property vecve-26 Shutting down the contract when the caller has elevated permissions should result in the veCVE.isShutdown =2
    /// @custom:property vecve-27 Shutting down the contract when the caller has elevated permissions should result in the veCVE.isShutdown =2
    /// @custom:property vecve-28 Shutting down the contract when the caller has elevated permissions, and the system is not already shut down should never revert unexpectedly.
    /// @custom:precondition caller has elevated rights
    /// @custom:precondition caller system is not shut down already
    function shutdown_success_if_elevated_permission() public {
        // should be true on setup unless revoked
        require(centralRegistry.hasElevatedPermissions(caller));
        // should not be shut down already
        require(veCVE.isShutdown() != 2);
        emit LogAddress("caller from call", caller);
        // call central registry from addr(this)
        try veCVE.shutdown() {
            assertWithMsg(
                veCVE.isShutdown() == 2,
                "VECVE-26 - shutdown() did not set isShutdown variable"
            );
            // VECVE-27
            assertWithMsg(
                cveLocker.isShutdown() == 2,
                "VECVE-27 - shutdown() should also set cveLocker"
            );
        } catch {
            // VECVE-28
            assertWithMsg(
                false,
                "VECVE-28 - shutdown() by elevated permission failed unexpectedly"
            );
        }
    }

    // Stateful
    /// @custom:property s-vecve-1 Balance of veCVE must equal to the sum of all non-continuous lock amounts.
    function balance_must_equal_lock_amount_for_non_continuous() public {
        (
            uint256 lockAmountSum,
            uint256 numberOfExistingContinuousLocks
        ) = _get_sum_and_count_continuous_locks(caller);
        require(numberOfExistingContinuousLocks != _get_locks_length());
        assertEq(
            veCVE.balanceOf(caller),
            lockAmountSum,
            "S-VECVE-1 - balance = lock.amount for all non-continuous objects"
        );
    }

    /// @custom:property s-vecve-2 User unlocks by epoch should be greater than 0 for all non-continuous locks.
    /// @custom:property s-vecve-3 User unlocks by epoch should be 0 for all continuous locks.
    function user_unlock_for_epoch_for_values_are_correct() public {
        (
            ,
            uint256 numberOfExistingContinuousLocks
        ) = _get_sum_and_count_continuous_locks(caller);
        require(numberOfExistingContinuousLocks == _get_locks_length());
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = _get_user_locks_info(caller, i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            if (unlockTime != veCVE.CONTINUOUS_LOCK_VALUE()) {
                assertGt(
                    veCVE.userUnlocksByEpoch(caller, epoch),
                    0,
                    "S-VECVE-2 - userUnlockByEpoch >0 for non-continuous"
                );
            } else {
                assertEq(
                    veCVE.userUnlocksByEpoch(caller, epoch),
                    0,
                    "S-VECVE-3 - userUnlockBy Epoch == 0 for non-continuous"
                );
            }
        }
    }

    /// @custom:property s-vecve-4 Chain unlocks by epoch should be greater than 0 for all non-continuous locks.
    /// @custom:property s-vecve-5 Chain unlocks by epoch should be 0 for all continuous locks.
    function chain_unlock_for_epoch_for_values_are_correct() public {
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = _get_user_locks_info(caller, i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            if (unlockTime != veCVE.CONTINUOUS_LOCK_VALUE()) {
                assertGt(
                    veCVE.chainUnlocksByEpoch(epoch),
                    0,
                    "S-VECVE-4 - chainUnlockForEpoch >0 for non-continuous"
                );
            } else {
                assertEq(
                    veCVE.chainUnlocksByEpoch(epoch),
                    0,
                    "S-VECVE-5 - chainUnlockForEpoch ==0 for continuous"
                );
            }
        }
    }

    /// @custom:property s-vecve-6 The sum of all user unlock epochs for each epoch must be less than or equal to the user points.
    function sum_of_all_user_unlock_epochs_is_equal_to_user_points() public {
        _save_epoch_unlock_values();
        uint256 sumUserUnlockEpochs;

        for (uint256 i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = _get_user_locks_info(caller, i);

            uint256 epoch = veCVE.currentEpoch(unlockTime);

            sumUserUnlockEpochs += epochBalances[epoch].userUnlocksByEpoch;
        }
        assertLte(
            sumUserUnlockEpochs,
            veCVE.userPoints(caller),
            "S-VECVE-6 - sum_of_all_user_unlock_epochs_is_equal_to_user_points"
        );
    }

    /// @custom:property s-vecve-7 The contract should only have a zero cve balance when there are no user locks
    function no_user_locks_should_have_zero_cve_balance() public {
        address[4] memory senders = [
            address(0x10000),
            address(0x20000),
            address(0x30000),
            caller
        ];
        for (uint i = 0; i < senders.length; i++) {
            (uint256[] memory lockAmounts, ) = veCVE.queryUserLocks(
                senders[i]
            );
            uint256 numberOfExistingLocks = lockAmounts.length;
            require(numberOfExistingLocks == 0);
        }
        assertEq(
            cve.balanceOf(address(veCVE)),
            0,
            "S-VECVE-7 - CVE Balance of VECVE should be zero when there are no user locks"
        );
    }

    // Helper Functions

    /// @custom:propertyhelper vecve balance decreased
    /// @custom:propertyhelper cve balance increased
    /// @custom:property helper number of locks decreased
    function _check_no_relock_post_conditions(
        uint preLockCVEBalance,
        uint256 preLockVECVEBalance,
        uint256 amount,
        uint256 numberOfExistingLocks
    ) private {
        uint256 postLockVECVEBalance = veCVE.balanceOf(caller);
        // vecve-54
        assertEq(
            preLockVECVEBalance - amount,
            postLockVECVEBalance,
            "VE_CVE - processExpiredLock() - vcve balance should be decreased"
        );
        uint256 postLockCVEBalance = cve.balanceOf(caller);

        // vecve-53
        assertGt(
            postLockCVEBalance,
            preLockCVEBalance,
            "VE_CVE - processExpiredLock() - cve balance should be increased"
        );
        assertEq(
            numberOfExistingLocks - 1,
            _get_locks_length(),
            "VE_CVE - processExpiredLock() - existing locks decreased by 1"
        );
    }

    /// @custom:propertyhelper chainPoints decreased
    /// @custom:propertyhelper postChainUnlocksByEpoch decreased, if continuous
    /// @custom:propertyhelper userUnlocksByEpoch decreased, if continuous
    function _check_decrease_in_points(
        uint256 preChainUnlocksByEpoch,
        uint256 preUserUnlocksByEpoch,
        uint256 amount,
        uint256 currentEpoch,
        bool isContinuous,
        string memory chainUnlocksId,
        string memory userUnlocksId
    ) private {
        uint256 postChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
            currentEpoch
        );
        uint256 postUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            caller,
            currentEpoch
        );

        if (!isContinuous) {
            // vecve-50
            assertWithMsg(
                preChainUnlocksByEpoch - amount == postChainUnlocksByEpoch,
                chainUnlocksId,
                "- processExpiredLock() - postChainUnlocksByEpoch should be decreased by amount"
            );

            // vecve-51
            assertWithMsg(
                preUserUnlocksByEpoch - amount == postUserUnlocksByEpoch,
                userUnlocksId,
                "- processExpiredLock() - userUnlocksByEpoch should be decreased by amount"
            );
        }
    }

    function _check_continuous_lock_has_no_user_or_chain_points(
        uint256 combinedUnlockTime,
        string memory chainUnlocksString,
        string memory userUnlocksString
    ) private {
        uint256 epoch = veCVE.currentEpoch(combinedUnlockTime);

        assertEq(veCVE.chainUnlocksByEpoch(epoch), 0, chainUnlocksString);
        assertEq(
            veCVE.userUnlocksByEpoch(caller, epoch),
            0,
            userUnlocksString
        );
    }

    uint256[] uniqueEpochs;
    mapping(uint256 => CombineBalance) epochBalances;
    struct CombineBalance {
        uint256 chainUnlocksByEpoch;
        uint256 userUnlocksByEpoch;
    }

    function _save_epoch_unlock_values() private {
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = _get_user_locks_info(caller, i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            if (!_has_epoch_been_added(epoch)) {
                uniqueEpochs.push(epoch);
            }
            epochBalances[epoch].chainUnlocksByEpoch += veCVE
                .chainUnlocksByEpoch(epoch);
            epochBalances[epoch].userUnlocksByEpoch += veCVE
                .userUnlocksByEpoch(caller, epoch);
        }
    }

    function _has_epoch_been_added(uint _value) private view returns (bool) {
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            if (uniqueEpochs[i] == _value) return true;
        }
        return false;
    }

    function _get_sum_and_count_continuous_locks(
        address addr
    )
        private
        view
        returns (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        )
    {
        for (uint i = 0; i < _get_locks_length(); i++) {
            (uint216 amount, uint40 unlockTime) = _get_user_locks_info(
                addr,
                i
            );
            newLockAmount += amount;

            if (unlockTime == veCVE.CONTINUOUS_LOCK_VALUE()) {
                numberOfExistingContinuousLocks++;
            }
        }
    }

    function _get_user_locks_info(
        address addr,
        uint256 lockIndex
    ) private view returns (uint216 amount, uint40 unlockTime) {
        (amount, unlockTime) = veCVE.userLocks(addr, lockIndex);
    }

    function _get_existing_lock(uint256 seed) private returns (uint256) {
        if (_get_locks_length() == 0) {
            return NO_LOCKS;
        } else {
            return clampBetween(seed, 0, _get_locks_length() - 1);
        }
    }

    function _get_continuous_lock() private view returns (uint256 index) {
        for (uint i = 0; i < _get_locks_length(); i++) {
            (, uint40 unlockTime) = _get_user_locks_info(caller, i);
            if (unlockTime == veCVE.CONTINUOUS_LOCK_VALUE()) {
                return i;
            }
        }
        return NO_LOCKS;
    }

    function _get_expired_lock() private view returns (uint256 index) {
        for (uint i = 0; i < _get_locks_length(); i++) {
            (, uint40 unlockTime) = _get_user_locks_info(caller, i);
            if (unlockTime < block.timestamp) {
                return i;
            }
        }
        return NO_LOCKS;
    }

    function _get_unlock_time(
        uint256 lockIndex
    ) private view returns (uint256) {
        (, uint256[] memory unlockTimes) = veCVE.queryUserLocks(caller);
        return unlockTimes[lockIndex];
    }

    function _get_locks_length() private view returns (uint256) {
        (uint256[] memory lockAmounts, ) = veCVE.queryUserLocks(caller);
        return lockAmounts.length;
    }

    function _approve_cve_tokens(uint256 amount, string memory error) private {
        try cve.approve(address(veCVE), amount) {} catch {
            assertWithMsg(false, error);
        }
    }

    function _has_epochs_to_claim() private returns (bool) {
        return cveLocker.epochsToClaim(address(this)) > 0;
    }
}
