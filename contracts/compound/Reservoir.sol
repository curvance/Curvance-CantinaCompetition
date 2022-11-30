// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IEIP20.sol";

/**
 * @title Reservoir Contract
 * @notice Distributes a token to a different contract at a fixed rate.
 * @dev This contract must be poked via the `drip()` function every so often.
 * @author Compound
 */
contract Reservoir {
    error MathError();

    /// @notice The block number when the Reservoir started (immutable)
    uint256 public dripStart;

    /// @notice Tokens per block that to drip to target (immutable)
    uint256 public dripRate;

    /// @notice Reference to token to drip (immutable)
    IEIP20 public token;

    /// @notice Target to receive dripped tokens (immutable)
    address public target;

    /// @notice Amount that has already been dripped
    uint256 public dripped;

    /**
     * @notice Constructs a Reservoir
     * @param dripRate_ Numer of tokens per block to drip
     * @param token_ The token to drip
     * @param target_ The recipient of dripped tokens
     */
    constructor(
        uint256 dripRate_,
        IEIP20 token_,
        address target_
    ) {
        dripStart = block.number;
        dripRate = dripRate_;
        token = token_;
        target = target_;
        dripped = 0;
    }

    /**
     * @notice Drips the maximum amount of tokens to match the drip rate since inception
     * @dev Note: this will only drip up to the amount of tokens available.
     * @return The amount of tokens dripped in this call
     */
    function drip() public returns (uint256) {
        // First, read storage into memory
        IEIP20 token_ = token;
        uint256 reservoirBalance_ = token_.balanceOf(address(this));
        uint256 dripRate_ = dripRate;
        uint256 dripStart_ = dripStart;
        uint256 dripped_ = dripped;
        address target_ = target;
        uint256 blockNumber_ = block.number;

        // Next, calculate intermediate values
        uint256 dripTotal_ = dripRate_ * (blockNumber_ - dripStart_);
        uint256 deltaDrip_ = dripTotal_ - dripped_;
        uint256 toDrip_ = min(reservoirBalance_, deltaDrip_);
        uint256 drippedNext_ = dripped_ + toDrip_;

        // Finally, write new `dripped` value and transfer tokens to target
        dripped = drippedNext_;
        token_.transfer(target_, toDrip_);

        return toDrip_;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a <= b) {
            return a;
        } else {
            return b;
        }
    }
}
