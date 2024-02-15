// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITokenBridge {
    /// EXTERNAL FUNCTIONS ///

    function transferTokensWithPayload(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce,
        bytes memory payload
    ) external payable returns (uint64 sequence);
}
