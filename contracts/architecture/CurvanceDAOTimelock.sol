// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract Timelock is TimelockController {
    /// CONSTANTS ///

    /// @notice Minimum delay for timelock transaction proposals to execute.
    uint256 public constant MINIMUM_DELAY = 7 days;
    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    address internal _DAO_ADDRESS;

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

        // grant admin/proposer/executor role to DAO.
        _DAO_ADDRESS = centralRegistry.daoAddress();
        _grantRole(PROPOSER_ROLE, _DAO_ADDRESS);
        _grantRole(EXECUTOR_ROLE, _DAO_ADDRESS);
    }

    function updateDaoAddress() external {
        address daoAddress = centralRegistry.daoAddress();
        if (daoAddress != _DAO_ADDRESS) {
            _revokeRole(PROPOSER_ROLE, _DAO_ADDRESS);
            _revokeRole(EXECUTOR_ROLE, _DAO_ADDRESS);

            _grantRole(PROPOSER_ROLE, daoAddress);
            _grantRole(EXECUTOR_ROLE, daoAddress);
        }
    }
}
