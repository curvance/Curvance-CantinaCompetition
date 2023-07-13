// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/interestRates/JumpRateModelV2.sol";
import "contracts/market/interestRates/InterestRateModel.sol";
import "contracts/market/Oracle/PriceOracle.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/market/collateral/CErc20.sol";
import "contracts/market/collateral/CEther.sol";
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
    address public lendtroller;
    address public gauge;

    IERC20 dai;
    CEther public cETH;
    CErc20 public cDAI;

    SimplePriceOracle public priceOracle;

    function setUp() public virtual {
        _fork();

        deployments = new DeployCompound();
        deployments.makeCompound();
        lendtroller = address(deployments.lendtroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(DAI_ADDRESS, _ONE);
        priceOracle.setDirectPrice(E_ADDRESS, _ONE);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        gauge = address(new GaugePool(address(0), address(0), lendtroller));

        dai = IERC20(DAI_ADDRESS);
    }

    function _deployCEther() internal {
        cETH = new CEther(
            lendtroller,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
    }

    function _deployCDAI() internal {
        cDAI = new CErc20(
            DAI_ADDRESS,
            lendtroller,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
    }

    function _setupCEtherMarket() internal {
        vm.startPrank(admin);
        Lendtroller(lendtroller)._supportMarket(CToken(address(cETH)));
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cETH)),
            5e17
        );
        vm.stopPrank();
    }

    function _setupCDAIMarket() internal {
        vm.startPrank(admin);
        Lendtroller(lendtroller)._supportMarket(CToken(address(cDAI)));
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cDAI)),
            5e17
        );
        vm.stopPrank();
    }

    function _enterCEtherMarket(address user_) internal {
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);

        vm.prank(user_);
        ILendtroller(lendtroller).enterMarkets(markets);
    }

    function _enterCDAIMarket(address user_) internal {
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);

        vm.prank(user_);
        ILendtroller(lendtroller).enterMarkets(markets);
    }

    function _enterMarkets(address user_) internal {
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);

        vm.prank(user_);
        ILendtroller(lendtroller).enterMarkets(markets);
    }
}