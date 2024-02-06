// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/external/ERC20.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";

// mock CVE for testing
contract MockCve is ERC20, ERC165 {

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IVeCVE).interfaceId ||
            super.supportsInterface(interfaceId);
    }

}
