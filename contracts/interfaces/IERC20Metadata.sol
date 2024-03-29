// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "contracts/interfaces/IERC20.sol";

// @dev Interface for the optional metadata functions from the ERC-20 standard.
interface IERC20Metadata is IERC20 {

    //@dev Returns the name of the token.
    function name() external view returns (string memory);

    // @dev Returns the name of the token.
    function symbol() external view returns (string memory);

    // @dev Returns the decimals places of the token.
    function decimals() external view returns (uint8);
}