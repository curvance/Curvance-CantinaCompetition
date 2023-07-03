// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/lendtroller/LendtrollerInterface.sol";
import "contracts/token/collateral/CErc20.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/market/interestRates/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { ChildGaugePool } from "contracts/gauge/ChildGaugePool.sol";
import "contracts/mocks/MockToken.sol";

import { DeployCompound } from "tests/market/deploy.sol";
import "tests/utils/TestBase.sol";

contract User {}

contract TestChildGaugePool is TestBase {
    uint256 constant CHILD_GAUGE_COUNT = 5;

    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public admin;
    DeployCompound public deployments;
    address public unitroller;
    CErc20 public cDAI;
    SimplePriceOracle public priceOracle;

    address public owner;
    address[10] public tokens;
    address public rewardToken;
    ChildGaugePool[5] public childGauges;
    address[5] public childRewardTokens;
    address[10] public users;
    GaugePool public gaugePool;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        _fork();

        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, _ONE);
        admin = deployments.admin();

        owner = address(this);

        rewardToken = address(new MockToken("Reward Token", "RT", 18));
        gaugePool = new GaugePool(
            address(rewardToken),
            address(0),
            unitroller
        );
        MockToken(rewardToken).approve(address(gaugePool), 1000 ether);

        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            childRewardTokens[i] = address(
                new MockToken("Reward Token", "RT", 18)
            );
            childGauges[i] = new ChildGaugePool(
                address(gaugePool),
                childRewardTokens[i]
            );
            MockToken(childRewardTokens[i]).approve(
                address(childGauges[i]),
                1000 ether
            );

            gaugePool.addChildGauge(address(childGauges[i]));
        }

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
                    LendtrollerInterface(unitroller),
                    address(gaugePool),
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
            Lendtroller(unitroller)._supportMarket(CToken(tokens[i]));
            // set collateral factor
            vm.prank(admin);
            Lendtroller(unitroller)._setCollateralFactor(
                CToken(tokens[i]),
                5e17
            );

            for (uint256 j = 0; j < 10; j++) {
                address user = users[j];
                vm.prank(user);
                address[] memory markets = new address[](1);
                markets[0] = address(tokens[i]);
                LendtrollerInterface(unitroller).enterMarkets(markets);

                // approve
                vm.prank(user);
                IERC20(dai).approve(address(tokens[i]), 200000e18);
            }

            vm.deal(users[i], 200000e18);
        }

        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 1000);
    }

    function testChildGaugesRewardRatioOfDifferentPools() public {
        // set reward per sec
        gaugePool.setRewardPerSecOfNextEpoch(0, 300);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            childGauges[i].setRewardPerSec(0, 300);
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                childGauges[i].pendingRewards(tokens[0], users[0]),
                10000
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[2]),
                20000
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                childGauges[i].pendingRewards(tokens[0], users[0]),
                12000
            );
            assertEq(childGauges[i].pendingRewards(tokens[0], users[1]), 8000);
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[2]),
                24000
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[3]),
                16000
            );
        }

        // user0, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            vm.prank(users[0]);
            childGauges[i].claim(tokens[0]);
            vm.prank(users[3]);
            childGauges[i].claim(tokens[1]);
        }
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 12000);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 16000);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[0]),
                12000
            );
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[3]),
                16000
            );
        }

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 2000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 16000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 28000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(childGauges[i].pendingRewards(tokens[0], users[0]), 2000);
            assertEq(
                childGauges[i].pendingRewards(tokens[0], users[1]),
                16000
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[2]),
                28000
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[3]),
                16000
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(childGauges[i].pendingRewards(tokens[0], users[0]), 3111);
            assertEq(
                childGauges[i].pendingRewards(tokens[0], users[1]),
                24888
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[2]),
                34666
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[3]),
                29333
            );
        }

        // user0, user1, user2, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[2]);
        gaugePool.claim(tokens[1]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            vm.prank(users[0]);
            childGauges[i].claim(tokens[0]);
            vm.prank(users[1]);
            childGauges[i].claim(tokens[0]);
            vm.prank(users[2]);
            childGauges[i].claim(tokens[1]);
            vm.prank(users[3]);
            childGauges[i].claim(tokens[1]);
        }
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 15111);
        assertEq(MockToken(rewardToken).balanceOf(users[1]), 24888);
        assertEq(MockToken(rewardToken).balanceOf(users[2]), 34666);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 45333);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[0]),
                15111
            );
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[1]),
                24888
            );
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[2]),
                34666
            );
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[3]),
                45333
            );
        }

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 1111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8889);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 6667);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 13333);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(childGauges[i].pendingRewards(tokens[0], users[0]), 1111);
            assertEq(childGauges[i].pendingRewards(tokens[0], users[1]), 8889);
            assertEq(childGauges[i].pendingRewards(tokens[1], users[2]), 6667);
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[3]),
                13333
            );
        }
    }

    function testChildGaugesRewardCalculationWithDifferentEpoch() public {
        // set reward per sec
        gaugePool.setRewardPerSecOfNextEpoch(0, 300);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            childGauges[i].setRewardPerSec(0, 300);
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                childGauges[i].pendingRewards(tokens[0], users[0]),
                10000
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[1]),
                20000
            );
        }

        // set next epoch reward per second
        gaugePool.setRewardPerSecOfNextEpoch(1, 400);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            childGauges[i].setRewardPerSec(1, 400);
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                childGauges[i].pendingRewards(tokens[0], users[0]),
                2 weeks * 100 + 100 * 200
            );
            assertEq(
                childGauges[i].pendingRewards(tokens[1], users[1]),
                2 weeks * 200 + 100 * 200
            );
        }

        // user0, user1 claim rewards
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[1]);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            vm.prank(users[0]);
            childGauges[i].claim(tokens[0]);
            vm.prank(users[1]);
            childGauges[i].claim(tokens[1]);
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[0]),
                2 weeks * 100 + 100 * 200
            );
            assertEq(
                MockToken(childRewardTokens[i]).balanceOf(users[1]),
                2 weeks * 200 + 100 * 200
            );
            assertEq(childGauges[i].pendingRewards(tokens[0], users[0]), 0);
            assertEq(childGauges[i].pendingRewards(tokens[1], users[1]), 0);
        }
    }
}
