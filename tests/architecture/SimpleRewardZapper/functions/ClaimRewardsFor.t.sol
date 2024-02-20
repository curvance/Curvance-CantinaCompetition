// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseSimpleRewardZaper } from "../TestBaseSimpleRewardZaper.sol";

import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { SimpleRewardZapper } from "contracts/architecture/utils/SimpleRewardZapper.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";

contract ClaimRewardsForTest is TestBaseSimpleRewardZaper {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    RewardsData public rewardsData = RewardsData(false, false, false, false);
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

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);
        centralRegistry.setExternalCallDataChecker(
            _UNISWAP_V2_ROUTER,
            address(new MockCallDataChecker(_UNISWAP_V2_ROUTER))
        );

        deal(_USDC_ADDRESS, address(cveLocker), 1e18);
    }

    function test_claimRewardsFor_fail_whenCallerIsNotVeCVE() public {
        simpleRewardZapper.addAuthorizedOutputToken(_WETH_ADDRESS);

        vm.startPrank(user1);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(1e18, false, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(_ONE);
        }

        uint256 epochs = cveLocker.epochsToClaim(user1);

        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.claimRewardsFor(
            user1,
            epochs,
            rewardsData,
            abi.encode(swapData),
            0
        );
    }

    function test_claimRewardsFor_success_fuzzed(uint256 amount) public {
        vm.assume(amount > 1e18 && amount <= 100e18);

        simpleRewardZapper.addAuthorizedOutputToken(_WETH_ADDRESS);

        vm.startPrank(user1);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(amount, false, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(_ONE);
        }

        deal(_USDC_ADDRESS, address(cveLocker), amount);

        swapData.inputAmount = amount;
        swapData.call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            amount,
            0,
            path,
            address(simpleRewardZapper),
            block.timestamp
        );

        uint256[] memory amountsOut = IUniswapV2Router(_UNISWAP_V2_ROUTER)
            .getAmountsOut(amount, path);
        uint256 baseRewardBalance = usdc.balanceOf(address(cveLocker));
        uint256 desiredTokenBalance = IERC20(_WETH_ADDRESS).balanceOf(user1);

        vm.prank(user1);
        cveLocker.setDelegateApproval(address(simpleRewardZapper), true);

        vm.prank(user1);
        simpleRewardZapper.claimAndSwap(swapData, user2);

        assertEq(
            usdc.balanceOf(address(cveLocker)),
            baseRewardBalance - amountsOut[0]
        );
        assertEq(
            IERC20(_WETH_ADDRESS).balanceOf(user2),
            desiredTokenBalance + amountsOut[1]
        );
    }
}
