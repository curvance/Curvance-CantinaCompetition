// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IRateProvider.sol";

interface IBalancerPool is IRateProvider {
    /// @dev Returns this Pool's ID, used when interacting with the Vault (to e.g. join the Pool or swap with it).
    function getPoolId() external view returns (bytes32);

    /// @dev returns the number of decimals for this vault token.
    /// For reaper single-strat vaults, the decimals are fixed to 18.
    function decimals() external view returns (uint8);

    /// @dev Returns an 18 decimal fixed point number that is the exchange rate of the token to some other underlying
    /// token. The meaning of this rate depends on the context.
    function getRate() external view returns (uint256);
}
