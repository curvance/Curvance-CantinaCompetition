// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/Unitroller/Unitroller.sol";
import "contracts/market/interestRates/JumpRateModelV2.sol";
import "contracts/market/interestRates/InterestRateModel.sol";
import "contracts/market/Oracle/PriceOracle.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/gauge/GaugeController.sol";

import "tests/utils/TestBase.sol";

contract DeployCompound is TestBase {
    address public admin;
    Lendtroller public lendtroller;
    Unitroller public unitroller;
    SimplePriceOracle public priceOracle;
    address public jumpRateModel;

    function makeCompound() public {
        admin = address(this);
        makeUnitroller();
        makeJumpRateModel();
    }

    function makeUnitroller() public returns (address) {
        priceOracle = new SimplePriceOracle();

        unitroller = new Unitroller();
        // Some parameters are set zero address/values
        // which are not related to tests currently.
        lendtroller = new Lendtroller(GaugeController(address(0)));

        unitroller._setPendingImplementation(address(lendtroller));
        lendtroller._become(unitroller);

        Lendtroller(address(unitroller))._setPriceOracle(
            PriceOracle(address(priceOracle))
        );
        Lendtroller(address(unitroller))._setCloseFactor(5e17);
        Lendtroller(address(unitroller))._setLiquidationIncentive(5e17);

        return address(unitroller);
    }

    function makeJumpRateModel() public returns (address) {
        jumpRateModel = address(
            new JumpRateModelV2(1e17, 1e17, 1e17, 5e17, address(this))
        );
        return jumpRateModel;
    }
}
