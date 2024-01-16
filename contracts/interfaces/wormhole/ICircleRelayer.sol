// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";
import { IERC20Metadata } from "contracts/interfaces/IERC20Metadata.sol";

interface ICircleRelayer {
    /// @notice Calls Wormhole's Circle Integration contract
    ///         to burn user specified tokens.
    /// @dev It emits a Wormhole message with instructions for how to handle
    ///      relayer payments on the target contract and the quantity of tokens
    ///      to convert into native assets for the user.
    /// @param token Address of the Circle Bridge asset to be transferred.
    /// @param amount Quantity of tokens to be transferred.
    /// @param toNativeTokenAmount Amount of tokens to swap into native assets
    ///                            on the target chain.
    /// @param targetChain Wormhole chain ID of the target blockchain.
    /// @param targetRecipient User's wallet address on the target blockchain.
    /// @return messageSequence Wormhole sequence for emitted
    ///                         TransferTokensWithRelay message.
    function transferTokensWithRelay(
        IERC20Metadata token,
        uint256 amount,
        uint256 toNativeTokenAmount,
        uint16 targetChain,
        bytes32 targetRecipient
    ) external payable returns (uint64 messageSequence);

    /// @notice Returns registered circle relayer address on given chain.
    /// @param targetChain Wormhole specific chain ID of the blockchain.
    function getRegisteredContract(
        uint16 targetChain
    ) external view returns (bytes32);

    function relayerFee(
        uint16 targetChain,
        address token
    ) external view returns (uint256);

    function wormhole() external view returns (IWormhole);
}
