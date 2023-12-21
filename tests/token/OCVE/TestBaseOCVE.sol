// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { OCVE } from "contracts/token/OCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract TestBaseOCVE is TestBaseMarket {
    OCVE public oCVE;

    function setUp() public virtual override {
        super.setUp();

        oCVE = new OCVE(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );
    }
}
