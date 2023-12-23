// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICVE {
    /// @notice Used by protocol messaging hub to mint gauge emissions for
    ///         the upcoming epoch
    function mintGaugeEmissions(address gaugePool, uint256 amount) external;

    /// @notice Used by gauge pools to mint CVE for a users lock boost
    function mintLockBoost(uint256 amount) external;

    /// @notice Sets allowance of `spender` over the caller's tokens.
    function approve(address spender, uint256 amount) external returns (bool);
}
