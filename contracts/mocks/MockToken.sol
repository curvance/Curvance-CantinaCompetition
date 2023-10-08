// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import { ERC20 } from "contracts/libraries/ERC20.sol";

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 100000000 * (10**decimals_));
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
