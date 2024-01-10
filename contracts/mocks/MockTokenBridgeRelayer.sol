// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";

contract MockTokenBridgeRelayer {
    /// TYPES ///

    struct SwapRateUpdate {
        address token;
        uint256 value;
    }

    /// CONSTANTS ///

    address internal constant _WORMHOLE =
        0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;

    /// EXTERNAL FUNCTIONS ///

    /// @notice Calls Wormhole's Token Bridge contract to emit
    ///         a contract-controlled transfer. The transfer message includes
    ///         an arbitrary payload with instructions for how to handle
    ///         relayer payments on the target contract and the quantity of
    ///         tokens to convert into native assets for the user.
    /// @param token ERC20 token address to transfer cross chain.
    /// @param amount Quantity of tokens to be transferred.
    /// @param toNativeTokenAmount Amount of tokens to swap into native assets
    ///                            on the target chain.
    /// @param targetChain Wormhole chain ID of the target blockchain.
    /// @param targetRecipient User's wallet address on the target blockchain
    ///                        in bytes32 format (zero-left-padded).
    /// @param batchId ID for Wormhole message batching
    /// @return messageSequence Wormhole sequence for emitted
    ///                         TransferTokensWithRelay message.
    function transferTokensWithRelay(
        address token,
        uint256 amount,
        uint256 toNativeTokenAmount,
        uint16 targetChain,
        bytes32 targetRecipient,
        uint32 batchId
    ) external payable returns (uint64 messageSequence) {}

    /// @notice Converts the USD denominated relayer fee into the specified token
    ///         denomination.
    /// @param targetChainId Wormhole specific chain ID of the target blockchain.
    /// @param token Address of token being transferred.
    /// @param decimals Token decimals of token being transferred.
    /// @return feeInTokenDenomination Relayer fee denominated in tokens.
    function calculateRelayerFee(
        uint16 targetChainId,
        address token,
        uint8 decimals
    ) external view returns (uint256 feeInTokenDenomination) {}

    /// @notice Register tokens accepted by this contract.
    /// @param chainId Wormhole specific chain ID.
    /// @param token Address of the token.
    function registerToken(uint16 chainId, address token) external {}

    function wormhole() external pure returns (IWormhole) {
        return IWormhole(_WORMHOLE);
    }

    function tokenBridge() external view returns (address) {}

    function owner() external view returns (address) {}

    /// @notice Updates the swap rates for a batch of tokens.
    /// @param chainId Wormhole chain ID.
    /// @param swapRateUpdate Array of structs with token -> swap rate pairs.
    /// @dev The swapRate is the conversion rate using asset prices denominated
    ///      in USD multiplied by the swapRatePrecision.
    ///      For example, if the conversion rate is $15 and
    ///      the swapRatePrecision is 1000000, the swapRate should be set
    ///      to 15000000.
    ///
    /// NOTE: This function does NOT check if a token is specified twice.
    ///       It is up to the owner to correctly construct the `SwapRateUpdate`
    ///       struct.
    function updateSwapRate(
        uint16 chainId,
        SwapRateUpdate[] calldata swapRateUpdate
    ) external {}
}
