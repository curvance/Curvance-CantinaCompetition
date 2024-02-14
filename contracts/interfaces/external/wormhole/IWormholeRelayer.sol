// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWormholeRelayer {
    /// @param keyType 0-127 are reserved for standardized KeyTypes,
    ///                128-255 are for custom use.
    struct MessageKey {
        uint8 keyType;
        bytes encodedKey;
    }

    struct VaaKey {
        uint16 chainId;
        bytes32 emitterAddress;
        uint64 sequence;
    }

    /// @notice Publishes an instruction for the delivery provider at `deliveryProviderAddress`
    /// to relay a payload and external messages specified by `messageKeys` to the address `targetAddress` on chain `targetChain`
    /// with gas limit `gasLimit` and `msg.value` equal to
    /// receiverValue + (arbitrary amount that is paid for by paymentForExtraReceiverValue of this chain's wei) in targetChain wei.
    ///
    /// Any refunds (from leftover gas) will be sent to `refundAddress` on chain `refundChain`
    /// `targetAddress` must implement the IWormholeReceiver interface
    ///
    /// This function must be called with `msg.value` equal to
    /// quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit, deliveryProviderAddress) + paymentForExtraReceiverValue
    ///
    /// Note: MessageKeys can specify wormhole messages (VaaKeys) or other types of messages (ex. USDC CCTP attestations). Ensure the selected
    /// DeliveryProvider supports all the MessageKey.keyType values specified or it will not be delivered!
    ///
    /// @param targetChain in Wormhole Chain ID format
    /// @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
    /// @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    /// @param paymentForExtraReceiverValue amount (in current chain currency units) to spend on extra receiverValue
    ///        (in addition to the `receiverValue` specified)
    /// @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according to the
    ///        `targetChainRefundPerGasUnused` rate quoted by the delivery provider
    /// @param refundChain The chain to deliver any refund to, in Wormhole Chain ID format
    /// @param refundAddress The address on `refundChain` to deliver any refund to
    /// @param deliveryProviderAddress The address of the desired delivery provider's implementation of IDeliveryProvider
    /// @param messageKeys Additional messagess to pass in as parameter in call to `targetAddress`
    /// @param consistencyLevel Consistency level with which to publish the delivery instructions - see
    ///        https://book.wormhole.com/wormhole/3_coreLayerContracts.html?highlight=consistency#consistency-levels
    /// @return sequence sequence number of published VAA containing delivery instructions
    function sendToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 paymentForExtraReceiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress,
        address deliveryProviderAddress,
        MessageKey[] memory messageKeys,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);

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

    /// @notice Publishes an instruction for the default delivery provider
    /// to relay a payload and VAAs specified by `vaaKeys` to the address `targetAddress` on chain `targetChain`
    /// with gas limit `gasLimit` and `msg.value` equal to `receiverValue`
    ///
    /// `targetAddress` must implement the IWormholeReceiver interface
    ///
    /// This function must be called with `msg.value` equal to `quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit)`
    ///
    /// Any refunds (from leftover gas) will be paid to the delivery provider. In order to receive the refunds, use the `sendVaasToEvm` function
    /// with `refundChain` and `refundAddress` as parameters
    ///
    /// @param targetChain in Wormhole Chain ID format
    /// @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
    /// @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    /// @param gasLimit gas limit with which to call `targetAddress`.
    /// @param vaaKeys Additional VAAs to pass in as parameter in call to `targetAddress`
    /// @return sequence sequence number of published VAA containing delivery instructions
    function sendVaasToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        VaaKey[] memory vaaKeys
    ) external payable returns (uint64 sequence);

    /// @notice Returns the address of the current default delivery provider
    /// @return deliveryProvider The address of (the default delivery provider)'s contract on this source
    ///   chain. This must be a contract that implements IDeliveryProvider.
    function getDefaultDeliveryProvider()
        external
        view
        returns (address deliveryProvider);

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
