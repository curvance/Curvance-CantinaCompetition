// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestStatefulDeployments } from "tests/fuzzing/TestStatefulDeployments.sol";
import { FuzzVECVE } from "tests/fuzzing/FuzzVECVE.sol";
import { FuzzMarketManager } from "tests/fuzzing/FuzzMarketManager.sol";
import { FuzzMarketManagerRBAC } from "tests/fuzzing/FuzzMarketManagerRBAC.sol";
import { FuzzMarketManagerStateChecks } from "tests/fuzzing/FuzzMarketManagerStateChecks.sol";
import { FuzzDToken } from "tests/fuzzing/FuzzDToken.sol";

//
contract FuzzingSuite is
    FuzzDToken,
    FuzzMarketManager,
    FuzzMarketManagerRBAC,
    FuzzMarketManagerStateChecks,
    FuzzVECVE,
    TestStatefulDeployments
{

}
