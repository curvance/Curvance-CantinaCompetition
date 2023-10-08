// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/ERC20.sol";

// mock CVE for testing
contract MockCve is ERC20 {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
