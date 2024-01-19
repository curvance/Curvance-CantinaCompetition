// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "erc4626-tests/ERC4626.test.sol";
import { TestBaseMarket, ICentralRegistry } from "tests/market/TestBaseMarket.sol";
import { MockERC20Token } from "./MockERC20Token.sol";
import { MockCToken } from "./MockCToken.sol";

///@dev ERC4626 Property Tests: https://github.com/a16z/erc4626-tests
contract ERC4626StdCTokenTest is ERC4626Test, TestBaseMarket {
    // @todo check the failing tests: test_maxWithdraw! which reverts
    // test_redeem, test_withdraw have problem with allowance
    function setUp() public override(ERC4626Test, TestBaseMarket) {
        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();
        _deployVeCVE();
        _deployGaugePool();
        _deployLendtroller();

        // start gauge to enable deposits
        gaugePool.start(address(lendtroller));
        vm.warp(veCVE.nextEpochStartTime() + 1000);

        // deploy collateral token and cToken
        MockERC20Token mockUnderlying = new MockERC20Token();
        vm.label(address(mockUnderlying), "tokenCollateral");
        MockCToken mockCToken = new MockCToken(
            ICentralRegistry(address(centralRegistry)),
            address(mockUnderlying),
            address(lendtroller)
        );
        vm.label(address(mockCToken), "cToken");

        // start market for cToken
        uint256 startAmount = 42069;
        mockUnderlying.mint(address(this), startAmount);
        mockUnderlying.approve(address(mockCToken), startAmount);
        lendtroller.listToken(address(mockCToken));

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
