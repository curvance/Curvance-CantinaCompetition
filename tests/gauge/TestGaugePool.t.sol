// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/lendtroller/LendtrollerInterface.sol";
import "contracts/market/collateral/CErc20.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/market/interestRates/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import "contracts/gauge/GaugeErrors.sol";
import "contracts/mocks/MockToken.sol";

import { DeployCompound } from "tests/market/deploy.sol";
import "tests/utils/TestBase.sol";

contract User {}

contract TestGaugePool is TestBase {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public admin;
    DeployCompound public deployments;
    address public lendtroller;
    CErc20 public cDAI;
    SimplePriceOracle public priceOracle;

    address public owner;
    address[10] public tokens;
    address public rewardToken;
    address[10] public users;
    GaugePool public gaugePool;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        _fork();

        deployments = new DeployCompound();
        deployments.makeCompound();
        lendtroller = address(deployments.lendtroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, _ONE);
        admin = deployments.admin();

        owner = address(this);

        rewardToken = address(new MockToken("Reward Token", "RT", 18));
        gaugePool = new GaugePool(
            address(rewardToken),
            address(0),
            lendtroller
        );

        MockToken(rewardToken).approve(address(gaugePool), 1000 ether);

        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(new User());
            vm.store(
                dai,
                keccak256(
                    abi.encodePacked(uint256(uint160(users[i])), uint256(2))
                ),
                bytes32(uint256(200000e18))
            );
        }
        for (uint256 i = 0; i < 10; i++) {
            tokens[i] = address(
                new CErc20(
                    dai,
                    lendtroller,
                    InterestRateModel(address(deployments.jumpRateModel())),
                    _ONE,
                    "cDAI",
                    "cDAI",
                    18,
                    payable(admin)
                )
            );
            // support market
            vm.prank(admin);
            Lendtroller(lendtroller)._supportMarket(CToken(tokens[i]));
            // set collateral factor
            vm.prank(admin);
            Lendtroller(lendtroller)._setCollateralFactor(
                CToken(tokens[i]),
                5e17
            );

            for (uint256 j = 0; j < 10; j++) {
                address user = users[j];
                vm.prank(user);
                address[] memory markets = new address[](1);
                markets[0] = address(tokens[i]);
                LendtrollerInterface(lendtroller).enterMarkets(markets);

                // approve
                vm.prank(user);
                IERC20(dai).approve(address(tokens[i]), 200000e18);
            }

            vm.deal(users[i], 200000e18);
        }

        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 1000);
    }

    function testManageEmissionRatesOfEachEpoch() public {
        // set reward per sec
        assertEq(gaugePool.rewardPerSec(0), 0);

        gaugePool.setRewardPerSecOfNextEpoch(0, 1000);

        assertEq(gaugePool.rewardPerSec(0), 1000);

        // set gauge weights
        assertTrue(gaugePool.isGaugeEnabled(0, tokens[0]) == false);
        (uint256 totalWeights, uint256 poolWeight) = gaugePool.gaugeWeight(
            0,
            tokens[0]
        );
        assertEq(totalWeights, 0);
        assertEq(poolWeight, 0);

        address[] memory tokensParam = new address[](1);
        tokensParam[0] = tokens[0];
        uint256[] memory poolWeights = new uint256[](1);
        poolWeights[0] = 100;
        gaugePool.setEmissionRates(0, tokensParam, poolWeights);

        assertTrue(gaugePool.isGaugeEnabled(0, tokens[0]) == true);
        (totalWeights, poolWeight) = gaugePool.gaugeWeight(0, tokens[0]);
        assertEq(totalWeights, 100);
        assertEq(poolWeight, 100);

        // start epoch
        gaugePool.start();

        assertEq(gaugePool.currentEpoch(), 0);
        assertEq(gaugePool.epochOfTimestamp(block.timestamp + 3 weeks), 1);
        assertEq(gaugePool.epochStartTime(1), block.timestamp + 2 weeks);
        assertEq(gaugePool.epochEndTime(1), block.timestamp + 4 weeks);

        // set gauge settings of next epoch
        gaugePool.setRewardPerSecOfNextEpoch(1, 2000);
        tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);

        (totalWeights, poolWeight) = gaugePool.gaugeWeight(1, tokens[0]);
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 100);
        (totalWeights, poolWeight) = gaugePool.gaugeWeight(1, tokens[1]);
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 200);
    }

    function testCanOnlyUpdateEmissionRatesOfNextEpoch() public {
        // set reward per sec
        assertEq(gaugePool.rewardPerSec(0), 0);

        gaugePool.setRewardPerSecOfNextEpoch(0, 1000);

        assertEq(gaugePool.rewardPerSec(0), 1000);

        // set gauge weights
        assertTrue(gaugePool.isGaugeEnabled(0, tokens[0]) == false);
        (uint256 totalWeights, uint256 poolWeight) = gaugePool.gaugeWeight(
            0,
            tokens[0]
        );
        assertEq(totalWeights, 0);
        assertEq(poolWeight, 0);

        address[] memory tokensParam = new address[](1);
        tokensParam[0] = tokens[0];
        uint256[] memory poolWeights = new uint256[](1);
        poolWeights[0] = 100;
        gaugePool.setEmissionRates(0, tokensParam, poolWeights);

        assertTrue(gaugePool.isGaugeEnabled(0, tokens[0]) == true);
        (totalWeights, poolWeight) = gaugePool.gaugeWeight(0, tokens[0]);
        assertEq(totalWeights, 100);
        assertEq(poolWeight, 100);

        // start epoch
        gaugePool.start();

        assertEq(gaugePool.currentEpoch(), 0);
        assertEq(gaugePool.epochOfTimestamp(block.timestamp + 3 weeks), 1);
        assertEq(gaugePool.epochStartTime(1), block.timestamp + 2 weeks);
        assertEq(gaugePool.epochEndTime(1), block.timestamp + 4 weeks);

        // check invalid epoch
        vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
        gaugePool.setRewardPerSecOfNextEpoch(0, 1000);
        vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
        gaugePool.setRewardPerSecOfNextEpoch(2, 1000);

        // set gauge settings of next epoch
        gaugePool.setRewardPerSecOfNextEpoch(1, 2000);

        tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;

        // check invalid epoch
        vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
        gaugePool.setEmissionRates(0, tokensParam, poolWeights);
        vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
        gaugePool.setEmissionRates(2, tokensParam, poolWeights);

        // can update emission rate of next epoch
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);

        (totalWeights, poolWeight) = gaugePool.gaugeWeight(1, tokens[0]);
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 100);
        (totalWeights, poolWeight) = gaugePool.gaugeWeight(1, tokens[1]);
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 200);
    }

    function testRewardRatioOfDifferentPools() public {
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
        vm.prank(users[0]);
        CErc20(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        CErc20(tokens[1]).mint(100 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 20000);

        // user1 deposit 400 token0
        vm.prank(users[1]);
        CErc20(tokens[0]).mint(400 ether);

        // user3 deposit 400 token1
        vm.prank(users[3]);
        CErc20(tokens[1]).mint(400 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 12000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 24000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);

        // user0, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 12000);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 16000);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 2000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 16000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 28000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);

        // user0 withdraw half
        vm.prank(users[0]);
        CErc20(tokens[0]).redeem(50 ether);

        // user2 deposit 2x
        vm.prank(users[2]);
        CErc20(tokens[1]).mint(100 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 3111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 24888);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 34666);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 29333);

        // user0, user1, user2, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[2]);
        gaugePool.claim(tokens[1]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 15111);
        assertEq(MockToken(rewardToken).balanceOf(users[1]), 24888);
        assertEq(MockToken(rewardToken).balanceOf(users[2]), 34666);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 45333);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 1111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8889);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 6667);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 13333);
    }

    function testRewardCalculationWithDifferentEpoch() public {
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
        vm.prank(users[0]);
        CErc20(tokens[0]).mint(100 ether);

        // user1 deposit 100 token1
        vm.prank(users[1]);
        CErc20(tokens[1]).mint(100 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[1]), 20000);

        // set next epoch reward per second
        gaugePool.setRewardPerSecOfNextEpoch(1, 400);
        // set gauge weights
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        poolWeights[0] = 200;
        poolWeights[1] = 200;
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);

        // check pending rewards after 2 weeks
        vm.warp(block.timestamp + 2 weeks);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0]),
            2 weeks * 100 + 100 * 200
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[1]),
            2 weeks * 200 + 100 * 200
        );

        // user0, user1 claim rewards
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[1]);

        assertEq(
            MockToken(rewardToken).balanceOf(users[0]),
            2 weeks * 100 + 100 * 200
        );
        assertEq(
            MockToken(rewardToken).balanceOf(users[1]),
            2 weeks * 200 + 100 * 200
        );
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 0);
        assertEq(gaugePool.pendingRewards(tokens[1], users[1]), 0);
    }

    function testUpdatePoolDoesNotMessUpTheRewardCalculation() public {
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
        vm.prank(users[0]);
        CErc20(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        CErc20(tokens[1]).mint(100 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 20000);

        // user1 deposit 400 token0
        vm.prank(users[1]);
        CErc20(tokens[0]).mint(400 ether);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // user3 deposit 400 token1
        vm.prank(users[3]);
        CErc20(tokens[1]).mint(400 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 12000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 24000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // user0, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 12000);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 16000);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 2000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 16000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 28000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);

        // user0 withdraw half
        vm.prank(users[0]);
        CErc20(tokens[0]).redeem(50 ether);

        // user2 deposit 2x
        vm.prank(users[2]);
        CErc20(tokens[1]).mint(100 ether);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 3111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 24888);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 34666);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 29333);

        // user0, user1, user2, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[2]);
        gaugePool.claim(tokens[1]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 15111);
        assertEq(MockToken(rewardToken).balanceOf(users[1]), 24888);
        assertEq(MockToken(rewardToken).balanceOf(users[2]), 34666);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 45333);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 1111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8889);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 6667);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 13333);
    }
}
