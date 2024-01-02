// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, ICentralRegistry, IERC20 } from "contracts/market/collateral/CTokenCompounding.sol";
import { FixedPointMathLib } from "contracts/libraries/FixedPointMathLib.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev The CToken vaults run must be a LOSSLESS position, since totalAssets
///      is not actually using the balances stored in the position,
///      rather it only uses an internal balance.
abstract contract CTokenCompoundingWithExitFee is CTokenCompounding {

    /// CONSTANTS ///

    /// @notice 2% maximum exit fee configurable by DAO.
    uint256 public constant MAXIMUM_EXIT_FEE = .02e18;

    /// STORAGE ///

    // Fee for exiting a vault position, in `WAD`.
    uint256 public exitFee;

    /// EVENTS ///

    event ExitFeeSet(uint256 oldExitFee, uint256 newExitFee);

    /// ERRORS ///

    error CTokenCompoundingWithExitFee__InvalidExitFee();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address lendtroller_,
        uint256 exitFee_
    ) CTokenCompounding(centralRegistry_, asset_, lendtroller_) {
        _setExitFee(exitFee_);
    }

    /// EXTERNAL FUNCTIONS ///

    function setExitFee(uint256 newExitFee) external {
        _checkElevatedPermissions();
        _setExitFee(newExitFee);
    }

    /// INTERNAL FUNCTIONS ///

    function _removeExitFeeFromAssets(uint256 assets) internal view returns (uint256) {
        // Rounds up with an enforced minimum of assets = 1,
        // so this can never underflow.
        return assets - FixedPointMathLib.mulWadUp(exitFee, assets);
    }

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

    /// @dev Internal helper function for easily converting between scalars.
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        // multiplies by 1e14 to convert from basis points to WAD.
        return value * 100000000000000;
    }

}