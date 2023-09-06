//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICurveSwap {
    function coins(int128 arg0) external view returns (address);

    function underlying_coins(int128 arg0) external view returns (address);

    function add_liquidity(
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function add_liquidity(
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function remove_liquidity(
        uint256 amount,
        uint256[2] calldata min_amounts
    ) external;

    function remove_liquidity(
        uint256 amount,
        uint256[3] calldata min_amounts
    ) external;

    function remove_liquidity(
        uint256 amount,
        uint256[4] calldata min_amounts
    ) external;

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external;

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        uint256 i,
        uint256 min_amount
    ) external;
}

interface ICurveEthSwap {
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external payable returns (uint256);
}
