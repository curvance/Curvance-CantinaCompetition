// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestStatefulDeployments } from "tests/fuzzing/system/TestStatefulDeployments.sol";
import { FuzzVeCVE } from "tests/fuzzing/functional/FuzzVeCVE.sol";
import { FuzzMarketManager } from "tests/fuzzing/FuzzMarketManager.sol";
import { FuzzMarketManagerSystem } from "tests/fuzzing/system/FuzzMarketManagerSystem.sol";
import { FuzzMarketManagerRBAC } from "tests/fuzzing/functional/FuzzMarketManagerRBAC.sol";
import { FuzzMarketManagerStateChecks } from "tests/fuzzing/functional/FuzzMarketManagerStateChecks.sol";
import { FuzzDToken } from "tests/fuzzing/functional/FuzzDToken.sol";
import { FuzzDTokenSystem } from "tests/fuzzing/system/FuzzDTokenSystem.sol";

//
contract FuzzingSuite is
    FuzzDToken,
    FuzzDTokenSystem,
    FuzzMarketManager,
    FuzzMarketManagerSystem,
    FuzzMarketManagerRBAC,
    FuzzMarketManagerStateChecks,
    FuzzVeCVE,
    TestStatefulDeployments
{

}
