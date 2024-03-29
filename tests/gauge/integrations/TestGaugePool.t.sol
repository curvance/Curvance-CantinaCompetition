// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";

contract User {}

contract TestGaugePool is TestBaseMarket {
    address public owner;
    address[] public tokens;
    address[] public users;

    MockDataFeed public mockDaiFeed;

    function setUp() public override {
        super.setUp();
        tokens = new address[](10);
        users = new address[](10);

        // prepare 200K USDC
        _prepareUSDC(user1, 200000e6);
        _prepareUSDC(user2, 200000e6);
        _prepareUSDC(liquidator, 200000e6);

        // prepare 1 BAL-RETH/WETH
        _prepareBALRETH(user1, 1 ether);
        _prepareBALRETH(user2, 1 ether);
        _prepareBALRETH(liquidator, 1 ether);

        owner = address(this);

        _prepareDAI(owner, 200000e18);

        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(new User());
            _prepareDAI(users[i], 200000e18);
        }

        address[] memory tokensParam = new address[](1);
        tokensParam[0] = tokens[0];
        uint256[] memory poolWeights = new uint256[](1);
        poolWeights[0] = 100;

        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(0, tokensParam, poolWeights);

        // start epoch
        gaugePool.start(address(marketManager));

        for (uint256 i = 0; i < 10; i++) {
            tokens[i] = address(_deployDDAI());

            // support market
            dai.approve(address(tokens[i]), 200000e18);
            marketManager.listToken(tokens[i]);

            // add MToken support on price router
            oracleRouter.addMTokenSupport(tokens[i]);

            for (uint256 j = 0; j < 10; j++) {
                address user = users[j];

                // approve
                vm.prank(user);
                dai.approve(address(tokens[i]), 200000e18);
            }

            // sort token addresses
            for (uint256 j = i; j > 0; j--) {
                if (tokens[j] < tokens[j - 1]) {
                    address temp = tokens[j];
                    tokens[j] = tokens[j - 1];
                    tokens[j - 1] = temp;
                }
            }
        }

        mockDaiFeed = new MockDataFeed(_CHAINLINK_DAI_USD);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, address(mockDaiFeed), 0, true);
    }

    function testRevertSetEmissionRatesUnauthorized() public {
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge settings of next epoch
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;

        vm.expectRevert(GaugeErrors.Unauthorized.selector);
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
    }

    function testRevertSetEmissionRatesInvalidEpoch() public {
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge settings of next epoch
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;

        vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(2, tokensParam, poolWeights);
    }

    function testRevertSetEmissionRatesInvalidLength() public {
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge settings of next epoch
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](1);
        poolWeights[0] = 100;

        vm.expectRevert(GaugeErrors.InvalidLength.selector);
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
    }

    function testRevertSetEmissionRatesInvalidToken() public {
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge settings of next epoch
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[1];
        tokensParam[1] = tokens[0];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;

        vm.expectRevert(GaugeErrors.InvalidToken.selector);
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
    }

    function testIsGaugeEnabled() public {
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge settings of next epoch
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;

        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);

        assertEq(gaugePool.isGaugeEnabled(1, tokens[0]), true);
        assertEq(gaugePool.isGaugeEnabled(1, tokens[2]), false);
    }

    function testManageEmissionRatesOfEachEpoch() public {
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        assertEq(gaugePool.currentEpoch(), 0);
        assertEq(gaugePool.epochOfTimestamp(block.timestamp + 3 weeks), 1);
        assertEq(gaugePool.epochStartTime(1), block.timestamp + 2 weeks);
        assertEq(gaugePool.epochEndTime(1), block.timestamp + 4 weeks);

        // set gauge settings of next epoch
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);

        (uint256 totalWeights, uint256 poolWeight) = gaugePool.gaugeWeight(
            1,
            tokens[0]
        );
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 100);
        (totalWeights, poolWeight) = gaugePool.gaugeWeight(1, tokens[1]);
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 200);
    }

    function testCanOnlyUpdateEmissionRatesOfNextEpoch() public {
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        assertEq(gaugePool.currentEpoch(), 0);
        assertEq(gaugePool.epochOfTimestamp(block.timestamp + 3 weeks), 1);
        assertEq(gaugePool.epochStartTime(1), block.timestamp + 2 weeks);
        assertEq(gaugePool.epochEndTime(1), block.timestamp + 4 weeks);

        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 200;

        // check invalid epoch
        vm.prank(address(protocolMessagingHub));
        vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
        gaugePool.setEmissionRates(0, tokensParam, poolWeights);
        vm.prank(address(protocolMessagingHub));
        vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
        gaugePool.setEmissionRates(2, tokensParam, poolWeights);

        // can update emission rate of next epoch
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);

        (uint256 totalWeights, uint256 poolWeight) = gaugePool.gaugeWeight(
            1,
            tokens[0]
        );
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 100);
        (totalWeights, poolWeight) = gaugePool.gaugeWeight(1, tokens[1]);
        assertEq(totalWeights, 300);
        assertEq(poolWeight, 200);
    }

    function testRevertDepositInvalidToken() public {
        vm.expectRevert(GaugeErrors.InvalidToken.selector);
        gaugePool.deposit(tokens[0], address(this), 100 ether);

        vm.expectRevert(GaugeErrors.InvalidToken.selector);
        gaugePool.withdraw(tokens[0], address(this), 100 ether);
    }

    function testRevertClaim() public {
        vm.warp(gaugePool.startTime() - 1);

        vm.expectRevert(GaugeErrors.NotStarted.selector);
        vm.prank(users[0]);
        gaugePool.claim(address(cve));

        vm.warp(gaugePool.startTime());
        vm.expectRevert(GaugeErrors.NoReward.selector);
        vm.prank(users[0]);
        gaugePool.claim(address(cve));
    }

    function testRewardRatioOfDifferentPools() public {
        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge weights
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100 * 2 weeks;
        poolWeights[1] = 200 * 2 weeks;
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
        vm.prank(address(protocolMessagingHub));
        cve.mintGaugeEmissions(address(gaugePool), 300 * 2 weeks);

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            10000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            20000
        );

        // user1 deposit 400 token0
        vm.prank(users[1]);
        IMToken(tokens[0]).mint(400 ether);

        // user3 deposit 400 token1
        vm.prank(users[3]);
        IMToken(tokens[1]).mint(400 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            12000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            8000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            24000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            16000
        );

        // user0, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(cve.balanceOf(users[0]), 12000);
        assertEq(cve.balanceOf(users[3]), 16000);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            2000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            16000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            28000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            16000
        );

        // user0 withdraw half
        vm.prank(users[0]);
        IMToken(tokens[0]).redeem(50 ether);

        // user2 deposit 2x
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            3111
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            24888
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            34666
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            29333
        );

        // user0, user1, user2, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[2]);
        gaugePool.claim(tokens[1]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(cve.balanceOf(users[0]), 15111);
        assertEq(cve.balanceOf(users[1]), 24888);
        assertEq(cve.balanceOf(users[2]), 34666);
        assertEq(cve.balanceOf(users[3]), 45333);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            1111
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            8889
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            6667
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            13333
        );
    }

    function testRewardCalculationWithDifferentEpoch() public {
        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user1 deposit 100 token1
        vm.prank(users[1]);
        IMToken(tokens[1]).mint(100 ether);

        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge weights
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100 * 2 weeks;
        poolWeights[1] = 200 * 2 weeks;
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
        vm.prank(address(protocolMessagingHub));
        cve.mintGaugeEmissions(address(gaugePool), 300 * 2 weeks);

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            10000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[1], address(cve)),
            20000
        );

        // set gauge weights
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        poolWeights[0] = 200 * 2 weeks;
        poolWeights[1] = 200 * 2 weeks;
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(2, tokensParam, poolWeights);
        vm.prank(address(protocolMessagingHub));
        cve.mintGaugeEmissions(address(gaugePool), 400 * 2 weeks);

        // check pending rewards after 2 weeks
        vm.warp(block.timestamp + 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            2 weeks * 100 + 100 * 200
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[1], address(cve)),
            2 weeks * 200 + 100 * 200
        );

        // user0, user1 claim rewards
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[1]);

        assertEq(cve.balanceOf(users[0]), 2 weeks * 100 + 100 * 200);
        assertEq(cve.balanceOf(users[1]), 2 weeks * 200 + 100 * 200);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            0
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[1], address(cve)),
            0
        );
    }

    function testMassUpdatePoolDoesNotMessUpTheRewardCalculation() public {
        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge weights
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100 * 2 weeks;
        poolWeights[1] = 200 * 2 weeks;
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
        vm.prank(address(protocolMessagingHub));
        cve.mintGaugeEmissions(address(gaugePool), 300 * 2 weeks);

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        gaugePool.massUpdatePools(tokensParam);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            10000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            20000
        );
    }

    function testPendingRewardsReturnsAllRewards() public {
        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge weights
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100 * 2 weeks;
        poolWeights[1] = 200 * 2 weeks;
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
        vm.prank(address(protocolMessagingHub));
        cve.mintGaugeEmissions(address(gaugePool), 300 * 2 weeks);

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        gaugePool.massUpdatePools(tokensParam);
        uint256[] memory rewards = gaugePool.pendingRewards(
            tokens[0],
            users[0]
        );
        assertEq(rewards[0], 10000);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            10000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            20000
        );
    }

    function testUpdatePoolDoesNotMessUpTheRewardCalculation() public {
        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge weights
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = tokens[0];
        tokensParam[1] = tokens[1];
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100 * 2 weeks;
        poolWeights[1] = 200 * 2 weeks;
        vm.prank(address(protocolMessagingHub));
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
        vm.prank(address(protocolMessagingHub));
        cve.mintGaugeEmissions(address(gaugePool), 300 * 2 weeks);

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            10000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            20000
        );

        // user1 deposit 400 token0
        vm.prank(users[1]);
        IMToken(tokens[0]).mint(400 ether);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // user3 deposit 400 token1
        vm.prank(users[3]);
        IMToken(tokens[1]).mint(400 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            12000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            8000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            24000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            16000
        );

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // user0, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(cve.balanceOf(users[0]), 12000);
        assertEq(cve.balanceOf(users[3]), 16000);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            2000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            16000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            28000
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            16000
        );

        // user0 withdraw half
        vm.prank(users[0]);
        IMToken(tokens[0]).redeem(50 ether);

        // user2 deposit 2x
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            3111
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            24888
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            34666
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            29333
        );

        // user0, user1, user2, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[1]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[2]);
        gaugePool.claim(tokens[1]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(cve.balanceOf(users[0]), 15111);
        assertEq(cve.balanceOf(users[1]), 24888);
        assertEq(cve.balanceOf(users[2]), 34666);
        assertEq(cve.balanceOf(users[3]), 45333);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);

        gaugePool.updatePool(tokens[0]);
        gaugePool.updatePool(tokens[1]);

        assertEq(
            gaugePool.pendingRewards(tokens[0], users[0], address(cve)),
            1111
        );
        assertEq(
            gaugePool.pendingRewards(tokens[0], users[1], address(cve)),
            8889
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[2], address(cve)),
            6667
        );
        assertEq(
            gaugePool.pendingRewards(tokens[1], users[3], address(cve)),
            13333
        );
    }
}
