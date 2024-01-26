// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

contract TestBaseVeCVE is TestBaseMarket {
    RewardsData public rewardsData;
    uint256 internal constant _MIN_FUZZ_AMOUNT = 1e18;
    uint256 internal constant _MAX_FUZZ_AMOUNT = 420e24;

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
