// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/interestRates/JumpRateModelV2.sol";
import "contracts/market/interestRates/InterestRateModel.sol";
import "contracts/market/Oracle/PriceOracle.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/gauge/GaugePool.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import "tests/utils/TestBase.sol";

contract DeployCurvanceMarket is TestBase {
    address public admin;
    Lendtroller public lendtroller;
    SimplePriceOracle public priceOracle;
    address public jumpRateModel;

    function makeCurvanceMarket() public {
        admin = address(this);
        makeLendtroller();
        makeJumpRateModel();
    }

    function makeLendtroller() public returns (address) {
        priceOracle = new SimplePriceOracle();

        // Some parameters are set zero address/values
        // which are not related to tests currently.
        lendtroller = new Lendtroller(
            ICentralRegistry(address(0)),
            address(0)
        );

        //lendtroller._setPriceOracle(PriceOracle(address(priceOracle)));
        lendtroller._setCloseFactor(5e17);
        lendtroller._setLiquidationIncentive(5e17);

        return address(lendtroller);
    }

    function makeJumpRateModel() public returns (address) {
        jumpRateModel = address(
            new JumpRateModelV2(1e17, 1e17, 1e17, 5e17, address(this))
        );
        return jumpRateModel;
    }
}
