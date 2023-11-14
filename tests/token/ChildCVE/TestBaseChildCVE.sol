// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/ChildCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract TestBaseChildCVE is TestBaseMarket {
    CVE public childCVE;

    function setUp() public virtual override {
        super.setUp();

        childCVE = new CVE(
            "Child Curvance",
            "childCVE",
            18,
            _LZ_ENDPOINT,
            ICentralRegistry(address(centralRegistry))
        );
    }
}
