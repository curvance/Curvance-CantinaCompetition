// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockCToken is ERC20 {
    using SafeERC20 for IERC20;

    uint8 private __decimals;

    address public underlying;

    constructor(address _underlying, string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        underlying = _underlying;
        __decimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }

    function mint(uint256 amount) external returns (bool) {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        _mint(msg.sender, amount);

        return true;
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {}
}
