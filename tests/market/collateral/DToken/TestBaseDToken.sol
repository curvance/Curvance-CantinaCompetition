// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract TestBaseDToken is TestBaseMarket {
    function setUp() public virtual override {
        super.setUp();

        gaugePool.start(address(lendtroller));

        _prepareUSDC(user1, _ONE);
        _prepareUSDC(address(this), _ONE);

        vm.prank(user1);
        usdc.approve(address(dUSDC), _ONE);

        usdc.approve(address(dUSDC), _ONE);
        lendtroller.listMarketToken(address(dUSDC));

        address[] memory markets = new address[](1);
        markets[0] = address(dUSDC);

        lendtroller.enterMarkets(markets);

        dUSDC.depositReserves(1000e6);

        _prepareBALRETH(address(this), 10e18);
        balRETH.approve(address(cBALRETH), 10e18);

        lendtroller.listMarketToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            200,
            0,
            1200,
            1000,
            5000
        );

        markets[0] = address(cBALRETH);

        lendtroller.enterMarkets(markets);

        cBALRETH.mint(1e18);
    }
}
