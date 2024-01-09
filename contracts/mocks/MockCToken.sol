// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/external/ERC20.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract MockCToken is ERC20 {

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    address public underlying;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        underlying = underlying_;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
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
