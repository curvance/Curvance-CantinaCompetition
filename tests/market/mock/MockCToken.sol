// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { CTokenPrimitive, IERC20 } from "contracts/market/collateral/CTokenPrimitive.sol";

contract MockCToken is CTokenPrimitive {
    constructor(
        ICentralRegistry centralRegistry_,
        address asset_,
        address lendtroller_
    ) CTokenPrimitive(centralRegistry_,  IERC20(asset_), lendtroller_) {}

}
