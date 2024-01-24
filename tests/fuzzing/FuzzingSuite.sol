// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestStatefulDeployments } from "tests/fuzzing/TestStatefulDeployments.sol";
import { FuzzVECVE } from "tests/fuzzing/functional/FuzzVECVE.sol";
import { FuzzLendtroller } from "tests/fuzzing/FuzzLendtroller.sol";
import { FuzzLendtrollerSystem } from "tests/fuzzing/system/FuzzLendtrollerSystem.sol";
import { FuzzLendtrollerRBAC } from "tests/fuzzing/functional/FuzzLendtrollerRBAC.sol";
import { FuzzLendtrollerStateChecks } from "tests/fuzzing/functional/FuzzLendtrollerStateChecks.sol";
import { FuzzDToken } from "tests/fuzzing/functional/FuzzDToken.sol";
import { FuzzDTokenSystem } from "tests/fuzzing/system/FuzzDTokenSystem.sol";

//
contract FuzzingSuite is
    FuzzDToken,
    FuzzDTokenSystem,
    FuzzLendtroller,
    FuzzLendtrollerSystem,
    FuzzLendtrollerRBAC,
    FuzzLendtrollerStateChecks,
    FuzzVECVE,
    TestStatefulDeployments
{

}
