// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/compound/Comptroller.sol";
import "contracts/compound/CErc20Immutable.sol";
import "contracts/compound/Errors.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/interfaces/IComptroller.sol";
import "contracts/compound/interfaces/InterestRateModel.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";

contract User {}

contract TestCErc20Immutable is DSTestPlus {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public user;
    address public admin;
    DeployCompound public deployments;
    address public unitroller;
    CErc20Immutable public cDAI;

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());

        admin = deployments.admin();
        user = address(this);

        // prepare 200K DAI
        hevm.store(dai, keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))), bytes32(uint256(200000e18)));
        emit log_named_uint("Dai balanceOf ", IERC20(dai).balanceOf(user));
    }

    function testInitialize() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
    }

    function testMint() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertGt(cDAI.balanceOf(user), 0);
    }
}
