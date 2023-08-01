// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "contracts/interfaces/IERC20.sol";

library CommonLib {
    
    function isETH(address token) internal pure returns (bool) {
        /// We need to check against both null address and 0xEee
        /// because each protocol uses different implementations
        address _tokenAddr = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        assembly{
            if iszero(token) {
                mstore(0,0x1)
                return(0,0x20)
            }
            if iszero(iszero(eq(token,_tokenAddr))){
                mstore(0,0x1)
                return(0,0x20)
            }
        }
        return false;
    }

    /// @dev Get token balance of this contract
    /// @param token The token address
    function getTokenBalance(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @dev Get eth balance of this contract
    function getETHBalance() internal view returns (uint256) {
        return address(this).balance;
    }
}
