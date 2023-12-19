// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IProtocolMessagingHub {
    /// @notice Quotes gas cost and token fee for executing crosschain
    ///         wormhole deposit and messaging.
    /// @param dstChainId Wormhole specific destination chain ID.
    /// @param transferToken Whether deliver token or not.
    /// @return Total gas cost.
    /// @return Deliverying fee.
    function quoteWormholeFee(
        uint16 dstChainId,
        bool transferToken
    ) external view returns (uint256, uint256);

    /// @notice Sends veCVE locked token data to destination chain.
    /// @param dstChainId Destination chain ID where the message data should be
    ///                   sent.
    /// @param toAddress The destination address specified by `dstChainId`.
    /// @param payload The payload data that is sent along with the message.
    /// @dev We redundantly pass adapterParams so we do not need to coerce data
    ///      in the function, calls with this function will have
    ///      messageType = 1, 2 or 3
    function sendLockedTokenData(
        uint16 dstChainId,
        address toAddress,
        bytes calldata payload
    ) external payable;

    /// @notice Sends fee tokens to the Messaging Hub on `dstChainId`.
    /// @param dstChainId Wormhole specific destination chain ID .
    /// @param to The address of Messaging Hub on `dstChainId`.
    /// @param amount The amount of token to transfer.
    function sendFees(uint16 dstChainId, address to, uint256 amount) external;
}
