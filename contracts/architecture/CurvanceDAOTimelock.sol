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
    address internal _daoAddress;

    /// ERRORS ///

    error Timelock__InvalidCentralRegistry(address invalidCentralRegistry);

    /// CONSTRUCTOR ///

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
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert Timelock__InvalidCentralRegistry(address(centralRegistry_));
        }

        centralRegistry = centralRegistry_;

        // grant admin/proposer/executor role to DAO
        _daoAddress = centralRegistry.daoAddress();
        _grantRole(PROPOSER_ROLE, _daoAddress);
        _grantRole(EXECUTOR_ROLE, _daoAddress);
    }

    function updateDaoAddress() external {
        address daoAddress = centralRegistry.daoAddress();
        if (daoAddress != _daoAddress) {
            _revokeRole(PROPOSER_ROLE, _daoAddress);
            _revokeRole(EXECUTOR_ROLE, _daoAddress);

            _grantRole(PROPOSER_ROLE, daoAddress);
            _grantRole(EXECUTOR_ROLE, daoAddress);
        }
    }
}
