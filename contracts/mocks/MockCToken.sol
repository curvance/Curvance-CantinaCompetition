// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract MockCToken is CTokenPrimitive {
    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 underlying_,
        address lendtroller_
    ) CTokenPrimitive(centralRegistry_, underlying_, lendtroller_) {}
}
