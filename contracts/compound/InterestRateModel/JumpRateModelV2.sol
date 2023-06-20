// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BaseJumpRateModelV2.sol";
import "./InterestRateModel.sol";

/**
 * @title Curvance's JumpRateModel Contract V2 for V2 cTokens
 * @author Curvance
 * @notice Supports only for V2 cTokens
 */
contract JumpRateModelV2 is InterestRateModel, BaseJumpRateModelV2 {
    constructor(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_,
        address owner_
    ) BaseJumpRateModelV2(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_, owner_) {}

    /**
     * @notice Calculates the current borrow rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view override returns (uint256) {
        return getBorrowRateInternal(cash, borrows, reserves);
    }
}
