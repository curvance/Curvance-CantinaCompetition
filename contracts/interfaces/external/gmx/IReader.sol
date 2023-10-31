//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IReader {
    /// TYPES ///

    // @param marketToken address of the market token for the market
    // @param indexToken address of the index token for the market
    // @param longToken address of the long token for the market
    // @param shortToken address of the short token for the market
    struct MarketProps {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }

    // @param min the min price
    // @param max the max price
    struct PriceProps {
        uint256 min;
        uint256 max;
    }

    // @dev struct to avoid stack too deep errors for the getPoolValue call
    // @param poolValue the pool value
    // @param longPnl the pending pnl of long positions
    // @param shortPnl the pending pnl of short positions
    // @param netPnl the net pnl of long and short positions
    // @param longTokenAmount the amount of long token in the pool
    // @param shortTokenAmount the amount of short token in the pool
    // @param longTokenUsd the USD value of the long tokens in the pool
    // @param shortTokenUsd the USD value of the short tokens in the pool
    // @param totalBorrowingFees the total pending borrowing fees for the market
    // @param borrowingFeePoolFactor the pool factor for borrowing fees
    // @param impactPoolAmount the amount of tokens in the impact pool
    struct InfoProps {
        int256 poolValue;
        int256 longPnl;
        int256 shortPnl;
        int256 netPnl;
        uint256 longTokenAmount;
        uint256 shortTokenAmount;
        uint256 longTokenUsd;
        uint256 shortTokenUsd;
        uint256 totalBorrowingFees;
        uint256 borrowingFeePoolFactor;
        uint256 impactPoolAmount;
    }

    /// FUNCTIONS ///

    function getMarket(
        address dataStore,
        address key
    ) external view returns (MarketProps memory);

    // @dev get the market token's price
    // @param dataStore DataStore
    // @param market the market to check
    // @param longTokenPrice the price of the long token
    // @param shortTokenPrice the price of the short token
    // @param indexTokenPrice the price of the index token
    // @param maximize whether to maximize or minimize the market token price
    // @return returns (the market token's price, MarketPoolValueInfo.Props)
    function getMarketTokenPrice(
        address dataStore,
        MarketProps memory market,
        PriceProps memory indexTokenPrice,
        PriceProps memory longTokenPrice,
        PriceProps memory shortTokenPrice,
        bytes32 pnlFactorType,
        bool maximize
    ) external view returns (int256, InfoProps memory);
}
