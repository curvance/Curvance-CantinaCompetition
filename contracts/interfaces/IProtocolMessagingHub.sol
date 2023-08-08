// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { ICVE, LzCallParams } from "contracts/interfaces/ICVE.sol";
import { swapRouter, lzTxObj } from "contracts/interfaces/layerzero/IStargateRouter.sol";

struct PoolData {
        address endpoint; // Stargate Endpoint
        uint256 dstChainId; // Destination Chain ID
        uint256 srcPoolId; // Source Pool ID
        uint256 dstPoolId; // Destination Pool ID
        uint256 amountLD; // Amount to send
        uint256 minAmountLD; // Min amount out
    }

interface IProtocolMessagingHub {

    function sendLockedTokenMessageData(
        uint16[] calldata dstChainId,
        bytes32[] calldata toAddress,
        bytes calldata payload,
        uint64 dstGasForCall,
        bytes calldata adapterParams, 
        LzCallParams calldata callParams
    ) external;

    /// @notice Sends WETH fees to the Fee Accumulator on `dstChainId`
    /// @param to The address Stargate Endpoint to call
    /// @param poolData Stargate pool routing data
    /// @param lzTxParams Supplemental LayerZero parameters for the transaction
    /// @param payload Additional payload data
    function sendFees(
        address to,
        PoolData calldata poolData,
        lzTxObj calldata lzTxParams,
        bytes calldata payload
    ) external;
}