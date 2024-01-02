// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "contracts/interfaces/IERC20.sol";

library Bytes32Helper {

    /// ERRORS ///

    error Bytes32Helper__ZeroLengthString();

    /// INTERNAL FUNCTIONS ///

    /// @notice Converts `tokenAddress` to bytes32 based on its ERC20 symbol.
    /// @param tokenAddress Address of desired token to pull ERC20 symbol from.
    function _toBytes32(address tokenAddress) internal view returns (bytes32) {
        string memory concatString = string.concat(_getSymbol(tokenAddress));
        return _stringToBytes32(concatString);
    }

    /// @notice Converts `tokenAddress` to bytes32 based on its ERC20 symbol,
    ///         and "/ETH" appended.
    /// @param tokenAddress Address of desired token to pull ERC20 symbol from.
    function _toBytes32WithETH(address tokenAddress) internal view returns (bytes32) {
        string memory concatString = string.concat(_getSymbol(tokenAddress), "/ETH");
        return _stringToBytes32(concatString);
    }

    /// @notice Converts `tokenAddress` to bytes32 based on its ERC20 symbol,
    ///         and "/USD" appended.
    /// @param tokenAddress Address of desired token to pull ERC20 symbol from.
    function _toBytes32WithUSD(address tokenAddress) internal view returns (bytes32) {
        string memory concatString = string.concat(_getSymbol(tokenAddress), "/USD");
        return _stringToBytes32(concatString);
    }

    /// @notice Returns `tokenAddress`'s ERC20 symbol as a string.
    /// @param tokenAddress Address of desired token to pull ERC20 symbol from.
    function _getSymbol(address tokenAddress) internal view returns (string memory) {
        return IERC20(tokenAddress).symbol();
    }

    /// @dev This will trim the output value to 32 bytes,
    ///      even if the bytes value is > 32 bytes
    function _stringToBytes32(string memory stringData) public pure returns (bytes32 result) {
        bytes memory bytesData = bytes(stringData);
        if (bytesData.length == 0) {
            revert Bytes32Helper__ZeroLengthString();
        }

        /// @solidity memory-safe-assembly
        assembly {
            result := mload(add(stringData, 32))
        }
    }

}
