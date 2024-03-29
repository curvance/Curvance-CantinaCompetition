// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { Delegable } from "contracts/libraries/Delegable.sol";

contract CVELockerDeploymentTest is TestBaseCVELocker {
    function test_cveLockerDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(Delegable.Delegable__InvalidCentralRegistry.selector);
        new CVELocker(ICentralRegistry(address(0)), _USDC_ADDRESS);
    }

    function test_cveLockerDeployment_fail_whenRewardTokenIsZeroAddress()
        public
    {
        vm.expectRevert(
            CVELocker.CVELocker__RewardTokenIsZeroAddress.selector
        );
        new CVELocker(ICentralRegistry(address(centralRegistry)), address(0));
    }

    function test_cveLockerDeployment_success() public {
        cveLocker = new CVELocker(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );

        assertEq(
            address(cveLocker.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(cveLocker.genesisEpoch(), centralRegistry.genesisEpoch());
        assertEq(cveLocker.rewardToken(), _USDC_ADDRESS);
        assertEq(cveLocker.cve(), centralRegistry.cve());
    }
}
