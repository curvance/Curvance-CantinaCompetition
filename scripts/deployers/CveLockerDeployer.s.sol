// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CveLockerDeployer is Script {
    address cveLocker;

    function deployCveLocker(
        address centralRegistry,
        address rewardToken
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(rewardToken != address(0), "Set the rewardToken!");

        cveLocker = address(
            new CVELocker(ICentralRegistry(centralRegistry), rewardToken)
        );

        console.log("cveLocker: ", cveLocker);
    }
}
