// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// In fork environment, it fails to call functions of ArbSys contract
// which on address 0x0000000000000000000000000000000000000064
// To solve this problem, need to use mock contract.
contract MockArbSys {
    function arbBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function arbBlockHash(
        uint256 blockNumber
    ) external view returns (bytes32) {
        // Hardcoded values to simulate the deposit execution.
        if (blockNumber == 150368147) {
            return
                0x1829312c7ab7afd4792be2df4561fc9b293341021905134670a05c2152c0b081;
        } else if (blockNumber == 150368148) {
            return
                0x950cea2980f9a92d1e2c59526071f2d793b9f40d84ca1974948d35a0649c0a15;
        }
    }
}
