// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IAggregationRouterV5 } from "contracts/interfaces/external/1inch/IAggregationRouterV5.sol";
import { UniswapV3Pool } from "contracts/interfaces/external/uniswap/UniswapV3Pool.sol";
import { CallDataCheckerBase, SwapperLib } from "./CallDataCheckerBase.sol";

contract CallDataCheckerFor1InchAggregationRouterV5 is CallDataCheckerBase {
    /// CONSTANTS ///
    uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255;
    uint256 private constant _REVERSE_MASK =
        0x8000000000000000000000000000000000000000000000000000000000000000;

    /// CONSTRUCTOR ///

    constructor(address _target) CallDataCheckerBase(_target) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Inspects calldata for compliance with other swap instruction
    ///         parameters.
    /// @dev Used on Zap/swap to inspect and validate calldata safety.
    /// @param swapData Zap/swap instruction data including both direct
    ///                 parameters and decodeable calldata.
    /// @param expectedRecipient User who will receive results of Zap/swap.
    function checkCallData(
        SwapperLib.Swap memory swapData,
        address expectedRecipient
    ) external view override {
        if (swapData.target != target) {
            revert CallDataChecker__TargetError();
        }

        bytes4 funcSigHash = getFuncSigHash(swapData.call);
        address recipient;
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        if (funcSigHash == IAggregationRouterV5.swap.selector) {
            (, IAggregationRouterV5.SwapDescription memory desc, , ) = abi
                .decode(
                    getFuncParams(swapData.call),
                    (
                        address,
                        IAggregationRouterV5.SwapDescription,
                        bytes,
                        bytes
                    )
                );
            recipient = desc.dstReceiver;
            inputToken = desc.srcToken;
            inputAmount = desc.amount;
            outputToken = desc.dstToken;
        } else if (
            funcSigHash ==
            IAggregationRouterV5.uniswapV3SwapToWithPermit.selector
        ) {
            (
                address payable recipientAddress,
                address srcToken,
                uint256 amount,
                ,
                uint256[] memory pools,

            ) = abi.decode(
                    getFuncParams(swapData.call),
                    (address, address, uint256, uint256, uint256[], bytes)
                );

            recipient = recipientAddress;
            inputToken = srcToken;
            inputAmount = amount;

            uint256 pool = pools[pools.length - 1];
            outputToken = (pool & _ONE_FOR_ZERO_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token1()
                : UniswapV3Pool(address(uint160(pool))).token0();
        } else if (
            funcSigHash == IAggregationRouterV5.uniswapV3SwapTo.selector
        ) {
            (
                address payable recipientAddress,
                uint256 amount,
                ,
                uint256[] memory pools
            ) = abi.decode(
                    getFuncParams(swapData.call),
                    (address, uint256, uint256, uint256[])
                );

            recipient = recipientAddress;
            inputAmount = amount;

            uint256 pool = pools[0];
            inputToken = (pool & _ONE_FOR_ZERO_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token0()
                : UniswapV3Pool(address(uint160(pool))).token1();

            pool = pools[pools.length - 1];
            outputToken = (pool & _ONE_FOR_ZERO_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token1()
                : UniswapV3Pool(address(uint160(pool))).token0();
        } else if (
            funcSigHash == IAggregationRouterV5.uniswapV3Swap.selector
        ) {
            (uint256 amount, , uint256[] memory pools) = abi.decode(
                getFuncParams(swapData.call),
                (uint256, uint256, uint256[])
            );

            recipient = expectedRecipient;
            inputAmount = amount;

            uint256 pool = pools[0];
            inputToken = (pool & _ONE_FOR_ZERO_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token0()
                : UniswapV3Pool(address(uint160(pool))).token1();

            pool = pools[pools.length - 1];
            outputToken = (pool & _ONE_FOR_ZERO_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token1()
                : UniswapV3Pool(address(uint160(pool))).token0();
        } else if (
            funcSigHash == IAggregationRouterV5.unoswapToWithPermit.selector
        ) {
            (
                address payable recipientAddress,
                address srcToken,
                uint256 amount,
                ,
                uint256[] memory pools,

            ) = abi.decode(
                    getFuncParams(swapData.call),
                    (address, address, uint256, uint256, uint256[], bytes)
                );

            recipient = recipientAddress;
            inputToken = srcToken;
            inputAmount = amount;

            uint256 pool = pools[pools.length - 1];
            outputToken = (pool & _REVERSE_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token1()
                : UniswapV3Pool(address(uint160(pool))).token0();
        } else if (funcSigHash == IAggregationRouterV5.unoswapTo.selector) {
            (
                address payable recipientAddress,
                address srcToken,
                uint256 amount,
                ,
                uint256[] memory pools
            ) = abi.decode(
                    getFuncParams(swapData.call),
                    (address, address, uint256, uint256, uint256[])
                );

            recipient = recipientAddress;
            inputToken = srcToken;
            inputAmount = amount;

            uint256 pool = pools[pools.length - 1];
            outputToken = (pool & _REVERSE_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token1()
                : UniswapV3Pool(address(uint160(pool))).token0();
        } else if (funcSigHash == IAggregationRouterV5.unoswap.selector) {
            (address srcToken, uint256 amount, , uint256[] memory pools) = abi
                .decode(
                    getFuncParams(swapData.call),
                    (address, uint256, uint256, uint256[])
                );

            recipient = expectedRecipient;
            inputToken = srcToken;
            inputAmount = amount;

            uint256 pool = pools[pools.length - 1];
            outputToken = (pool & _REVERSE_MASK == 0)
                ? UniswapV3Pool(address(uint160(pool))).token1()
                : UniswapV3Pool(address(uint160(pool))).token0();
        } else {
            revert CallDataChecker__InvalidFuncSig();
        }

        if (recipient != expectedRecipient) {
            revert CallDataChecker__RecipientError();
        }

        if (inputToken != swapData.inputToken) {
            revert CallDataChecker__InputTokenError();
        }

        if (inputAmount != swapData.inputAmount) {
            revert CallDataChecker__InputAmountError();
        }

        if (outputToken != swapData.outputToken) {
            revert CallDataChecker__OutputTokenError();
        }
    }
}
