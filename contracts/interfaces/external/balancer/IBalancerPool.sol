// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

interface IBalancerPool {
    function getMainToken() external view returns (address);

    /// @dev Returns an 18 decimal fixed point number that is the exchange rate of the token to some other underlying
    /// token. The meaning of this rate depends on the context.
    function getRate() external view returns (uint256);

    function getInvariant() external view returns (uint256);

    function getLastInvariant() external view returns (uint256);

    function getFinalTokens() external view returns (address[] memory);

    function getNormalizedWeight(address token)
        external
        view
        returns (uint256);

    function getNormalizedWeights() external view returns (uint256[] memory);

    function getSwapFee() external view returns (uint256);

    function getNumTokens() external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    /// @dev Returns this Pool's ID, used when interacting with the Vault (to e.g. join the Pool or swap with it).
    function getPoolId() external view returns (bytes32);

    /// @dev returns the number of decimals for this vault token.
    /// For reaper single-strat vaults, the decimals are fixed to 18.
    function decimals() external view returns (uint8);

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
        external;
}
