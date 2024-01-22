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

    /// @notice Mint CVE to msg.sender, 
    ///         which will always be the VeCVE contract.
    /// @dev Only callable by the ProtocolMessagingHub.
    ///      This function is used only for creating a bridged VeCVE lock.
    /// @param amount The amount of token to mint for the new veCVE lock.
    function mintVeCVELock(uint256 amount) external;

    /// @notice Burn CVE from msg.sender, 
    ///         which will always be the VeCVE contract.
    /// @dev Only callable by VeCVE.
    ///      This function is used only for bridging VeCVE lock.
    /// @param amount The amount of token to burn for a bridging veCVE lock.
    function burnVeCVELock(uint256 amount) external;
}
