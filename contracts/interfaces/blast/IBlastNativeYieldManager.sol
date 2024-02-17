// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBlastNativeYieldManager {
    /// @notice Claims delegated yield on behalf of the caller. Will natively
    ///         revert if not delegated. Transfers rewards to governee
    /// @dev Only callable by governee themself. Natively claims gas rebate.
    /// @param marketManager The Market Manager associated with the mToken
    ///                      managing it native yield.
    /// @param claimWETHYield Whether WETH native yield should be claimed.
    /// @param claimUSDBYield Whether USDB native yield should be claimed.
    /// @return WETHYield The amount of WETH yield claimed.
    /// @return USDBYield The amount of USDB yield claimed.
    function claimYieldForAutoCompounding(
        address marketManager,
        bool claimWETHYield,
        bool claimUSDBYield
    ) external returns (uint256, uint256);
    /// @notice Called by the Central registry on updating isMarketManager on Blast.
    /// @dev Only callable by Curvance Central Registry.
    /// @param notifiedMarketManager The Market Manager contract to modify support
    ///                              for use in Curvance Yield Manager.
    function notifyIsMarketManager(
        address notifiedMarketManager,
        bool isSupported
    ) external;
    /// @notice Used by Curvance mTokens to notify the Yield Manager native
    ///         yield has been claimed to the Yield Manager.
    /// @param marketManager The Market Manager contract associated with
    ///                      calling Curvance mToken.
    function notifyNativeYieldRewards(
        address marketManager,
        uint256 amount
    ) external;
    /// @notice Helper function to view pending gas yield available for claim.
    /// @dev Returns 0 if the Yield Manager is not a governor of
    ///      `delegatedAddress`.
    /// @param delegatedAddress The address to check pending gas fees for.
    /// @return The pending claimable native yield.
    function getClaimableNativeYield(
        address delegatedAddress
    ) external view returns (uint256);
    /// @notice Claims all pending native yield available for a contract
    ///         inside Curvance.
    /// @dev mTokens cannot be called by this.
    /// @param delegatedAddresses The address to claim pending gas fees for.
    function claimPendingNativeYield(
        address[] calldata delegatedAddresses
    ) external;
}