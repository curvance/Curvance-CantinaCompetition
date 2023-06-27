// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/Unitroller/Unitroller.sol";
import "contracts/market/InterestRateModel/JumpRateModelV2.sol";
import "contracts/market/InterestRateModel/InterestRateModel.sol";
import "contracts/market/Oracle/PriceOracle.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/market/Token/CErc20Immutable.sol";
import "contracts/market/Token/CEther.sol";
import "contracts/gauge/GaugeController.sol";

import "tests/market/deploy.sol";
import "tests/utils/TestBase.sol";

contract User {
    receive() external payable {}

    fallback() external payable {}
}

contract TestBaseMarket is TestBase {
    address public DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public E_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    DeployCompound public deployments;

    address public admin;
    address public user;
    address public liquidator;
    address public unitroller;
    address public gauge;

    IERC20 dai;
    CEther public cETH;
    CErc20Immutable public cDAI;

    SimplePriceOracle public priceOracle;

    function setUp() public virtual {
        _fork();

        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(DAI_ADDRESS, _ONE);
        priceOracle.setDirectPrice(E_ADDRESS, _ONE);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        gauge = address(new GaugePool(address(0), address(0), unitroller));

        dai = IERC20(DAI_ADDRESS);
    }

    function _deployCEther() internal {
        cETH = new CEther(
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
    }

    function _deployCDAI() internal {
        cDAI = new CErc20Immutable(
            DAI_ADDRESS,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
    }
}
