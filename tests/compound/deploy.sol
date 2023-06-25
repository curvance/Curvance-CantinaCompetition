// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/Unitroller/Unitroller.sol";
import "contracts/market/CompRewards/CompRewards.sol";
import "contracts/market/InterestRateModel/JumpRateModel.sol";
import "contracts/market/InterestRateModel/InterestRateModel.sol";
import "contracts/market/Oracle/PriceOracle.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";

import "tests/utils/TestBase.sol";

contract DeployCompound is TestBase {
    address public admin;
    CVE public cve;
    Comptroller public comptroller;
    Unitroller public unitroller;
    CompRewards public compRewards;
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
        cve = new CVE(
            "Curvance",
            "CVE",
            18,
            address(0),
            ICentralRegistry(address(0)),
            address(0),
            0,
            0,
            0,
            10000000e18
        );
        compRewards = new CompRewards(address(unitroller), address(admin), address(cve));
        cve.transfer(address(compRewards), 1000e18);
        comptroller = new Comptroller(RewardsInterface(address(compRewards)));

        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        Comptroller(address(unitroller))._setRewardsContract(RewardsInterface(address(compRewards)));
        Comptroller(address(unitroller))._setPriceOracle(PriceOracle(address(priceOracle)));
        Comptroller(address(unitroller))._setCloseFactor(5e17);
        Comptroller(address(unitroller))._setLiquidationIncentive(5e17);

        return address(unitroller);
    }

    function makeJumpRateModel() public returns (address) {
        jumpRateModel = address(new JumpRateModel(1e17, 1e17, 1e17, 5e17));
        return jumpRateModel;
    }
}
