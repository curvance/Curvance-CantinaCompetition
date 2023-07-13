// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    uint8 private __decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 _decimals
    ) ERC20(name, symbol) {
        __decimals = _decimals;
        _mint(msg.sender, 100000000 * (10**_decimals));
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
