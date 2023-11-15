// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

contract TestBaseLendtroller is TestBaseMarket {
    function setUp() public virtual override {
        super.setUp();

        gaugePool.start(address(lendtroller));

        _prepareUSDC(address(this), _ONE);
        _prepareDAI(address(this), _ONE);
        _prepareBALRETH(address(this), _ONE);

        priceRouter.addMTokenSupport(address(dDAI));

        SafeTransferLib.safeApprove(_USDC_ADDRESS, address(dUSDC), _ONE);
        SafeTransferLib.safeApprove(_DAI_ADDRESS, address(dDAI), _ONE);
        SafeTransferLib.safeApprove(
            _BALANCER_WETH_RETH,
            address(cBALRETH),
            _ONE
        );
    }
}
