// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Unitroller/Unitroller.sol";
import "contracts/compound/CompRewards/CompRewards.sol";
import "contracts/compound/InterestRateModel/JumpRateModel.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import "contracts/compound/Oracle/PriceOracle.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";

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
        cve = new CVE(admin);
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
