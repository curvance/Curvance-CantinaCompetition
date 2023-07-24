// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract Timelock is TimelockController {

    /// CONSTANTS ///
    uint256 public constant MINIMUM_DELAY = 7 days;
    ICentralRegistry public immutable centralRegistry;

    constructor(ICentralRegistry centralRegistry_)
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
        _grantRole(PROPOSER_ROLE, centralRegistry.daoAddress());
        _grantRole(EXECUTOR_ROLE, centralRegistry.daoAddress());
    }
}
