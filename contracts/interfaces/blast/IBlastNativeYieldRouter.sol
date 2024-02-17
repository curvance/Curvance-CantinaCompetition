// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBlastNativeYieldRouter {
    /// @notice Called by the Central registry on updating isMarketManager on Blast.
    /// @dev Only callable by Curvance Central Registry.
    /// @param notifiedMarketManager The Market Manager contract to modify support
    ///                              for use in Curvance Yield Manager.
    function notifyIsMarketManager(address notifiedMarketManager, bool isSupported) external;
    /// @notice Helper function to view pending gas yield available for claim.
    /// @dev Returns 0 if the Yield Router is not a governor of `delegatedAddress`.
    /// @param delegatedAddress The address to check pending gas fees for.
    /// @return The pending claimable native yield.
    function getClaimableNativeYield(address delegatedAddress) external view returns (uint256);
}