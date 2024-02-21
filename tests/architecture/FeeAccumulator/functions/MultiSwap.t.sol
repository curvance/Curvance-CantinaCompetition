// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract MultiSwapTest is TestBaseFeeAccumulator {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    SwapperLib.Swap[] public swapData;
    address[] public path;
    address[] public tokens;

    function setUp() public override {
        super.setUp();

        path.push(_WETH_ADDRESS);
        path.push(_USDC_ADDRESS);

        tokens.push(_WETH_ADDRESS);

        swapData.push(
            SwapperLib.Swap({
                inputToken: _WETH_ADDRESS,
                inputAmount: _ONE,
                outputToken: _USDC_ADDRESS,
                target: _UNISWAP_V2_ROUTER,
                call: abi.encodeWithSignature(
                    "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                    _ONE,
                    0,
                    path,
                    address(feeAccumulator),
                    block.timestamp
                )
            })
        );

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = _WETH_ADDRESS;
        rewardTokens[1] = _USDC_ADDRESS;

        feeAccumulator.addRewardTokens(rewardTokens);

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);
        centralRegistry.setExternalCallDataChecker(
            _UNISWAP_V2_ROUTER,
            address(new MockCallDataChecker(_UNISWAP_V2_ROUTER))
        );
    }

    function test_multiSwap_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);
    }

    function test_multiSwap_fail_whenTokensLengthIsNotMatch() public {
        tokens.push(_USDT_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeAccumulator
                    .FeeAccumulator__SwapDataAndTokenLengthMismatch
                    .selector,
                1,
                2
            )
        );

        vm.prank(harvester);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);
    }

    function test_multiSwap_fail_whenTokenIsNotRewardToken() public {
        tokens[0] = _USDT_ADDRESS;

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeAccumulator
                    .FeeAccumulator__SwapDataCurrentTokenIsNotRewardToken
                    .selector,
                0,
                _USDT_ADDRESS
            )
        );

        vm.prank(harvester);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);
    }

    function test_multiSwap_fail_whenTokenIsNotSwapInputToken() public {
        tokens[0] = _USDC_ADDRESS;

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeAccumulator
                    .FeeAccumulator__SwapDataInputTokenIsNotCurrentToken
                    .selector,
                0,
                _WETH_ADDRESS,
                _USDC_ADDRESS
            )
        );

        vm.prank(harvester);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);
    }

    function test_multiSwap_fail_whenSwapOutputTokenIsNotFeeToken() public {
        swapData[0] = SwapperLib.Swap({
            inputToken: _WETH_ADDRESS,
            inputAmount: _ONE,
            outputToken: _USDT_ADDRESS,
            target: _UNISWAP_V2_ROUTER,
            call: abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                _ONE,
                0,
                path,
                address(feeAccumulator),
                block.timestamp
            )
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeAccumulator
                    .FeeAccumulator__SwapDataOutputTokenIsNotFeeToken
                    .selector,
                0,
                _USDT_ADDRESS,
                _USDC_ADDRESS
            )
        );

        vm.prank(harvester);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);
    }

    function test_multiSwap_fail_whenSwapTargetIsInvalidSwapper() public {
        swapData[0] = SwapperLib.Swap({
            inputToken: _WETH_ADDRESS,
            inputAmount: _ONE,
            outputToken: _USDC_ADDRESS,
            target: address(1),
            call: abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                _ONE,
                0,
                path,
                address(feeAccumulator),
                block.timestamp
            )
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeAccumulator.FeeAccumulator__SwapDataInvalidSwapper.selector,
                0,
                address(1)
            )
        );

        vm.prank(harvester);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);
    }

    function test_multiSwap_fail_whenFeeAccumulatorHasNoEnoughToken() public {
        vm.expectRevert();

        vm.prank(harvester);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);
    }

    function test_multiSwap_success() public {
        deal(_WETH_ADDRESS, address(feeAccumulator), _ONE);
        uint256 balance = usdc.balanceOf(address(oneBalanceFeeManager));

        vm.prank(harvester);
        feeAccumulator.multiSwap(abi.encode(swapData), tokens);

        assertEq(
            IERC20(_WETH_ADDRESS).balanceOf(address(oneBalanceFeeManager)),
            0
        );
        assertGt(usdc.balanceOf(address(oneBalanceFeeManager)), balance);
    }
}
