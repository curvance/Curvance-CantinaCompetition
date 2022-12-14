// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract Cve is ERC20Votes {
    constructor(address owner) ERC20Permit("Curvance") ERC20("Curvance", "CVE") {
        _mint(owner, 10000000e18);
    }
}
