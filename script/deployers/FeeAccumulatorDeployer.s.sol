// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract FeeAccumulatorDeployer is DeployConfiguration {
    address feeAccumulator;

    function _deployFeeAccumulator(
        address centralRegistry,
        address feeToken,
        uint256 gasForCalldata,
        uint256 gasForCrosschain
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(feeToken != address(0), "Set the feeToken!");

        feeAccumulator = address(
            new FeeAccumulator(
                ICentralRegistry(centralRegistry),
                feeToken,
                gasForCalldata,
                gasForCrosschain
            )
        );

        console.log("feeAccumulator: ", feeAccumulator);
        _saveDeployedContracts("feeAccumulator", feeAccumulator);
    }
}
