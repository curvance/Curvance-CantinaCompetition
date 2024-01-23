// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Return data from oracle adaptor.
/// @param price the price of the asset in some asset, either ETH or USD.
/// @param hadError the message return data, whether the adaptor ran into
///                 trouble pricing the asset.
/// @param inUsd bool indicating whether the price feed is denominated
///              in USD(true) or ETH(false).
struct PriceReturnData {
    uint240 price;
    bool hadError;
    bool inUSD;
}

interface IOracleAdaptor {
    /// @notice Called by OracleRouter to price an asset.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return PriceReturnData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view returns (PriceReturnData memory);

    /// @notice Asset => Supported by adaptor.
    function isSupportedAsset(address asset) external view returns (bool);
}
