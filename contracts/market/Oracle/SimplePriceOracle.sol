// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./PriceOracle.sol";
import "contracts/market/collateral/CErc20.sol";

contract SimplePriceOracle is PriceOracle {
    mapping(address => uint256) public prices;
    event PricePosted(
        address asset,
        uint256 previousPriceMantissa,
        uint256 requestedPriceMantissa,
        uint256 newPriceMantissa
    );

    /// @notice returns underlying asset address of given market token
    /// @param cToken market token address
    /// @return The underlying asset address
    function _getUnderlyingAddress(
        CToken cToken
    ) private view returns (address) {
        address asset;
        if (compareStrings(cToken.symbol(), "cETH")) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = address(CErc20(address(cToken)).underlying());
        }
        return asset;
    }

    /// @notice returns underlying asset price of given market token
    /// @param cToken market token address
    /// @return The underlying asset price
    function getUnderlyingPrice(
        CToken cToken
    ) public view override returns (uint256) {
        return prices[_getUnderlyingAddress(cToken)];
    }

    /// @notice set underlying asset price of given market token
    /// @param cToken market token address
    /// @param underlyingPriceMantissa underlying asset price
    function setUnderlyingPrice(
        CToken cToken,
        uint256 underlyingPriceMantissa
    ) public {
        address asset = _getUnderlyingAddress(cToken);
        emit PricePosted(
            asset,
            prices[asset],
            underlyingPriceMantissa,
            underlyingPriceMantissa
        );
        prices[asset] = underlyingPriceMantissa;
    }

    /// @notice set direct price of given asset
    /// @param asset asset address
    /// @param price asset price
    function setDirectPrice(address asset, uint256 price) public {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    /// @notice returns the asset price
    /// @param asset asset address
    /// @return The asset price
    function assetPrices(address asset) external view returns (uint256) {
        return prices[asset];
    }

    /// @notice check if two given strings match
    /// @param a first string
    /// @param b second string
    /// @return true if two strings match or not
    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }
}
