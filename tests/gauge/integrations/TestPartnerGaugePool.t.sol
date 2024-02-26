// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";

contract User {}

contract TestPartnerGaugePool is TestBaseMarket {
    address public owner;
    address[] public tokens;
    address[] public users;

    uint256 constant CHILD_GAUGE_COUNT = 5;
    address[CHILD_GAUGE_COUNT] public partnerRewardTokens;

    MockDataFeed public mockDaiFeed;

    receive() external payable {}

    fallback() external payable {}

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

        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // add partner gauges
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            partnerRewardTokens[i] = address(
                new MockToken("Reward Token", "RT", 18)
            );
            MockToken(partnerRewardTokens[i]).approve(
                address(gaugePool),
                1000 ether
            );

            gaugePool.addExtraReward(address(partnerRewardTokens[i]));
        }

        mockDaiFeed = new MockDataFeed(_CHAINLINK_DAI_USD);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, address(mockDaiFeed), 0, true);
    }

    function testRevertAddExtraRewardInvalidAddress() public {
        vm.expectRevert(GaugeErrors.InvalidAddress.selector);
        gaugePool.addExtraReward(address(0));

        vm.expectRevert(GaugeErrors.InvalidAddress.selector);
        gaugePool.addExtraReward(address(partnerRewardTokens[0]));
    }

    function testRevertRemoveExtraReward() public {
        vm.expectRevert(GaugeErrors.Unauthorized.selector);
        gaugePool.removeExtraReward(0, address(cve));

        vm.expectRevert(GaugeErrors.InvalidAddress.selector);
        gaugePool.removeExtraReward(0, address(partnerRewardTokens[0]));
    }

    function testSuccessRevertExtraReward() public {
        assertEq(gaugePool.getRewardTokensLength(), CHILD_GAUGE_COUNT + 1);

        gaugePool.removeExtraReward(1, address(partnerRewardTokens[0]));

        assertEq(gaugePool.getRewardTokensLength(), CHILD_GAUGE_COUNT);
    }

    function testRevertSetRewardPerSecInvalidEpoch() public {
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

        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            vm.expectRevert(GaugeErrors.InvalidEpoch.selector);
            gaugePool.setRewardPerSec(
                tokens[0],
                0,
                partnerRewardTokens[i],
                300
            );
        }
    }

    function testUpdateRewardPerSec() public {
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

        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            gaugePool.setRewardPerSec(
                tokens[0],
                1,
                partnerRewardTokens[i],
                300
            );
            gaugePool.setRewardPerSec(
                tokens[0],
                1,
                partnerRewardTokens[i],
                200
            );
        }
    }

    function testPartnerGaugesRewardRatioOfDifferentPools() public {
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

        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            gaugePool.setRewardPerSec(
                tokens[0],
                1,
                partnerRewardTokens[i],
                100
            );
            gaugePool.setRewardPerSec(
                tokens[1],
                1,
                partnerRewardTokens[i],
                200
            );
        }

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);

        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                10000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[2],
                    partnerRewardTokens[i]
                ),
                20000
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                12000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[1],
                    partnerRewardTokens[i]
                ),
                8000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[2],
                    partnerRewardTokens[i]
                ),
                24000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[3],
                    partnerRewardTokens[i]
                ),
                16000
            );
        }

        // user0, user3 claims
        vm.prank(users[0]);
        gaugePool.claim(tokens[0]);
        vm.prank(users[3]);
        gaugePool.claim(tokens[1]);
        assertEq(cve.balanceOf(users[0]), 12000);
        assertEq(cve.balanceOf(users[3]), 16000);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[0]),
                12000
            );
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[3]),
                16000
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                2000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[1],
                    partnerRewardTokens[i]
                ),
                16000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[2],
                    partnerRewardTokens[i]
                ),
                28000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[3],
                    partnerRewardTokens[i]
                ),
                16000
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                3111
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[1],
                    partnerRewardTokens[i]
                ),
                24888
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[2],
                    partnerRewardTokens[i]
                ),
                34666
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[3],
                    partnerRewardTokens[i]
                ),
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
        assertEq(cve.balanceOf(users[0]), 15111);
        assertEq(cve.balanceOf(users[1]), 24888);
        assertEq(cve.balanceOf(users[2]), 34666);
        assertEq(cve.balanceOf(users[3]), 45333);
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[0]),
                15111
            );
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[1]),
                24888
            );
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[2]),
                34666
            );
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[3]),
                45333
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                1111
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[1],
                    partnerRewardTokens[i]
                ),
                8889
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[2],
                    partnerRewardTokens[i]
                ),
                6667
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[3],
                    partnerRewardTokens[i]
                ),
                13333
            );
        }
    }

    function testPartnerGaugesRewardCalculationWithDifferentEpoch() public {
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

        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            gaugePool.setRewardPerSec(
                tokens[0],
                1,
                partnerRewardTokens[i],
                100
            );
            gaugePool.setRewardPerSec(
                tokens[1],
                1,
                partnerRewardTokens[i],
                200
            );
        }

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);

        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user1 deposit 100 token1
        vm.prank(users[1]);
        IMToken(tokens[1]).mint(100 ether);

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                10000
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[1],
                    partnerRewardTokens[i]
                ),
                20000
            );
        }

        // set next epoch reward per second
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            gaugePool.setRewardPerSec(
                tokens[0],
                2,
                partnerRewardTokens[i],
                200
            );
            gaugePool.setRewardPerSec(
                tokens[1],
                2,
                partnerRewardTokens[i],
                200
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                2 weeks * 100 + 100 * 200
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[1],
                    partnerRewardTokens[i]
                ),
                2 weeks * 200 + 100 * 200
            );
        }

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
        for (uint256 i = 0; i < CHILD_GAUGE_COUNT; i++) {
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[0]),
                2 weeks * 100 + 100 * 200
            );
            assertEq(
                MockToken(partnerRewardTokens[i]).balanceOf(users[1]),
                2 weeks * 200 + 100 * 200
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[0],
                    users[0],
                    partnerRewardTokens[i]
                ),
                0
            );
            assertEq(
                gaugePool.pendingRewards(
                    tokens[1],
                    users[1],
                    partnerRewardTokens[i]
                ),
                0
            );
        }
    }
}
