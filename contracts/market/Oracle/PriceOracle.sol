// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICToken } from "contracts/interfaces/market/ICToken.sol";

abstract contract PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice Get the underlying price of a cToken asset
    /// @param cToken The cToken to get the underlying price of
    /// @return The underlying asset price mantissa (scaled by 1e18).
    ///  Zero means the price is unavailable.
    function getUnderlyingPrice(
        ICToken cToken
    ) external view virtual returns (uint256);
}
