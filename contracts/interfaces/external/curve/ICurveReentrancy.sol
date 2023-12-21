//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICurveRemoveLiquidity {
    /// As with balancer re-entry check, we add a maximum
    /// gas allocation meaning no writing should take place, 
    /// so we can mark these as view functions
    function remove_liquidity(
        uint256 _tokenAmount,
        uint256[2] calldata _amounts
    ) external view;

    function remove_liquidity(
        uint256 _tokenAmount,
        uint256[3] calldata _amounts
    ) external view;

    function remove_liquidity(
        uint256 _tokenAmount,
        uint256[4] calldata _amounts
    ) external view;
}
