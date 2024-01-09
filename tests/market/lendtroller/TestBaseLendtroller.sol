// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

contract TestBaseLendtroller is TestBaseMarket {
    MockDataFeed public mockWethFeed;
    MockDataFeed public mockRethFeed;

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

        mockWethFeed = new MockDataFeed(_CHAINLINK_ETH_USD);
        chainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(mockWethFeed),
            0,
            true
        );
        dualChainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(mockWethFeed),
            0,
            true
        );
        mockRethFeed = new MockDataFeed(_CHAINLINK_ETH_USD);
        chainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(mockRethFeed),
            0,
            true
        );
        dualChainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(mockRethFeed),
            0,
            true
        );
    }
}
