// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

contract TestBaseDToken is TestBaseMarket {
    function setUp() public virtual override {
        super.setUp();

        _deployDUSDC();

        gaugePool.start(address(lendtroller));
        priceRouter.addMTokenSupport(address(dUSDC));

        _prepareUSDC(user1, _ONE);
        _prepareUSDC(address(this), _ONE);

        SafeTransferLib.safeApprove(_USDC_ADDRESS, address(dUSDC), _ONE);
        lendtroller.listMarketToken(address(dUSDC));

        dUSDC.depositReserves(1000e6);
    }
}
