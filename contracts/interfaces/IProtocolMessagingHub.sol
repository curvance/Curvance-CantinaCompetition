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
    function sendWormholeMessages(
        uint16 dstChainId,
        address toAddress,
        bytes calldata payload
    ) external payable;

    /// @notice Sends fee tokens to the Messaging Hub on `dstChainId`.
    /// @param dstChainId Wormhole specific destination chain ID .
    /// @param to The address of Messaging Hub on `dstChainId`.
    /// @param amount The amount of token to transfer.
    function sendFees(uint16 dstChainId, address to, uint256 amount) external;

    /// @notice Bridge CVE to destination chain.
    /// @param dstChainId Chain ID of the target blockchain.
    /// @param recipient The address of recipient on destination chain.
    /// @param amount The amount of token to bridge.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function bridgeCVE(
        uint256 dstChainId,
        address recipient,
        uint256 amount
    ) external payable returns (uint64);

    /// @notice Bridge VeCVE lock to destination chain.
    /// @param dstChainId Chain ID of the target blockchain.
    /// @param recipient The address of recipient on destination chain.
    /// @param amount The amount of token to bridge.
    /// @param continuousLock Whether the lock should be continuous or not.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function bridgeVeCVELock(
        uint256 dstChainId,
        address recipient,
        uint256 amount,
        bool continuousLock
    ) external payable returns (uint64);

    /// @notice Returns required amount of CVE for relayer fee.
    /// @param dstChainId Chain ID of the target blockchain.
    /// @return Required fee.
    function cveRelayerFee(uint256 dstChainId) external view returns (uint256);

    /// @notice Returns required amount of native asset for message fee.
    /// @return Required fee.
    function cveBridgeFee() external view returns (uint256);

    /// @notice Returns wormhole specific chain ID for evm chain ID.
    /// @param chainId Evm chain ID.
    function wormholeChainId(uint256 chainId) external view returns (uint16);
}
