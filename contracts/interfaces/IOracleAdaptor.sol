// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

/**
 * @notice Return data from oracle adaptor
 * @param price the price of the asset in some asset, either ETH or USD
 * @param hadError the message return data, whether the adaptor ran into trouble pricing the asset
 * @param inUsd bool indicating whether the price feed is denominated in USD(true) or ETH(false)
 */
struct priceReturnData {
    uint240 price;
    bool hadError;
    bool inUSD;
}

interface IOracleAdaptor {
    // @notice queries price from an oracle adaptor
    function getPrice(address _asset)
        external
        view
        returns (priceReturnData memory);
}
