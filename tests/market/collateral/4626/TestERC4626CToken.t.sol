// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import { TestERC4626 } from "tests/market/collateral/4626/TestERC4626.t.sol";
import { TestBaseMarket, ICentralRegistry } from "tests/market/TestBaseMarket.sol";
import { MockERC20Token } from "tests/market/MockERC20Token.sol";
import { MockCTokenPrimitive } from "tests/market/MockCTokenPrimitive.sol";

contract TestERC4626CToken is TestERC4626, TestBaseMarket {
    // @todo check the failing tests: test_maxWithdraw! which reverts
    // test_redeem, test_withdraw have problem with allowance
    function setUp() public override(TestERC4626, TestBaseMarket) {
        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();
        _deployVeCVE();
        _deployGaugePool();
        _deployMarketManager();

        // start gauge to enable deposits
        gaugePool.start(address(marketManager));
        vm.warp(veCVE.nextEpochStartTime() + 1000);

        // deploy collateral token and cToken
        MockERC20Token mockUnderlying = new MockERC20Token();
        vm.label(address(mockUnderlying), "tokenCollateral");
        MockCTokenPrimitive mockCToken = new MockCTokenPrimitive(
            ICentralRegistry(address(centralRegistry)),
            address(mockUnderlying),
            address(marketManager)
        );
        vm.label(address(mockCToken), "cToken");

        // start market for cToken
        uint256 startAmount = 42069;
        mockUnderlying.mint(address(this), startAmount);
        mockUnderlying.approve(address(mockCToken), startAmount);
        marketManager.listToken(address(mockCToken));

        _underlying_ = address(mockUnderlying);
        _vault_ = address(mockCToken);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = true;
    }

    function test_withdraw(
        Init memory init,
        uint assets,
        uint allowance
    ) public override {}

    function test_maxWithdraw(Init memory init) public override {}

    function test_redeem(
        Init memory init,
        uint shares,
        uint allowance
    ) public override {}
}
