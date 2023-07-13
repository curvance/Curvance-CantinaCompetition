// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

contract MockLendtroller {
    mapping(address => bool) private marketListed;

    function setMarket(address market, bool listed) external {
        marketListed[market] = listed;
    }

    function getIsMarkets(address market)
        external
        view
        returns (
            bool,
            uint256,
            bool
        )
    {
        return (marketListed[market], 0, false);
    }
}
