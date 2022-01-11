// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../external/compound/PriceOracle.sol";
import "../external/compound/CToken.sol";
import "../external/compound/CErc20.sol";

import "../external/chainlink/AggregatorV3Interface.sol";

import "../external/curve/ICurveTriCryptoLpTokenOracle.sol";

import "./BasePriceOracle.sol";

/**
 * @title CurveTriCryptoLpTokenPriceOracle
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice CurveTriCryptoLpTokenPriceOracle is a price oracle for Curve TriCrypto LP tokens.
 * @dev Implements the `PriceOracle` interface used by Fuse pools (and Compound v2).
 */
contract CurveTriCryptoLpTokenPriceOracle is PriceOracle, BasePriceOracle {
    using SafeMathUpgradeable for uint256;

    /**
     * @notice Official TriCrypto LP token price oracle deployed by Curve.
     */
    ICurveTriCryptoLpTokenOracle public constant SOURCE_ORACLE =
        ICurveTriCryptoLpTokenOracle(0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950);

    /**
     * @dev Chainlink ETH/USD price feed contract.
     */
    AggregatorV3Interface public constant ETH_USD_PRICE_FEED =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    /**
     * @notice Get the LiquidityGaugeV2 price price for an underlying token address.
     * @param underlying The underlying token address for which to get the price (set to zero address for ETH).
     * @return Price denominated in ETH (scaled by 1e18).
     */
    function price(address underlying) external view override returns (uint256) {
        return _price(underlying);
    }

    /**
     * @notice Returns the price in ETH of the token underlying `cToken`.
     * @dev Implements the `PriceOracle` interface for Fuse pools (and Compound v2).
     * @return Price in ETH of the token underlying `cToken`, scaled by `10 ** (36 - underlyingDecimals)`.
     */
    function getUnderlyingPrice(CToken cToken) external view override returns (uint256) {
        address underlying = CErc20(address(cToken)).underlying();
        // Comptroller needs prices to be scaled by 1e(36 - decimals)
        // Since `_price` returns prices scaled by 18 decimals, we must scale them by 1e(36 - 18 - decimals)
        return _price(underlying).mul(1e18).div(10**uint256(ERC20Upgradeable(underlying).decimals()));
    }

    /**
     * @dev Fetches the fair TriCrypto LP token/ETH price from Curve, with 18 decimals of precision.
     * @param gauge The LiquidityGaugeV2 contract address for price retrieval.
     */
    function _price(address gauge) internal view returns (uint256) {
        (uint80 roundId, int256 ethUsdPrice, , , uint80 answeredInRound) = ETH_USD_PRICE_FEED.latestRoundData();
        require(answeredInRound == roundId, "Chainlink round timed out.");
        return uint256(SOURCE_ORACLE.lp_price()).mul(1e8).div(uint256(ethUsdPrice));
    }
}
