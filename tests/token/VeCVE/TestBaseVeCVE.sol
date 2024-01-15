// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

contract TestBaseVeCVE is TestBaseMarket {
    RewardsData public rewardsData;

    modifier setRewardsData(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) {
        rewardsData = RewardsData(
            _USDC_ADDRESS,
            shouldLock,
            isFreshLock,
            isFreshLockContinuous
        );
        _;
    }

    function setUp() public virtual override {
        super.setUp();

        rewardsData = RewardsData(_USDC_ADDRESS, true, true, true);
    }
}
