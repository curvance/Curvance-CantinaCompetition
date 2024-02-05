// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICVE {
    /// @notice Sets allowance of `spender` over the caller's tokens.
    /// @dev Included here so we don't need to recast to IERC20.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Mints gauge emissions for the desired gauge pool.
    /// @dev Only callable by the ProtocolMessagingHub.
    /// @param gaugePool The address of the gauge pool where emissions will be
    ///                  configured.
    /// @param amount The amount of gauge emissions to be minted.
    function mintGaugeEmissions(address gaugePool, uint256 amount) external;

    /// @notice Mints CVE to the calling gauge pool to fund the users
    ///         lock boost.
    /// @param amount The amount of tokens to be minted.
    function mintLockBoost(uint256 amount) external;

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
