// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

contract FuzzVECVE is StatefulBaseMarket {
    struct CreateLockData {
        bool continuousLock;
        RewardsData rewardsData;
        bytes param;
        uint256 aux;
    }
    CreateLockData defaultContinuous;

    constructor() {
        defaultContinuous = CreateLockData(
            true,
            RewardsData(address(usdc), false, false, false),
            bytes(""),
            0
        );
    }

    function create_lock_with_zero_should_fail() public {
        require(veCVE.isShutdown() != 2);
        uint256 amount = 0;

        try cve.approve(address(veCVE), amount) {} catch {
            assertWithMsg(
                false,
                "VE_CVE - createLock call failed on cve token approval for ZERO"
            );
        }

        try
            veCVE.createLock(
                amount,
                defaultContinuous.continuousLock,
                defaultContinuous.rewardsData,
                defaultContinuous.param,
                defaultContinuous.aux
            )
        {
            assertWithMsg(
                false,
                "VE_CVE - createLock should have failed for ZERO amount"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == veCVE._INVALID_LOCK_SELECTOR(),
                "VE_CVE - createLock() should fail when creating with 0"
            );
        }
    }

    function create_continuous_lock_when_not_shutdown(uint256 amount) public {
        require(veCVE.isShutdown() != 2);
        amount = clampBetween(amount, 1, type(uint32).max);
        // save balance of CVE
        uint256 preLockCVEBalance = cve.balanceOf(address(this));
        // save balance of VE_CVE
        uint256 preLockVECVEBalance = veCVE.balanceOf(address(this));

        try cve.approve(address(veCVE), amount) {} catch {
            assertWithMsg(
                false,
                "VE_CVE - createLock call failed on cve token approval bound [1, type(uint32).max]"
            );
        }

        try
            veCVE.createLock(
                amount,
                defaultContinuous.continuousLock,
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
        } catch (bytes memory reason) {
            assertWithMsg(
                false,
                "VE_CVE - createLock call failed unexpectedly"
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
            assertWithMsg(
                false,
                "VE_CVE - extendLock() should not be successful"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == veCVE._VECVE_SHUTDOWN_SELECTOR(),
                "VE_CVE - extendLock() failed unexpectedly"
            );
        }
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
                errorSelector == veCVE._UNAUTHORIZED_SELECTOR(),
                "VE_CVE - shutdown() by elevated permission failed unexpectedly"
            );
        }
    }
}
