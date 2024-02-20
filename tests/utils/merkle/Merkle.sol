// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./MurkyBase.sol";

contract Merkle is MurkyBase {
    function hashLeafPairs(
        bytes32 left,
        bytes32 right
    ) public pure override returns (bytes32 _hash) {
        assembly {
            mstore(0x0, xor(left, right))
            _hash := keccak256(0x0, 0x20)
        }
    }
}
