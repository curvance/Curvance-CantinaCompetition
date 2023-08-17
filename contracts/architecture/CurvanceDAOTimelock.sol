// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract Timelock is TimelockController {
    /// CONSTANTS ///

    // Minimum delay for timelock transaction proposals to execute
    uint256 public constant MINIMUM_DELAY = 7 days;
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    constructor(
        ICentralRegistry centralRegistry_
    )
        TimelockController(
            MINIMUM_DELAY,
            new address[](0),
            new address[](0),
            address(0)
        )
    {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "Timelock: invalid central registry"
        );

        centralRegistry = centralRegistry_;

        // grant admin/proposer/executor role to DAO
        address _centralRegistryDaoAddress = centralRegistry.daoAddress();
        _grantRole(PROPOSER_ROLE, _centralRegistryDaoAddress);
        _grantRole(EXECUTOR_ROLE, _centralRegistryDaoAddress);
    }
}
