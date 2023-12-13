// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

contract FuzzVECVE is StatefulBaseMarket {
    function extend_lock_should_fail_if_shutdown(
        uint256 lockIndex,
        bool continuousLock
    ) public {
        // if CVE is not already shut down
        if (veCVE.isShutdown() != 2) {
            // attempt to shut it down
            shutdown_success_if_elevated_permission();
        }
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
        } catch (bytes memory reason) {
            uint256 errorSelector = extractErrorSelector(reason);

            assertWithMsg(
                errorSelector == veCVE._VECVE_SHUTDOWN_SELECTOR(),
                "VE_CVE - extendLock() should error with VECVE_SHUTDOWN_SELECTOR"
            );
        }
    }

    function shutdown_success_if_elevated_permission() public {
        // should be true on setup unless revoked
        require(centralRegistry.hasElevatedPermissions(address(this)));
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
