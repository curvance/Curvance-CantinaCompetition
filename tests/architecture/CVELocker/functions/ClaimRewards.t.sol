// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";

contract ClaimRewardsTest is TestBaseCVELocker {
    RewardsData public rewardsData = RewardsData(true, false, false, false);
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    SwapperLib.Swap public swapData;
    address[] public path;

    function setUp() public override {
        super.setUp();

        path.push(_USDC_ADDRESS);
        path.push(address(cve));

        swapData.inputToken = _USDC_ADDRESS;
        swapData.inputAmount = 100e6;
        swapData.outputToken = address(cve);
        swapData.target = _UNISWAP_V2_ROUTER;
        swapData.call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            100e6,
            0,
            path,
            address(cveLocker),
            block.timestamp
        );

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);
        centralRegistry.setExternalCallDataChecker(
            _UNISWAP_V2_ROUTER,
            address(new MockCallDataChecker(_UNISWAP_V2_ROUTER))
        );

        deal(_USDC_ADDRESS, address(cveLocker), 10000e6);

        deal(_USDC_ADDRESS, address(this), 10000e6);
        deal(address(cve), address(this), 100e18);

        IERC20(_USDC_ADDRESS).approve(_UNISWAP_V2_ROUTER, 10000e6);
        cve.approve(_UNISWAP_V2_ROUTER, 100e18);

        _UNISWAP_V2_ROUTER.call(
            abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
                _USDC_ADDRESS,
                address(cve),
                10000e6,
                100e18,
                10000e6,
                100e18,
                address(this),
                block.timestamp
            )
        );
    }

    function test_claimRewards_fail_whenNoEpochRewardsToClaim() public {
        vm.prank(address(veCVE));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(_ONE);
        }

        vm.prank(user1);

        vm.expectRevert(CVELocker.CVELocker__NoEpochRewards.selector);
        cveLocker.claimRewards(rewardsData, abi.encode(swapData), 0);
    }

    function test_claimRewards_fail_whenSwapDataIsInvalid() public {
        vm.startPrank(user1);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(100e18, false, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(veCVE));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(_ONE);
        }

        swapData.inputToken = _DAI_ADDRESS;

        vm.prank(user1);

        vm.expectRevert(CVELocker.CVELocker__SwapDataIsInvalid.selector);
        cveLocker.claimRewards(rewardsData, abi.encode(swapData), 0);
    }

    function test_claimRewards_success_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public {
        centralRegistry.addVeCVELocker(address(cveLocker));

        rewardsData = RewardsData(
            true,
            shouldLock,
            isFreshLock,
            isFreshLockContinuous
        );

        vm.assume(amount > 1e18 && amount <= 100e18);

        vm.startPrank(user1);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(amount, isFreshLockContinuous, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(veCVE));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(_ONE);
        }

        assertTrue(cveLocker.hasRewardsToClaim(user1));

        uint256 rewards = isFreshLockContinuous ? amount * 2 : amount;

        deal(_USDC_ADDRESS, address(cveLocker), rewards);

        swapData.inputAmount = rewards;
        swapData.call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            rewards,
            0,
            path,
            address(cveLocker),
            block.timestamp
        );

        uint256[] memory amountsOut = IUniswapV2Router(_UNISWAP_V2_ROUTER)
            .getAmountsOut(rewards, path);
        uint256 baseRewardBalance = usdc.balanceOf(address(cveLocker));
        uint256 desiredTokenBalance = cve.balanceOf(user1);

        vm.prank(user1);
        cveLocker.claimRewards(rewardsData, abi.encode(swapData), 0);

        assertEq(
            usdc.balanceOf(address(cveLocker)),
            baseRewardBalance - amountsOut[0]
        );

        if (shouldLock) {
            assertEq(cve.balanceOf(user1), desiredTokenBalance);
        } else {
            assertEq(
                cve.balanceOf(user1),
                desiredTokenBalance + amountsOut[1]
            );
        }
    }
}
