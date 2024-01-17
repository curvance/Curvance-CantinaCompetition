// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestStatefulDeployments } from "tests/fuzzing/TestStatefulDeployments.sol";
import { FuzzVECVE } from "tests/fuzzing/FuzzVECVE.sol";
import { FuzzLendtroller } from "tests/fuzzing/FuzzLendtroller.sol";
import { FuzzLendtrollerRBAC } from "tests/fuzzing/FuzzLendtrollerRBAC.sol";
import { FuzzLendtrollerStateChecks } from "tests/fuzzing/FuzzLendtrollerStateChecks.sol";
import { FuzzDToken } from "tests/fuzzing/FuzzDToken.sol";

//
contract FuzzingSuite is
    FuzzDToken,
    FuzzLendtroller,
    FuzzLendtrollerRBAC,
    FuzzLendtrollerStateChecks,
    FuzzVECVE,
    TestStatefulDeployments
{

}
