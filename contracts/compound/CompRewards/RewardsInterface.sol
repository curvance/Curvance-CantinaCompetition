// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../Token/CToken.sol";

abstract contract RewardsInterface {
    ////////// EVENTS //////////
    /// @notice Emitted when a new COMP speed is calculated for a market
    event CveSpeedUpdated(CToken indexed cToken, uint256 newSpeed);
    /// @notice Emitted when a new COMP speed is set for a contributor
    event ContributorCveSpeedUpdated(address indexed contributor, uint256 newSpeed);
    /// @notice Emitted when COMP is distributed to a supplier
    event DistributedSupplierCve(
        CToken indexed cToken,
        address indexed supplier,
        uint256 cveDelta,
        uint256 cveSupplyIndex
    );
    /// @notice Emitted when COMP is distributed to a borrower
    event DistributedBorrowerCve(
        CToken indexed cToken,
        address indexed borrower,
        uint256 cveDelta,
        uint256 cveBorrowIndex
    );
    /// @notice Emitted when COMP is granted by admin
    event CveGranted(address recipient, uint256 amount);

    function updateCveSupplyIndexExternal(address cTokenCollateral) external virtual;

    function distributeSupplierCveExternal(address cTokenCollateral, address claimer) external virtual;
}
