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

    /// @notice Mint an amount of token for user.
    /// @dev It will be called by only ProtocolMessagingHub.
    ///      This function is used only for bridging VeCVE lock.
    /// @param user The address of user to receive token.
    /// @param amount The amount of token to mint.
    function mint(address user, uint256 amount) external;

    /// @notice Burn an amount of token for user.
    /// @dev It will be called by only ProtocolMessagingHub.
    ///      This function is used only for bridging VeCVE lock.
    /// @param user The address of user to burn token.
    /// @param amount The amount of token to burn.
    function burn(address user, uint256 amount) external;
}
