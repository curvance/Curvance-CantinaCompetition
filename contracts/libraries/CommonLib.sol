// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "contracts/interfaces/IERC20.sol";

library CommonLib {

    /// @notice Returns whether `token` is referring to network gas token
    ///         or not.
    /// @param token The address to inspect.
    /// @return Whether `token` is referring to network gas token or not.
    function isETH(address token) internal pure returns (bool) {
        return
            token == address(0) ||
            token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

    /// @notice Returns balance of `token` for this contract.
    /// @param token The token address.
    /// @return The balance of `token` inside address(this).
    function getTokenBalance(address token) internal view returns (uint256) {
        if (isETH(token)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }
}
