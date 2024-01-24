// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract Faucet is Ownable {
    using ECDSA for bytes32;

    address private signer;

    /// user => token => last claimed timestamp
    mapping(address => mapping(address => uint256)) public userLastClaimed;

    mapping(bytes => bool) public isSignatureUsed;

    constructor(address _signer) Ownable() {
        signer = _signer;
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    function claim(
        address user,
        address token,
        uint256 amount,
        uint256 expireAt,
        bytes calldata signature
    ) external {
        require(!isSignatureUsed[signature], "Signature already used");
        require(
            userLastClaimed[user][token] + 24 hours <= block.timestamp,
            "Wait 24 hours"
        );
        require(expireAt >= block.timestamp, "Signature expired");

        bytes32 message = getMessageHash(user, token, amount, expireAt);
        require(
            ECDSA.recover(message, signature) == signer,
            "Invalid signature"
        );

        if (token == address(0)) {
            require(address(this).balance >= amount, "Not enough ETH");
            SafeTransferLib.safeTransferETH(user, amount);
        } else {
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "Not enough Token"
            );
            SafeTransferLib.safeTransfer(token, user, amount);
        }

        isSignatureUsed[signature] = true;
        userLastClaimed[user][token] = block.timestamp;
    }

    function getMessageHash(
        address user,
        address token,
        uint256 amount,
        uint256 expireAt
    ) public pure returns (bytes32) {
        bytes32 hash = keccak256(
            abi.encodePacked(user, token, amount, expireAt)
        );
        return ECDSA.toEthSignedMessageHash(hash);
    }
}
