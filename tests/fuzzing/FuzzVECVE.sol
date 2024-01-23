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

    /// @custom:property  vecve-1 - Creating a lock with a specified amount when the system is not in a shutdown state should succeed, with preLockCVEBalance matching postLockCVEBalance + amount and preLockVECVEBalance + amount matching postLockVECVEBalance.
    /// @custom:precondition  veCVE contract must not be shut down
    /// @custom:precondition  amount clamped between [WAD, uint64.max]
    /// @custom:precondition  CVE token must approve VeCVE token contract
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
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - createLock call failed unexpectedly"
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

    ///@custom:property  vecve-3 – Creating a lock with zero amount should fail and revert with an error message indicating an invalid lock amount.
    /// @custom:precondition  VeCVE contract is not shut down
    /// @custom:precondition  amount is 0
    /// @custom:precondition  VeCVE contract is approved for CVE
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

    /// @custom:property vecve-4 – Combining all continuous locks into a single continuous lock should result in identical user points before and after the operation.
    /// @custom:property vecve-5 – Combining all continuous locks into a single continuous lock should result in an increase in user points being greater than veCVE balance * MULTIPLIER / WAD.
    /// @custom:property vecve-6 – Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.
    /// @custom:property vecve-7 – Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.
    /// @custom:precondition  User must have more than 2 locks created
    /// @custom:precondition  All previous locks must be continuous
    function combineAllLocks_for_all_continuous_to_continuous_terminal_should_succeed()
        public
    {
        bool continuous = true;
        require(numLocks >= 2);

        uint256 preCombineUserPoints = veCVE.userPoints(address(this));
        (, uint256 numberOfExistingContinuousLocks) = get_all_user_lock_info(
            address(this)
        );
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
            (, uint40 combinedUnlockTime) = veCVE.userLocks(address(this), 0);

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

    /// @custom:property vecve-8 – Combining all non-continuous locks into a single non-continuous lock should result in the combined lock amount matching the sum of original lock amounts.
    /// @custom:property vecve-9 – Combining all continuous locks into a single continuous lock should result in resulting user points times the CL_POINT_MULTIPLIER being greater than or equal to the balance of veCVE.
    /// @custom:property vecve-10 – Combining non-continuous locks into continuous lock terminals should result in increased post combine user points compared to the pre combine user points.
    /// @custom:property vecve-11 – Combining non-continuous locks into continuous lock terminals should result in the userUnlockByEpoch value decreasing for each respective epoch.
    /// @custom:property vecve-12 – Combining non-continuous locks into continuous lock terminals should result in chainUnlockByEpoch decreasing for each respective epoch.
    /// @custom:property vecve-13 – Combining non-continuous locks to continuous locks should result in chainUnlockByEpochs being equal to 0.
    /// @custom:property vecve-14 – Combining non-continuous locks to continuous locks should result in the userUnlocksByEpoch being equal to 0.
    /// @custom:precondition  user must have more than 2 existing locks
    /// @custom:precondition  some of the pre-existing locks must be non-cntinuous
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
            (uint216 combinedAmount, uint40 combinedUnlockTime) = veCVE
                .userLocks(address(this), 0);

            // vecve-8
            assertEq(
                combinedAmount,
                newLockAmount,
                "VE_CVE - combineAllLocks() expected amount sum of new lock to equal calculated"
            );
            uint256 postCombineUserPoints = veCVE.userPoints(address(this));
            // vecve-9
            assertLt(
                preCombineUserPoints,
                postCombineUserPoints,
                "VE_CVE - combineAllLocks() - some or no prior continuous => continuous failed"
            );
            // vecve-10
            assertGte(
                postCombineUserPoints,
                (
                    (veCVE.balanceOf(address(this)) *
                        veCVE.CL_POINT_MULTIPLIER())
                ) / WAD,
                "VE_CVE - combineALlLocks() veCVE balance = userPoints * multiplier/DENOMINATOR failed for all continuous => continuous"
            );
            // for each existing lock's unique epoch
            for (uint i = 0; i < uniqueEpochs.length; i++) {
                uint256 unlockEpoch = uniqueEpochs[i];
                // vecve-11
                assertGte(
                    epochBalances[unlockEpoch].userUnlocksByEpoch,
                    veCVE.userUnlocksByEpoch(address(this), unlockEpoch),
                    "VE_CVE - pre userUnlockByEpoch must exceed post userUnlockByEpoch after noncontinuous -> continuous terminal"
                );
                // vecve-12
                assertGte(
                    epochBalances[unlockEpoch].chainUnlocksByEpoch,
                    veCVE.chainUnlocksByEpoch(unlockEpoch),
                    "VE_CVE - pre- chainUnlockByEpoch must exceed post chainUnlockByEpoch after noncontinuous -> continuous terminal"
                );
            }
            // vecve-13, vecve-14
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

    /// @custom:property vecve-15– Combining any locks to a non continuous terminal should result in the amount for the combined terminal matching the sum of original lock amounts.
    /// @custom:property vecve-16 – Combining some continuous locks to a non continuous terminal should result in user points decreasing.
    /// @custom:property vecve-17 – Combining no prior continuous locks to a non continuous terminal should result in no change in user points.
    /// @custom:property vecve-18 – Combining some prior continuous locks to a non continuous terminal should result in the veCVE balance of a user equaling the user points.
    /// @custom:precondition  User must have at least 2 existing locks
    function combineAllLocks_should_succeed_to_non_continuous_terminal()
        public
    {
        bool continuous = false;
        require(numLocks >= 2);
        save_epoch_unlock_values();

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
            (uint216 combinedAmount, ) = veCVE.userLocks(address(this), 0);

            // vecve-15
            assertEq(
                combinedAmount,
                newLockAmount,
                "VE_CVE - combineAllLocks() expected amount sum of new lock to equal calculated"
            );
            uint256 postCombineUserPoints = veCVE.userPoints(address(this));

            if (numberOfExistingContinuousLocks > 0) {
                // vecve-16
                assertGt(
                    preCombineUserPoints,
                    postCombineUserPoints,
                    "VE_CVE - combineAllLocks() - ALL continuous => !continuous failed"
                );
            }
            // no locks prior were continuous
            else {
                // CAN ADD: Post-condition check on the epoch balances
                // vecve-17
                assertEq(
                    preCombineUserPoints,
                    postCombineUserPoints,
                    "VE_CVE - combineAllLocks() NO continuous locks -> !continuous failed"
                );
            }
            //VECVE-18
            assertEq(
                veCVE.balanceOf(address(this)),
                postCombineUserPoints,
                "VE_CVE - combineAllLocks() balance should equal post combine user points"
            );

            numLocks = 1;
        } catch {
            assertWithMsg(
                false,
                "VE_CVE - combineAllLocks() failed unexpectedly with correct preconditions"
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
        uint256 lockIndex = get_existing_lock(seed);

        (, uint256 preExtendLockTime) = get_associated_lock(
            address(this),
            lockIndex
        );
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
            // VECVE-29
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
                    // VECVE-30
                    assertEq(
                        preExtendLockTime,
                        postExtendLockTime,
                        "VE_CVE - extendLock() when extend is called in same epoch should be the same"
                    );
                } else {
                    // VECVE-31
                    assertGt(
                        postExtendLockTime,
                        preExtendLockTime,
                        "VE_CVE - extendLock() when called in later epoch should increase unlock time"
                    );
                }
            }
        } catch {
            // VECVE-32
            assertWithMsg(
                false,
                "VE_CVE - extendLock() with correct preconditions should not revert"
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
        uint256 lockIndex = get_existing_lock(number);

        amount = clampBetween(amount, WAD, type(uint64).max);
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

            // vecve-34
            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VE_CVE - increaseAmountAndExtendLock CVE transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(address(this));

            // vecve-35
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
        //bool continuousLock = false;
        require(veCVE.isShutdown() != 2);
        uint256 lockIndex = get_existing_lock(number);
        isAllContinuous = false;

        amount = clampBetween(amount, WAD, type(uint64).max);
        (, uint256 unlockTime) = get_associated_lock(address(this), lockIndex);
        require(unlockTime != veCVE.CONTINUOUS_LOCK_VALUE());
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

            // vecve-37
            assertEq(
                preLockCVEBalance,
                postLockCVEBalance + amount,
                "VE_CVE - increaseAmountAndExtendLock CVE transferred to contract"
            );

            uint256 postLockVECVEBalance = veCVE.balanceOf(address(this));

            // vecve-38
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

    /// @custom:property vecve-39 - Processing a lock in a shutdown contract should complete successfully
    /// @custom:property vecve-40 – Processing a lock in a shutdown contract results in decreasing number of user locks
    /// @custom:property vecve-41 – Processing a lock in a shutdown contract results in decreasing user points
    /// @custom:property vecve-42 – Processing a lock in a shutdown contract results in decreasing chain points
    /// @custom:property vecve-43 – Processing a lock in a shutdown contract results in increasing cve tokens
    /// @custom:property vecve-44 – Processing a lock in a shutdown contract results in decreasing vecve tokens
    /// @custom:property vecve-45 – Processing an non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch
    /// @custom:property vecve-46 – Processing an non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch
    /// @custom:precondition veCVE is shut down
    function processExpiredLock_should_succeed_if_shutdown(
        uint256 seed
    ) public {
        require(veCVE.isShutdown() == 2);
        uint256 lockIndex = get_existing_lock(seed);
        (uint256 amount, uint256 unlockTime) = get_associated_lock(
            address(this),
            lockIndex
        );
        uint256 preUserPoints = veCVE.userPoints(address(this));
        uint256 preChainPoints = veCVE.chainPoints();
        uint256 currentEpoch = veCVE.currentEpoch(unlockTime);
        uint256 preChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
            currentEpoch
        );
        uint256 preUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            address(this),
            currentEpoch
        );
        uint256 preLockVECVEBalance = veCVE.balanceOf(address(this));
        uint256 preLockCVEBalance = cve.balanceOf(address(this));
        try
            veCVE.processExpiredLock(
                lockIndex,
                false,
                defaultContinuous.continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            // vecve-40
            numLocks--;
            uint256 postUserPoints = veCVE.userPoints((address(this)));
            uint256 postChainPoints = veCVE.chainPoints();
            uint256 postChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
                currentEpoch
            );
            uint256 postUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
                address(this),
                currentEpoch
            );
            uint256 postLockVECVEBalance = veCVE.balanceOf(address(this));
            uint256 postLockCVEBalance = cve.balanceOf(address(this));

            // vecve-41
            assertGt(
                preUserPoints,
                postUserPoints,
                "VE_CVE - processExpiredLock() - userPoints should have decreased"
            );

            // vecve-42
            assertGt(
                preChainPoints,
                postChainPoints,
                "VE_CVE - processExpiredLock() - chainPoints should have decreased"
            );

            // vecve-43
            assertGt(
                postLockCVEBalance,
                preLockCVEBalance,
                "VE_CVE - processExpiredLock() - cve balance should be increased"
            );

            // vecve-44
            assertEq(
                preLockVECVEBalance - amount,
                postLockVECVEBalance,
                "VE_CVE - processExpiredLock() - vcve balance should be decreased"
            );

            require(unlockTime != veCVE.CONTINUOUS_LOCK_VALUE());

            // vecve-45
            assertEq(
                preChainUnlocksByEpoch - amount,
                postChainUnlocksByEpoch,
                "VE_CVE - processExpiredLock() - postChainUnlocksByEpoch should be decreased by amount"
            );

            // vecve-46
            assertEq(
                preUserUnlocksByEpoch - amount,
                postUserUnlocksByEpoch,
                "VE_CVE - processExpiredLock() - userUnlocksByEpoch should be decreased by amount"
            );
        } catch {}
    }

    /// @custom:property vecve-47 - Processing a lock should complete successfully if unlock time is expired
    /// @custom:property vecve-48 – Processing an expired lock in a shutdown contract results in decreasing user points
    /// @custom:property vecve-49 – Processing an expired lock in a shutdown contract results in decreasing chain points
    /// @custom:property vecve-50 – Processing a non-continuous expired lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch
    /// @custom:property vecve-51 – Processing a non-continuous expired lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch
    /// @custom:property vecve-52 – Processing an expired lock without a relocking option results in decreasing number of user locks
    /// @custom:property vecve-53 – Processing an expired lock without a relocking option results in increasing cve tokens
    /// @custom:property vecve-54 – Processing an expired lock without a relocking option results in decreasing vecve tokens
    /// @custom:precondition unlock time is expired
    function processExpiredLock_should_succeed_if_unlocktime_expired(
        bool relock
    ) public {
        (uint256 lockIndex, bool isExpired) = get_expired_lock();
        require(isExpired);
        (uint256 amount, uint256 unlockTime) = get_associated_lock(
            address(this),
            lockIndex
        );
        uint256 preUserPoints = veCVE.userPoints(address(this));
        uint256 preChainPoints = veCVE.chainPoints();
        uint256 currentEpoch = veCVE.currentEpoch(unlockTime);
        uint256 preChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
            currentEpoch
        );
        uint256 preUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            address(this),
            currentEpoch
        );
        uint256 preLockVECVEBalance = veCVE.balanceOf(address(this));
        uint256 preLockCVEBalance = cve.balanceOf(address(this));

        try
            veCVE.processExpiredLock(
                lockIndex,
                relock,
                defaultContinuous.continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            {
                uint256 postUserPoints = veCVE.userPoints((address(this)));
                uint256 postChainPoints = veCVE.chainPoints();
                uint256 postChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
                    currentEpoch
                );
                uint256 postUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
                    address(this),
                    currentEpoch
                );

                if (veCVE.isShutdown() == 2) {
                    // vecve-48
                    assertGt(
                        preUserPoints,
                        postUserPoints,
                        "VE_CVE - processExpiredLock() - userPoints should have decreased"
                    );

                    // vecve-49
                    assertGt(
                        preChainPoints,
                        postChainPoints,
                        "VE_CVE - processExpiredLock() - chainPoints should have decreased"
                    );

                    require(unlockTime != veCVE.CONTINUOUS_LOCK_VALUE());

                    // vecve-50
                    assertEq(
                        preChainUnlocksByEpoch - amount,
                        postChainUnlocksByEpoch,
                        "VE_CVE - processExpiredLock() - postChainUnlocksByEpoch should be decreased by amount"
                    );

                    // vecve-51
                    assertEq(
                        preUserUnlocksByEpoch - amount,
                        postUserUnlocksByEpoch,
                        "VE_CVE - processExpiredLock() - userUnlocksByEpoch should be decreased by amount"
                    );
                }
            }

            uint256 postLockVECVEBalance = veCVE.balanceOf(address(this));
            uint256 postLockCVEBalance = cve.balanceOf(address(this));

            if (relock == false) {
                // vecve-52
                numLocks--;

                // vecve-53
                assertGt(
                    postLockCVEBalance,
                    preLockCVEBalance,
                    "VE_CVE - processExpiredLock() - cve balance should be increased"
                );

                // vecve-54
                assertEq(
                    preLockVECVEBalance - amount,
                    postLockVECVEBalance,
                    "VE_CVE - processExpiredLock() - vcve balance should be decreased"
                );
            }
        } catch {}
    }

    /// @custom:property vecve-19 – Processing an expired lock should fail when the lock index is incorrect or exceeds the length of created locks.
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

    /// @custom:property vecve-20 –  Disabling a continuous lock for a user’s continuous lock results in a decrease of user points.
    /// @custom:property vecve-21 – Disable continuous lock for a user’s continuous lock results in a decrease of chain points.
    /// @custom:property vecve-22 – Disable continuous lock for a user’s continuous lock results in preChainUnlocksByEpoch + amount being equal to postChainUnlocksByEpoch
    /// @custom:property vecve-23 – Disable continuous lock should for a user’s continuous lock results in  preUserUnlocksByEpoch + amount matching postUserUnlocksByEpoch
    /// @custom:precondition user has a continuous lock they intend to disable
    function disableContinuousLock_should_succeed_if_lock_exists() public {
        (uint256 lockIndex, bool isContinuous) = get_continuous_lock();
        require(isContinuous);
        uint256 preUserPoints = veCVE.userPoints(address(this));
        uint256 preChainPoints = veCVE.chainPoints();
        uint256 newEpoch = veCVE.freshLockEpoch();
        uint256 preChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(newEpoch);
        uint256 preUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
            address(this),
            newEpoch
        );

        try
            veCVE.disableContinuousLock(
                lockIndex,
                defaultContinuous.rewardsData,
                bytes(""),
                0
            )
        {
            uint256 postUserPoints = veCVE.userPoints((address(this)));
            uint256 postChainPoints = veCVE.chainPoints();
            (uint256 amount, ) = veCVE.userLocks(address(this), lockIndex);
            uint256 postChainUnlocksByEpoch = veCVE.chainUnlocksByEpoch(
                newEpoch
            );
            uint256 postUserUnlocksByEpoch = veCVE.userUnlocksByEpoch(
                address(this),
                newEpoch
            );

            // vecve-20
            assertGt(
                preUserPoints,
                postUserPoints,
                "VE_CVE - disableContinuousLock() - userPoints should have decreased"
            );

            // vecve-21
            assertGt(
                preChainPoints,
                postChainPoints,
                "VE_CVE - disableContinuousLock() - chainPoints should have decreased"
            );

            // vecve-22
            assertEq(
                preChainUnlocksByEpoch + amount,
                postChainUnlocksByEpoch,
                "VE_CVE - disableContinuousLock() - postChainUnlocksByEpoch should be increased by amount"
            );

            // vecve-23
            assertEq(
                preUserUnlocksByEpoch + amount,
                postUserUnlocksByEpoch,
                "VE_CVE - disableContinuousLock() - userUnlocksByEpoch should be increased by amount"
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
    /// @custom:precondition address(this) has elevated rights
    /// @custom:precondition address(this) system is not shut down already
    function shutdown_success_if_elevated_permission() public {
        // should be true on setup unless revoked
        require(centralRegistry.hasElevatedPermissions(address(this)));
        // should not be shut down already
        require(veCVE.isShutdown() != 2);
        emit LogAddress("msg.sender from call", address(this));
        // call central registry from addr(this)
        try veCVE.shutdown() {
            // VECVE-26
            assertWithMsg(
                veCVE.isShutdown() == 2,
                "VE_CVE - shutdown() did not set isShutdown variable"
            );
            // VECVE-27
            assertWithMsg(
                cveLocker.isShutdown() == 2,
                "VE_CVE - shutdown() should also set cveLocker"
            );
        } catch (bytes memory reason) {
            // VECVE-28
            assertWithMsg(
                false,
                "VE_CVE - shutdown() by elevated permission failed unexpectedly"
            );
        }
    }

    function earlyExpireLock_should_succeed(uint256 seed) public {
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

    // Stateful
    /// @custom:property s-vecve-1 Balance of veCVE must equal to the sum of all non-continuous lock amounts.
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

    /// @custom:property s-vecve-2 User unlocks by epoch should be greater than 0 for all non-continuous locks.
    /// @custom:property s-vecve-3 User unlocks by epoch should be 0 for all continuous locks.
    function user_unlock_for_epoch_for_values_are_correct() public {
        (, uint256 numberOfExistingContinuousLocks) = get_all_user_lock_info(
            address(this)
        );
        require(numberOfExistingContinuousLocks == numLocks);
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            if (unlockTime != veCVE.CONTINUOUS_LOCK_VALUE()) {
                assertGt(
                    veCVE.userUnlocksByEpoch(address(this), epoch),
                    0,
                    "VE_CVE - userUnlockByEpoch >0 for non-continuous"
                );
            } else {
                assertEq(
                    veCVE.userUnlocksByEpoch(address(this), epoch),
                    0,
                    "VE_CVE - userUnlockBy Epoch == 0 for non-continuous"
                );
            }
        }
    }

    /// @custom:property s-vecve-4 Chain unlocks by epoch should be greater than 0 for all non-continuous locks.
    /// @custom:property s-vecve-5 Chain unlocks by epoch should be 0 for all continuous locks.
    function chain_unlock_for_epoch_for_values_are_correct() public {
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            if (unlockTime != veCVE.CONTINUOUS_LOCK_VALUE()) {
                assertGt(
                    veCVE.chainUnlocksByEpoch(epoch),
                    0,
                    "VE_CVE - chainUnlockForEpoch >0 for non-continuous"
                );
            } else {
                assertEq(
                    veCVE.chainUnlocksByEpoch(epoch),
                    0,
                    "VE_CVE - chainUnlockForEpoch ==0 for continuous"
                );
            }
        }
    }

    /// @custom:property s-vecve-6 The sum of all user unlock epochs for each epoch must be less than or equal to the user points.
    function sum_of_all_user_unlock_epochs_is_equal_to_user_points() public {
        save_epoch_unlock_values();
        uint256 sumUserUnlockEpochs;

        emit LogUint256("numlocks", numLocks);
        emit LogUint256("uniqueEpochs", uniqueEpochs.length);

        for (uint256 i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);

            uint256 epoch = veCVE.currentEpoch(unlockTime);

            sumUserUnlockEpochs += epochBalances[epoch].userUnlocksByEpoch;
        }
        assertLte(
            sumUserUnlockEpochs,
            veCVE.userPoints(address(this)),
            "VE_CVE - sum_of_all_user_unlock_epochs_is_equal_to_user_points"
        );
    }

    // Helper Functions

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

    uint256[] uniqueEpochs;
    mapping(uint256 => CombineBalance) epochBalances;
    struct CombineBalance {
        uint256 chainUnlocksByEpoch;
        uint256 userUnlocksByEpoch;
    }

    function save_epoch_unlock_values() private {
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);
            uint256 epoch = veCVE.currentEpoch(unlockTime);
            if (!has_epoch_been_added(epoch)) {
                uniqueEpochs.push(epoch);
            }
            epochBalances[epoch].chainUnlocksByEpoch += veCVE
                .chainUnlocksByEpoch(epoch);
            epochBalances[epoch].userUnlocksByEpoch += veCVE
                .userUnlocksByEpoch(address(this), epoch);
        }
    }

    function has_epoch_been_added(uint _value) private returns (bool) {
        for (uint i = 0; i < uniqueEpochs.length; i++) {
            if (uniqueEpochs[i] == _value) return true;
        }
        return false;
    }

    function get_all_user_lock_info(
        address addr
    )
        private
        returns (
            uint256 newLockAmount,
            uint256 numberOfExistingContinuousLocks
        )
    {
        for (uint i = 0; i < numLocks; i++) {
            (uint216 amount, uint40 unlockTime) = veCVE.userLocks(addr, i);
            newLockAmount += amount;

            if (unlockTime == veCVE.CONTINUOUS_LOCK_VALUE()) {
                numberOfExistingContinuousLocks++;
            }
        }
    }

    function get_associated_lock(
        address addr,
        uint256 lockIndex
    ) private view returns (uint216 amount, uint40 unlockTime) {
        (amount, unlockTime) = veCVE.userLocks(addr, lockIndex);
    }

    function get_existing_lock(uint256 seed) private returns (uint256) {
        if (numLocks == 0) {
            create_lock_when_not_shutdown(seed, true);
            return 0;
        }
        return clampBetween(seed, 0, numLocks);
    }

    function get_continuous_lock()
        private
        view
        returns (uint256 index, bool exists)
    {
        for (uint i = 0; i < numLocks; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);
            if (unlockTime == veCVE.CONTINUOUS_LOCK_VALUE()) {
                return (i, true);
            }
        }
        return (0, false);
    }

    function get_expired_lock()
        private
        view
        returns (uint256 index, bool exists)
    {
        for (uint i = 0; i < numLocks; i++) {
            (, uint40 unlockTime) = veCVE.userLocks(address(this), i);
            if (unlockTime < block.timestamp) {
                return (i, true);
            }
        }
        return (0, false);
    }

    function approve_cve(uint256 amount, string memory error) private {
        try cve.approve(address(veCVE), amount) {} catch {
            assertWithMsg(false, error);
        }
    }
}
