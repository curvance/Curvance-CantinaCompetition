// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CErc20Immutable.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import "contracts/mocks/MockToken.sol";
import "contracts/mocks/MockCentralRegistry.sol";
import { veCVE } from "contracts/token/veCVE.sol";
import "contracts/interfaces/ICentralRegistry.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {}

contract TestBoostedLock is DSTestPlus {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public admin;
    DeployCompound public deployments;
    address public unitroller;
    CErc20Immutable public cDAI;
    SimplePriceOracle public priceOracle;

    address public owner;
    address[10] public tokens;
    address public cve;
    veCVE public ve;
    MockCentralRegistry public centralRegistry;
    address[10] public users;
    GaugePool public gaugePool;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, 1e18);
        admin = deployments.admin();

        owner = address(this);

        centralRegistry = new MockCentralRegistry(address(this), 1 weeks, block.chainid);
        cve = address(new MockToken("Reward Token", "RT", 18));
        centralRegistry.setCVE(cve);
        ve = new veCVE(12 weeks, ICentralRegistry(address(centralRegistry)));
        gaugePool = new GaugePool(address(cve), address(ve), unitroller);
        ve.addAuthorizedHelper(address(gaugePool));

        MockToken(cve).approve(address(gaugePool), 1000 ether);

        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(new User());
            hevm.store(
                dai,
                keccak256(abi.encodePacked(uint256(uint160(users[i])), uint256(2))),
                bytes32(uint256(200000e18))
            );
        }

        for (uint256 i = 0; i < 10; i++) {
            tokens[i] = address(
                new CErc20Immutable(
                    dai,
                    ComptrollerInterface(unitroller),
                    address(gaugePool),
                    InterestRateModel(address(deployments.jumpRateModel())),
                    1e18,
                    "cDAI",
                    "cDAI",
                    18,
                    payable(admin)
                )
            );
            // support market
            hevm.prank(admin);
            Comptroller(unitroller)._supportMarket(CToken(tokens[i]));
            // set collateral factor
            hevm.prank(admin);
            Comptroller(unitroller)._setCollateralFactor(CToken(tokens[i]), 5e17);

            for (uint256 j = 0; j < 10; j++) {
                address user = users[j];
                hevm.prank(user);
                address[] memory markets = new address[](1);
                markets[0] = address(tokens[i]);
                ComptrollerInterface(unitroller).enterMarkets(markets);

                // approve
                hevm.prank(user);
                IERC20(dai).approve(address(tokens[i]), 200000e18);
            }

            hevm.deal(users[i], 200000e18);
        }

        hevm.warp(block.timestamp + 1000);
        hevm.roll(block.number + 1000);
    }

    function testBoostedLockFromClaim() public {
        // set reward per sec
        gaugePool.setRewardPerSecOfNextEpoch(0, 300);
        // set gauge weights
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;
        gaugePool.setEmissionRates(0, tokensParam, poolWeights);
        // start epoch
        gaugePool.start();

        // user0 deposit 100 token0
        hevm.prank(users[0]);
        CErc20Immutable(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        hevm.prank(users[2]);
        CErc20Immutable(tokens[1]).mint(100 ether);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 20000);

        // user1 deposit 400 token0
        hevm.prank(users[1]);
        CErc20Immutable(tokens[0]).mint(400 ether);

        // user3 deposit 400 token1
        hevm.prank(users[3]);
        CErc20Immutable(tokens[1]).mint(400 ether);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 12000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 24000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);

        // user0, user3 claims
        hevm.prank(users[0]);
        gaugePool.claimAndLock(tokens[0], false);
        hevm.prank(users[3]);
        gaugePool.claimAndLock(tokens[1], false);
        assertEq(ve.balanceOf(users[0]), 12000);
        assertEq(ve.balanceOf(users[3]), 16000);
        assertEq(ve.getVotes(users[0]), 11538);
        assertEq(ve.getVotes(users[3]), 15384);

        hevm.warp(block.timestamp + 2 weeks);

        // user0, user3 claims
        hevm.prank(users[0]);
        gaugePool.claimAndExtendLock(tokens[0], 0, true);
        hevm.prank(users[3]);
        gaugePool.claimAndExtendLock(tokens[1], 0, false);
        assertEq(ve.balanceOf(users[0]), 24204000);
        assertEq(ve.balanceOf(users[3]), 193552000);
        assertEq(ve.getVotes(users[0]), 13200);
        assertEq(ve.getVotes(users[3]), 15384);

        hevm.warp(block.timestamp + 2 weeks);
        assertEq(ve.balanceOf(users[0]), 24204000);
        assertEq(ve.balanceOf(users[3]), 193552000);
        assertEq(ve.getVotes(users[0]), 13200);
        assertEq(ve.getVotes(users[3]), 14769);
    }
}
