// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWormholeRelayer {
    /// @notice Publishes an instruction for the default delivery provider to
    ///         relay a payload to the address `targetAddress` on chain
    ///         `targetChain` with gas limit `gasLimit` and msg.value` equal to
    ///         `receiverValue`.
    ///         `targetAddress` must implement the IWormholeReceiver interface.
    ///         This function must be called with `msg.value` equal to
    ///         `quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit)`.
    ///         Any refunds (from leftover gas) will be paid to
    ///         the delivery provider. In order to receive the refunds, use
    ///         the `sendPayloadToEvm` function with `refundChain` and
    ///         `refundAddress` as parameters.
    /// @param targetChain In Wormhole Chain ID format.
    /// @param targetAddress Address to call on targetChain
    ///                      (that implements IWormholeReceiver).
    /// @param payload Arbitrary bytes to pass in as parameter in call to
    ///                `targetAddress`.
    /// @param receiverValue msg.value that delivery provider should pass in
    ///                      for call to `targetAddress`.
    ///                      (in targetChain currency units)
    /// @param gasLimit Gas limit with which to call `targetAddress`.
    /// @return sequence Sequence number of published VAA containing delivery
    ///                  instructions.
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);

    /// @notice Returns the price to request a relay to chain `targetChain`,
    ///         using the default delivery provider.
    /// @param targetChain in Wormhole Chain ID format.
    /// @param receiverValue msg.value that delivery provider should pass in
    ///                      for call to `targetAddress`.
    ///                      (in targetChain currency units)
    /// @param gasLimit gas limit with which to call `targetAddress`.
    /// @return nativePriceQuote Price, in units of current chain currency,
    ///                          that the delivery provider charges to perform
    ///                          the relay.
    /// @return targetChainRefundPerGasUnused amount of target chain currency
    ///             that will be refunded per unit of gas unused,
    ///             if a refundAddress is specified.
    ///             Note: This value can be overridden by the delivery provider
    ///                   on the target chain.
    ///                   The returned value here should be considered to be a
    ///                   promise by the delivery provider of the amount of
    ///                   refund per gas unused that will be returned to the
    ///                   refundAddress at the target chain.
    ///                   If a delivery provider decides to override, this will
    ///                   be visible as part of the emitted Delivery event on
    ///                   the target chain.
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    )
        external
        view
        returns (
            uint256 nativePriceQuote,
            uint256 targetChainRefundPerGasUnused
        );
}
