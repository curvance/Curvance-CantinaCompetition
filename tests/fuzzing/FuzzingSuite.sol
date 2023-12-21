// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestStatefulDeployments } from "tests/fuzzing/TestStatefulDeployments.sol";
import { FuzzVECVE } from "tests/fuzzing/FuzzVECVE.sol";
import { FuzzLendtroller } from "tests/fuzzing/FuzzLendtroller.sol";

//
contract FuzzingSuite is TestStatefulDeployments, FuzzLendtroller, FuzzVECVE {

}
