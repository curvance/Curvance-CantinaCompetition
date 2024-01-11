// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC20 } from "contracts/libraries/external/ERC20.sol";

contract MockERC20Token is ERC20 {
    function name() public pure override returns (string memory) {
        return "ERC20Mock";
    }

    function symbol() public pure override returns (string memory) {
        return "E20M";
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
