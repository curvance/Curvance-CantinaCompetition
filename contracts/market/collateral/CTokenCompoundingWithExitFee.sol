// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, FixedPointMathLib, ICentralRegistry, IERC20 } from "contracts/market/collateral/CTokenCompounding.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev The CToken vaults run must be a LOSSLESS position, since totalAssets
///      is not actually using the balances stored in the position,
///      rather it only uses an internal balance.
abstract contract CTokenCompoundingWithExitFee is CTokenCompounding {

    /// CONSTANTS ///

    /// @notice Maximum exit fee configurable by DAO.
    ///         .02e18 = 2%.
    uint256 public constant MAXIMUM_EXIT_FEE = .02e18;

    /// STORAGE ///

    /// @notice Fee for exiting a vault position, in `WAD`.
    uint256 public exitFee;

    /// EVENTS ///

    event ExitFeeSet(uint256 oldExitFee, uint256 newExitFee);

    /// ERRORS ///

    error CTokenCompoundingWithExitFee__InvalidExitFee();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        uint256 exitFee_
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        _setExitFee(exitFee_);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Permissioned function for setting the exit fee on redemption
    ///         of shares for assets.
    /// @dev Parameter passed in basis points and converted to `WAD`.
    ///      Has a maximum value of `MAXIMUM_EXIT_FEE`.
    /// @param newExitFee The new exit fee to set for redemption of assets,
    ///                   in basis points.
    function setExitFee(uint256 newExitFee) external {
        _checkElevatedPermissions();
        _setExitFee(newExitFee);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Efficient internal calculation of `assets`
    ///         with corresponding exit fee removed.
    /// @param assets The number of assets to remove exit fee from.
    /// @return The number of assets remaining after removing the exit fee.
    function _removeExitFeeFromAssets(uint256 assets) internal view returns (uint256) {
        // Rounds up with an enforced minimum of assets = 1,
        // so this can never underflow.
        return assets - FixedPointMathLib.mulDivUp(exitFee, assets, 1e18);
    }

    /// @notice Processes a withdrawal of `shares` from the market by burning
    ///         `owner` shares and transferring `assets` minus proportional
    ///         `exitFee` to `to`, then  decreases `ta` by post exit fee
    ///         `assets`, and vests rewards if `pending` > 0.
    /// @param by The account that is executing the withdrawal.
    /// @param to The account that should receive `assets`.
    /// @param owner The account that will have `shares` burned to withdraw `assets`.
    /// @param assets The amount of the underlying asset to withdraw,
    ///               prior to exit fee being applied.
    /// @param shares The amount of shares redeemed from `owner`.
    /// @param ta The current total number of assets for assets to shares conversion.
    /// @param pending The current rewards that are pending and will be vested
    ///                during this withdrawal.
    function _processWithdraw(
        address by,
        address to,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 ta,
        uint256 pending
    ) internal override {
        // We remove the fees directly from the assets a user,
        // will receive distributing fee paid to all users.
        assets = _removeExitFeeFromAssets(assets);
        super._processWithdraw(by, to, owner, assets, shares, ta, pending);
    }

    /// @notice Helper function for setting the exit fee on redemption
    ///         of shares for assets.
    /// @dev Parameter passed in basis points and converted to `WAD`.
    ///      Has a maximum value of `MAXIMUM_EXIT_FEE`. 
    /// @param newExitFee The new exit fee to set for redemption of assets,
    ///                   in basis points.
    function _setExitFee(uint256 newExitFee) internal {
        // Convert `newExitFee` parameter from `basis points` to `WAD`.
        newExitFee = _bpToWad(newExitFee);

        // Check if the proposed exit fee is above the allowed maximum.
        if (newExitFee > MAXIMUM_EXIT_FEE) {
            revert CTokenCompoundingWithExitFee__InvalidExitFee();
        }

        // Cache the old exit fee for event emission.
        uint256 oldExitFee = exitFee;

        // Set new exit fee.
        exitFee = newExitFee;
        emit ExitFeeSet(oldExitFee, newExitFee);
    }

    /// @notice Multiplies `value` by 1e14 to convert it from `basis points`
    ///         to WAD.
    /// @dev Internal helper function for easily converting between scalars.
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        return value * 1e14;
    }

}