// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IMaker.sol";
import "./JumpRateModelV2.sol";
import "./JugLike.sol";

/**
 * @title Curvance's DAIInterestRateModel Contract (version 3)
 * @author Curvance (modified by Dharma Labs)
 * @notice The parameterized model described in section 2.4 of the original Curvance Protocol whitepaper.
 * Version 3 modifies the interest rate model in Version 2 by increasing the initial "gap" or slope of
 * the model prior to the "kink" from 2% to 4%, and enabling updateable parameters.
 */
contract DAIInterestRateModelV3 is JumpRateModelV2 {
    uint256 private constant BASE = 1e18;
    uint256 private constant RAY_BASE = 1e27;
    uint256 private constant RAY_TO_BASE_SCALE = 1e9;
    uint256 private constant SECONDS_PER_BLOCK = 15;

    /**
     * @notice The additional margin per block separating the base borrow rate from the roof.
     */
    uint256 public gapPerBlock;

    /**
     * @notice The assumed (1 - reserve factor) used to calculate the minimum borrow rate (reserve factor = 0.05)
     */
    uint256 public constant assumedOneMinusReserveFactorMantissa = 0.95e18;

    PotLike internal pot;
    JugLike internal jug;

    /**
     * @notice Construct an interest rate model
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     * @param pot_ The address of the Dai pot (where DSR is earned)
     * @param jug_ The address of the Dai jug (where SF is kept)
     * @param owner_ The address of the owner,
     *   i.e. the Timelock contract (which has the ability to update parameters directly)
     */
    constructor(
        uint256 jumpMultiplierPerYear,
        uint256 kink_,
        address pot_,
        address jug_,
        address owner_
    ) JumpRateModelV2(0, 0, jumpMultiplierPerYear, kink_, owner_) {
        gapPerBlock = 4e16 / blocksPerYear;
        pot = PotLike(pot_);
        jug = JugLike(jug_);
        poke();
    }

    /**
     * @notice External function to update the parameters of the interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by BASE).
     *   For DAI, this is calculated from DSR and SF. Input not used.
     * @param gapPerYear The Additional margin per year separating the base borrow rate from the roof. (scaled by BASE)
     * @param jumpMultiplierPerYear The jumpMultiplierPerYear after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModel(
        uint256 baseRatePerYear,
        uint256 gapPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) external override {
        // require(msg.sender == owner, "only the owner may call this function.");
        if (msg.sender != owner) {
            revert AddressUnauthorized();
        }
        gapPerBlock = gapPerYear / blocksPerYear;
        updateJumpRateModelInternal(0, 0, jumpMultiplierPerYear, kink_);
        poke();
    }

    /**
     * @notice Calculates the current supply interest rate per block including the Dai savings rate
     * @param cash The total amount of cash the market has
     * @param borrows The total amount of borrows the market has outstanding
     * @param reserves The total amnount of reserves the market has
     * @param reserveFactorMantissa The current reserve factor the market has
     * @return The supply rate per block (as a percentage, and scaled by BASE)
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    )
        public
        view
        override(BaseJumpRateModelV2, InterestRateModel)
        returns (uint256)
    {
        uint256 protocolRate = super.getSupplyRate(
            cash,
            borrows,
            reserves,
            reserveFactorMantissa
        );

        uint256 underlying = cash + borrows - reserves;
        if (underlying == 0) {
            return protocolRate;
        } else {
            uint256 cashRate = (cash * dsrPerBlock()) / underlying;
            return cashRate + protocolRate;
        }
    }

    /**
     * @notice Calculates the Dai savings rate per block
     * @return The Dai savings rate per block (as a percentage, and scaled by BASE)
     */
    function dsrPerBlock() public view returns (uint256) {
        // scaled RAY_BASE aka RAY, and includes an extra "ONE" before subtraction // descale to BASE // seconds per block
        return
            ((pot.dsr() - RAY_BASE) / RAY_TO_BASE_SCALE) * SECONDS_PER_BLOCK;
    }

    /**
     * @notice Resets the baseRate and multiplier per block based on the stability fee and Dai savings rate
     */
    function poke() public {
        (uint256 duty, ) = jug.ilks("ETH-A");
        uint256 stabilityFeePerBlock = ((duty + jug.base() - RAY_BASE) /
            RAY_TO_BASE_SCALE) * SECONDS_PER_BLOCK;

        // We ensure the minimum borrow rate >= DSR / (1 - reserve factor)
        baseRatePerBlock =
            (dsrPerBlock() * BASE) /
            assumedOneMinusReserveFactorMantissa;

        // The roof borrow rate is max(base rate, stability fee) + gap, from which we derive the slope
        if (baseRatePerBlock < stabilityFeePerBlock) {
            multiplierPerBlock =
                ((stabilityFeePerBlock - baseRatePerBlock + gapPerBlock) *
                    BASE) /
                kink;
        } else {
            multiplierPerBlock = (gapPerBlock * BASE) / kink;
        }

        emit NewInterestParams(
            baseRatePerBlock,
            multiplierPerBlock,
            jumpMultiplierPerBlock,
            kink
        );
    }
}
