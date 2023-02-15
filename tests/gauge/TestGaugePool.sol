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

    function testCanOnlyUpdateEmissionRatesOfNextEpoch() public {
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

        // check invalid epoch
        hevm.expectRevert(bytes4(keccak256("InvalidEpoch()")));
        gaugePool.setRewardPerSecOfNextEpoch(0, 1000);
        hevm.expectRevert(bytes4(keccak256("InvalidEpoch()")));
        gaugePool.setRewardPerSecOfNextEpoch(2, 1000);

        // set gauge settings of next epoch
        gaugePool.setRewardPerSecOfNextEpoch(1, 2000);
        
        tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        allocPoints = new uint256[](2);
        allocPoints[0] = 100;
        allocPoints[1] = 200;

        // check invalid epoch
        hevm.expectRevert(bytes4(keccak256("InvalidEpoch()")));
        gaugePool.setEmissionRates(0, tokensParam, allocPoints);
        hevm.expectRevert(bytes4(keccak256("InvalidEpoch()")));
        gaugePool.setEmissionRates(2, tokensParam, allocPoints);
        
        // can update emission rate of next epoch
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

        // user0, user3 claims
        hevm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        hevm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 12000);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 16000);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 2000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 16000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 28000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);

        // user0 withdraw half
        hevm.prank(users[0]);
        gaugePool.withdraw(tokens[0], 50 ether, users[0]);

        // user2 deposit 2x
        hevm.prank(users[2]);
        MockToken(tokens[1]).approve(address(gaugePool), 100 ether);
        hevm.prank(users[2]);
        gaugePool.deposit(tokens[1], 100 ether, users[2]);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 3111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 24888);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 34666);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 29333);

        // user0, user1, user2, user3 claims
        hevm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        hevm.prank(users[1]);
        gaugePool.claim(tokens[0]);
        hevm.prank(users[2]);
        gaugePool.claim(tokens[1]);
        hevm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 15111);
        assertEq(MockToken(rewardToken).balanceOf(users[1]), 24888);
        assertEq(MockToken(rewardToken).balanceOf(users[2]), 34666);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 45333);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 1111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8889);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 6667);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 13333);
    }

    function testRewardCalculationWithDifferentEpoch() public {
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

        // user1 deposit 100 token1
        hevm.prank(users[1]);
        MockToken(tokens[1]).approve(address(gaugePool), 100 ether);
        hevm.prank(users[1]);
        gaugePool.deposit(tokens[1], 100 ether, users[1]);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[1]), 20000);

        // set next epoch reward allocation
        gaugePool.setRewardPerSecOfNextEpoch(1, 400);
        // set gauge allocations
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        allocPoints[0] = 200;
        allocPoints[1] = 200;
        gaugePool.setEmissionRates(1, tokensParam, allocPoints);

        // check pending rewards after 4 weeks
        hevm.warp(block.timestamp + 4 weeks);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 4 weeks * 100 + 100 * 200);
        assertEq(gaugePool.pendingRewards(tokens[1], users[1]), 4 weeks * 200 + 100 * 200);

        // user0, user1 claim rewards
        hevm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        hevm.prank(users[1]);
        gaugePool.claim(tokens[1]);

        assertEq(MockToken(rewardToken).balanceOf(users[0]), 4 weeks * 100 + 100 * 200);
        assertEq(MockToken(rewardToken).balanceOf(users[1]), 4 weeks * 200 + 100 * 200);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 0);
        assertEq(gaugePool.pendingRewards(tokens[1], users[1]), 0);
    }

    function testUpdatePoolDoesNotMessUpTheRewardCalculation() public {
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
        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 20000);

        // user1 deposit 400 token0
        hevm.prank(users[1]);
        MockToken(tokens[0]).approve(address(gaugePool), 400 ether);
        hevm.prank(users[1]);
        gaugePool.deposit(tokens[0], 400 ether, users[1]);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

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

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // user0, user3 claims
        hevm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        hevm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 12000);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 16000);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 2000);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 16000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 28000);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000);

        // user0 withdraw half
        hevm.prank(users[0]);
        gaugePool.withdraw(tokens[0], 50 ether, users[0]);

        // user2 deposit 2x
        hevm.prank(users[2]);
        MockToken(tokens[1]).approve(address(gaugePool), 100 ether);
        hevm.prank(users[2]);
        gaugePool.deposit(tokens[1], 100 ether, users[2]);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 3111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 24888);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 34666);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 29333);

        // user0, user1, user2, user3 claims
        hevm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        hevm.prank(users[1]);
        gaugePool.claim(tokens[0]);
        hevm.prank(users[2]);
        gaugePool.claim(tokens[1]);
        hevm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(MockToken(rewardToken).balanceOf(users[0]), 15111);
        assertEq(MockToken(rewardToken).balanceOf(users[1]), 24888);
        assertEq(MockToken(rewardToken).balanceOf(users[2]), 34666);
        assertEq(MockToken(rewardToken).balanceOf(users[3]), 45333);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // check pending rewards after 100 seconds
        hevm.warp(block.timestamp + 100);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 1111);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8889);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 6667);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 13333);
    }
}
