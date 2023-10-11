// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";

contract ClaimRewardsForTest is TestBaseCVELocker {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    RewardsData public rewardsData =
        RewardsData(_WETH_ADDRESS, false, false, false);
    SwapperLib.Swap public swapData;
    address[] public path;

    function setUp() public override {
        super.setUp();

        path.push(_USDC_ADDRESS);
        path.push(_WETH_ADDRESS);

        swapData.inputToken = _USDC_ADDRESS;
        swapData.inputAmount = 1e18;
        swapData.outputToken = _WETH_ADDRESS;
        swapData.target = _UNISWAP_V2_ROUTER;
        swapData.call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            1e18,
            0,
            path,
            address(cveLocker),
            block.timestamp
        );

        deal(_USDC_ADDRESS, address(cveLocker), 1e18);
    }

    function test_claimRewardsFor_fail_whenCallerIsNotVeCVE() public {
        cveLocker.addAuthorizedRewardToken(_WETH_ADDRESS);

        vm.startPrank(user1);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(1e18, false, user1, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            uint256 nextEpochToDeliver = cveLocker.nextEpochToDeliver();

            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(nextEpochToDeliver, _ONE);
        }

        uint256 epochs = cveLocker.epochsToClaim(user1);

        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.claimRewardsFor(
            user1,
            user1,
            epochs,
            rewardsData,
            abi.encode(swapData),
            0
        );
    }

    function test_claimRewardsFor_fail_whenRewardTokenIsNotAuthorized()
        public
    {
        vm.startPrank(user1);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(1e18, false, user1, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            uint256 nextEpochToDeliver = cveLocker.nextEpochToDeliver();

            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(nextEpochToDeliver, _ONE);
        }

        uint256 epochs = cveLocker.epochsToClaim(user1);

        vm.expectRevert(CVELocker.CVELocker__ParametersareInvalid.selector);

        vm.prank(address(veCVE));
        cveLocker.claimRewardsFor(
            user1,
            user1,
            epochs,
            rewardsData,
            abi.encode(swapData),
            0
        );
    }

    function test_claimRewardsFor_success_fuzzed(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100e18);

        cveLocker.addAuthorizedRewardToken(_WETH_ADDRESS);

        vm.startPrank(user1);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(amount, false, user1, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            uint256 nextEpochToDeliver = cveLocker.nextEpochToDeliver();

            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(nextEpochToDeliver, _ONE);
        }

        deal(_USDC_ADDRESS, address(cveLocker), amount);

        swapData.inputAmount = amount;
        swapData.call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            amount,
            0,
            path,
            address(cveLocker),
            block.timestamp
        );

        uint256 epochs = cveLocker.epochsToClaim(user1);

        uint256[] memory amountsOut = IUniswapV2Router(_UNISWAP_V2_ROUTER)
            .getAmountsOut(amount, path);
        uint256 baseRewardBalance = usdc.balanceOf(address(cveLocker));
        uint256 desiredTokenBalance = IERC20(_WETH_ADDRESS).balanceOf(user1);

        vm.prank(address(veCVE));
        cveLocker.claimRewardsFor(
            user1,
            user1,
            epochs,
            rewardsData,
            abi.encode(swapData),
            0
        );

        assertEq(
            usdc.balanceOf(address(cveLocker)),
            baseRewardBalance - amountsOut[0]
        );
        assertEq(
            IERC20(_WETH_ADDRESS).balanceOf(user1),
            desiredTokenBalance + amountsOut[1]
        );
    }
}
