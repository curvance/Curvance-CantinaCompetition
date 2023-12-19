// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";

contract User {}

contract TestBoostedLock is TestBaseMarket {
    address public owner;
    address[] public tokens;
    address[] public users;

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
        gaugePool.start(address(lendtroller));

        for (uint256 i = 0; i < 10; i++) {
            tokens[i] = address(_deployDDAI());

            // support market
            dai.approve(address(tokens[i]), 200000e18);
            lendtroller.listToken(tokens[i]);

            // add MToken support on price router
            priceRouter.addMTokenSupport(tokens[i]);

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
    }

    function testBoostedLockFromClaim() public {
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
        cve.mintGaugeEmissions(address(gaugePool), 300e18 * 2 weeks);

        vm.warp(gaugePool.startTime() + 1 * 2 weeks);

        // user0 deposit 100 token0
        vm.prank(users[0]);
        IMToken(tokens[0]).mint(100 ether);

        // user2 deposit 100 token1
        vm.prank(users[2]);
        IMToken(tokens[1]).mint(100 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 10000e18);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 20000e18);

        // user1 deposit 400 token0
        vm.prank(users[1]);
        IMToken(tokens[0]).mint(400 ether);

        // user3 deposit 400 token1
        vm.prank(users[3]);
        IMToken(tokens[1]).mint(400 ether);

        // check pending rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        assertEq(gaugePool.pendingRewards(tokens[0], users[0]), 12000e18);
        assertEq(gaugePool.pendingRewards(tokens[0], users[1]), 8000e18);
        assertEq(gaugePool.pendingRewards(tokens[1], users[2]), 24000e18);
        assertEq(gaugePool.pendingRewards(tokens[1], users[3]), 16000e18);

        // user0, user3 claims
        RewardsData memory rewardData;
        vm.prank(users[0]);
        gaugePool.claimAndLock(tokens[0], false, rewardData, "0x", 0);
        vm.prank(users[3]);
        gaugePool.claimAndLock(tokens[1], false, rewardData, "0x", 0);
        assertEq(veCVE.balanceOf(users[0]), 12000e18);
        assertEq(veCVE.balanceOf(users[3]), 16000e18);
        assertEq(veCVE.getVotes(users[0]), 11538e18);
        assertEq(veCVE.getVotes(users[3]), 15384e18);

        vm.warp(block.timestamp + 1000);

        // user0, user3 claims
        vm.prank(users[0]);
        gaugePool.claimAndExtendLock(tokens[0], 0, true, rewardData, "0x", 0);
        vm.prank(users[3]);
        gaugePool.claimAndExtendLock(tokens[1], 0, false, rewardData, "0x", 0);
        assertEq(veCVE.balanceOf(users[0]), 32000e18);
        assertEq(veCVE.balanceOf(users[3]), 176000e18);
        assertEq(veCVE.getVotes(users[0]), 35200e18);
        assertEq(veCVE.getVotes(users[3]), 169230e18);

        vm.warp(block.timestamp + 6 weeks);
        assertEq(veCVE.balanceOf(users[0]), 32000e18);
        assertEq(veCVE.balanceOf(users[3]), 176000e18);
        assertEq(veCVE.getVotes(users[0]), 35200e18);
        assertEq(veCVE.getVotes(users[3]), 148923e18);
    }
}
