// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/gauge/GaugePool.sol";
import "contracts/mocks/MockToken.sol";

import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {}

contract TestGaugePool is DSTestPlus {
    address public owner;
    address[10] public tokens;
    address public rewardToken;
    address[10] public users;
    GaugePool public gaugePool;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        owner = address(this);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(new User());
        }
        for (uint256 i = 0; i < 10; i++) {
            tokens[i] = address(new MockToken("Mock Token", "MT", 18));
            for (uint256 j = 0; j < 10; j++) {
                MockToken(tokens[i]).transfer(users[j], 1000000 ether);
            }

            hevm.deal(users[i], 200000e18);
        }

        rewardToken = address(new MockToken("Reward Token", "RT", 18));
        gaugePool = new GaugePool(address(rewardToken));

        MockToken(rewardToken).transfer(address(gaugePool), 1000 ether);

        hevm.warp(block.timestamp + 1000);
        hevm.roll(block.number + 1000);
    }

    function testManageEmissionRatesOfEachEpoch() public {
        // set reward per sec
        assertEq(gaugePool.rewardPerSec(0), 0);

        gaugePool.setRewardPerSecOfNextEpoch(0, 1000);

        assertEq(gaugePool.rewardPerSec(0), 1000);

        // set gauge allocations
        assertTrue(gaugePool.isGaugeEnabled(0, tokens[0]) == false);
        (uint256 totalAllocation, uint256 poolAllocation) = gaugePool.gaugePoolAllocation(0, tokens[0]);
        assertEq(totalAllocation, 0);
        assertEq(poolAllocation, 0);

        address[] memory tokensParam = new address[](1);
        tokensParam[0] = tokens[0];
        uint256[] memory allocPoints = new uint256[](1);
        allocPoints[0] = 100;
        gaugePool.setEmissionRates(0, tokensParam, allocPoints);

        assertTrue(gaugePool.isGaugeEnabled(0, tokens[0]) == true);
        (totalAllocation, poolAllocation) = gaugePool.gaugePoolAllocation(0, tokens[0]);
        assertEq(totalAllocation, 100);
        assertEq(poolAllocation, 100);

        // start epoch
        gaugePool.start();

        assertEq(gaugePool.currentEpoch(), 0);
        assertEq(gaugePool.epochOfTimestamp(block.timestamp + 5 weeks), 1);
        assertEq(gaugePool.epochStartTime(1), block.timestamp + 4 weeks);
        assertEq(gaugePool.epochEndTime(1), block.timestamp + 8 weeks);

        // set gauge settings of next epoch
        gaugePool.setRewardPerSecOfNextEpoch(1, 2000);
        tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        allocPoints = new uint256[](2);
        allocPoints[0] = 100;
        allocPoints[1] = 200;
        gaugePool.setEmissionRates(1, tokensParam, allocPoints);

        (totalAllocation, poolAllocation) = gaugePool.gaugePoolAllocation(1, tokens[0]);
        assertEq(totalAllocation, 300);
        assertEq(poolAllocation, 100);
        (totalAllocation, poolAllocation) = gaugePool.gaugePoolAllocation(1, tokens[1]);
        assertEq(totalAllocation, 300);
        assertEq(poolAllocation, 200);
    }

    function testRewardRatioOfDifferentPools() public {
        // set reward per sec
        gaugePool.setRewardPerSecOfNextEpoch(0, 300);
        // set gauge allocations
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory allocPoints = new uint256[](2);
        allocPoints[0] = 100;
        allocPoints[1] = 200;
        gaugePool.setEmissionRates(0, tokensParam, allocPoints);
        // start epoch
        gaugePool.start();

        // user0 deposit 100 token0
        hevm.prank(users[0]);
        MockToken(tokens[0]).approve(address(gaugePool), 100 ether);
        hevm.prank(users[0]);
        gaugePool.deposit(tokens[0], 100 ether, users[0]);

        // user2 deposit 100 token1
        hevm.prank(users[2]);
        MockToken(tokens[1]).approve(address(gaugePool), 100 ether);
        hevm.prank(users[2]);
        gaugePool.deposit(tokens[1], 100 ether, users[2]);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 20000);

        // user1 deposit 400 token0
        hevm.prank(users[1]);
        MockToken(tokens[0]).approve(address(gaugePool), 400 ether);
        hevm.prank(users[1]);
        gaugePool.deposit(tokens[0], 400 ether, users[1]);

        // user3 deposit 400 token1
        hevm.prank(users[3]);
        MockToken(tokens[1]).approve(address(gaugePool), 400 ether);
        hevm.prank(users[3]);
        gaugePool.deposit(tokens[1], 400 ether, users[3]);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 12000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 24000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);
    }
}
