// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/ERC20.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

contract MockCToken is ERC20 {

    uint8 private _decimals;
    address public underlying;

    constructor(
        address underlying_,
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        underlying = underlying_;
        decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(uint256 amount) external returns (bool) {
        SafeTransferLib.safeTransferFrom(underlying, msg.sender, address(this), amount);

        _mint(msg.sender, amount);
        return true;
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {}
}
