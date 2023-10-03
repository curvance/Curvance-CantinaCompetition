// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { LzCallParams } from "contracts/interfaces/ICVE.sol";
import { LzTxObj } from "contracts/interfaces/layerzero/IStargateRouter.sol";

/// @param dstChainId Destination Chain ID
/// @param srcPoolId Source Pool ID
/// @param dstPoolId Destination Pool ID
/// @param amountLD Amount to send
/// @param minAmountLD Min amount out
struct PoolData {
    uint256 dstChainId;
    uint256 srcPoolId;
    uint256 dstPoolId;
    uint256 amountLD;
    uint256 minAmountLD;
}

interface IProtocolMessagingHub {
    function overEstimateStargateFee(
        uint8 functionType,
        bytes calldata toAddress
    ) external view returns (uint256);

    function quoteStargateFee(
        uint16 dstChainId,
        uint8 functionType,
        bytes calldata toAddress,
        bytes calldata transferAndCallPayload,
        LzTxObj memory lzTxParams
    ) external view returns (uint256, uint256);

    function sendLockedTokenData(
        uint16 dstChainId,
        bytes32 toAddress,
        bytes calldata payload,
        uint64 dstGasForCall,
        LzCallParams calldata callParams,
        uint256 etherValue
    ) external payable;

    /// @notice Sends WETH fees to the Fee Accumulator on `dstChainId`
    /// @param to The address Stargate Endpoint to call
    /// @param poolData Stargate pool routing data
    /// @param lzTxParams Supplemental LayerZero parameters for the transaction
    /// @param payload Additional payload data
    function sendFees(
        address to,
        PoolData calldata poolData,
        LzTxObj calldata lzTxParams,
        bytes calldata payload
    ) external;
}
