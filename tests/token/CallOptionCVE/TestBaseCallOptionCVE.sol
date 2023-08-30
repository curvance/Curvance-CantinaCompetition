// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CallOptionCVE } from "contracts/token/CallOptionCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract TestBaseCallOptionCVE is TestBaseMarket {
    CallOptionCVE public callOptionCVE;

    function setUp() public virtual override {
        super.setUp();

        callOptionCVE = new CallOptionCVE(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );
    }
}
