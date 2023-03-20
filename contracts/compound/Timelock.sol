// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/governance/TimelockController.sol";

contract Timelock is TimelockController {
    uint256 public constant MINIMUM_DELAY = 2 days;

    constructor(address admin) TimelockController(MINIMUM_DELAY, new address[](0), new address[](0)) {
        // remove admin role from deployer
        _revokeRole(TIMELOCK_ADMIN_ROLE, _msgSender());

        // grant admin/proposer/executor role to admin
        _setupRole(TIMELOCK_ADMIN_ROLE, admin);
        _setupRole(PROPOSER_ROLE, admin);
        _setupRole(EXECUTOR_ROLE, admin);
    }
}
