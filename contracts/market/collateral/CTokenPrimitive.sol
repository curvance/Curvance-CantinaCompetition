// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenBase, SafeTransferLib, ERC4626 } from "contracts/market/collateral/CTokenBase.sol";

import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev Built to support assets that do not generate rewards in external,
///      claimable tokens. This means CTokenPrimitive is built for assets
///      such as:
///      WETH, LSTs, LRTs, PTs, UNI, USDC, sDAI, etc.
contract CTokenPrimitive is CTokenBase {
    /// ERRORS ///

    error CTokenPrimitive__RedeemMoreThanMax();
    error CTokenPrimitive__WithdrawMoreThanMax();
    error CTokenPrimitive__ZeroShares();
    error CTokenPrimitive__ZeroAssets();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_
    ) CTokenBase(centralRegistry_,  asset_, marketManager_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Helper function for Position Folding contract to
    ///         redeem assets.
    /// @param owner The owner address of assets to redeem.
    /// @param assets The amount of the underlying assets to redeem.
    function withdrawByPositionFolding(
        address owner,
        uint256 assets,
        bytes calldata params
    ) external nonReentrant {
        // Validate that the position folding contract is calling.
        if (msg.sender != marketManager.positionFolding()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Cache _totalAssets and balanceOf.
        uint256 ta = _totalAssets;
        uint256 balancePrior = balanceOf(owner);

        // We use a modified version of maxWithdraw which more directly
        // checks whether `assets` is allowed.
        if (assets > _convertToAssets(balancePrior, ta)) {
            // revert with "CTokenPrimitive__WithdrawMoreThanMax".
            _revert(0xc6e63cc0);
        }

        // No need to check for rounding error, previewWithdraw rounds up.
        uint256 shares = _previewWithdraw(assets, ta);

        // Update gauge pool values for `owner`.
        _gaugePool().withdraw(address(this), owner, shares);
        // Process withdraw on behalf of `owner`.
        _processWithdraw(msg.sender, msg.sender, owner, assets, shares, ta);

        // Callback to PositionFolding that executes cToken specific logic.
        IPositionFolding(msg.sender).onRedeem(
            address(this),
            owner,
            assets,
            params
        );

        // Fails if redeem not allowed.
        marketManager.reduceCollateralIfNecessary(
            owner,
            address(this),
            balancePrior,
            shares
        );
        // Checks whether callback or slippage has broken invariants.
        marketManager.canRedeem(address(this), owner, 0);
    }

    // PERMISSIONED FUNCTIONS

    /// @notice Starts a CToken market, executed via marketManager.
    /// @dev This initial mint is a failsafe against rounding exploits,
    ///      although, we protect against them in many ways,
    ///      better safe than sorry.
    /// @param by The account initializing the cToken market.
    /// @return Returns with true when successful.
    function startMarket(address by) external nonReentrant override returns (bool) {
        _startMarket(by);
        return true;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Deposits `assets` and mints shares to `receiver`.
    /// @param assets The amount of the underlying asset to supply.
    /// @param receiver The account that should receive the cToken shares.
    /// @return shares The amount of cToken shares received by `receiver`.
    function _deposit(
        uint256 assets,
        address receiver
    ) internal override returns (uint256 shares) {
        if (assets == 0) {
            revert CTokenPrimitive__ZeroAssets();
        }

        // Fails if deposit not allowed, this stands in for a maxDeposit
        // check reviewing isListed and mintPaused != 2.
        marketManager.canMint(address(this));

        // Cache _totalAssets.
        uint256 ta = _totalAssets;

        // Check for rounding error, since we round down in previewDeposit.
        if ((shares = _previewDeposit(assets, ta)) == 0) {
            revert CTokenPrimitive__ZeroShares();
        }

        // Execute deposit.
        _processDeposit(msg.sender, receiver, assets, shares, ta);
        // Update gauge pool values for `receiver`.
        _gaugePool().deposit(address(this), receiver, shares);
    }

    /// @notice Deposits assets and mints `shares` to `receiver`.
    /// @param shares The amount of the underlying assets quoted in shares
    ///               to supply.
    /// @param receiver The account that should receive the cToken shares.
    /// @return assets The amount of cToken shares quoted in assets received
    ///                by `receiver`.
    function _mint(
        uint256 shares,
        address receiver
    ) internal override returns (uint256 assets) {
        if (shares == 0) {
            revert CTokenPrimitive__ZeroShares();
        }

        // Fail if mint not allowed, this stands in for a maxMint
        // check reviewing isListed and mintPaused != 2.
        marketManager.canMint(address(this));

        // Cache _totalAssets.
        uint256 ta = _totalAssets;

        // No need to check for rounding error, previewMint rounds up.
        assets = _previewMint(shares, ta);

        // Execute deposit.
        _processDeposit(msg.sender, receiver, assets, shares, ta);
        // Update gauge pool values for `receiver`.
        _gaugePool().deposit(address(this), receiver, shares);
    }

    /// @notice Withdraws `assets` to `receiver` from the market and burns
    ///         `owner` shares.
    /// @param assets The amount of the underlying asset to withdraw.
    /// @param receiver The account that should receive the assets.
    /// @param owner The account that will burn their shares to withdraw
    ///              assets.
    /// @param forceRedeemCollateral Whether the collateral should be always
    ///                              reduced from `owner`'s collateralPosted.
    /// @return shares The amount of assets, quoted in shares received
    ///                by `receiver`.
    function _withdraw(
        uint256 assets,
        address receiver,
        address owner,
        bool forceRedeemCollateral
    ) internal override returns (uint256 shares) {
        // Cache _totalAssets.
        uint256 ta = _totalAssets;

        // We use a modified version of maxWithdraw which more directly
        // checks whether `assets` is allowed.
        if (assets > _convertToAssets(balanceOf(owner), ta)) {
            // revert with "CTokenPrimitive__WithdrawMoreThanMax"
            _revert(0xc6e63cc0);
        }

        // No need to check for rounding error, previewWithdraw rounds up.
        shares = _previewWithdraw(assets, ta);
        // Validate that `owner` can redeem `shares`.
        marketManager.canRedeemWithCollateralRemoval(
            address(this),
            owner,
            balanceOf(owner),
            shares,
            forceRedeemCollateral
        );

        // Update gauge pool values for `owner`.
        _gaugePool().withdraw(address(this), owner, shares);
        // Execute withdrawal.
        _processWithdraw(msg.sender, receiver, owner, assets, shares, ta);
    }

    /// @notice Redeems assets to `receiver` from the market and burns
    ///         `owner` `shares`.
    /// @param shares The amount of shares to burn to withdraw assets.
    /// @param receiver The account that should receive the assets.
    /// @param owner The account that will burn their shares to withdraw
    ///              assets.
    /// @param forceRedeemCollateral Whether the collateral should be always
    ///                              reduced from `owner`'s collateralPosted.
    /// @return assets The amount of assets received by `receiver`.
    function _redeem(
        uint256 shares,
        address receiver,
        address owner,
        bool forceRedeemCollateral
    ) internal override returns (uint256 assets) {
        // Check whether `shares` is above max allowed redemption.
        if (shares > maxRedeem(owner)) {
            // revert with "CTokenPrimitive__RedeemMoreThanMax".
            _revert(0xb1652d68);
        }

        // Validate that `owner` can redeem `shares`.
        marketManager.canRedeemWithCollateralRemoval(
            address(this),
            owner,
            balanceOf(owner),
            shares,
            forceRedeemCollateral
        );

        // Cache _totalAssets.
        uint256 ta = _totalAssets;

        // Check for rounding error, since we round down in previewRedeem.
        if ((assets = _previewRedeem(shares, ta)) == 0) {
            revert CTokenPrimitive__ZeroAssets();
        }

        // Update gauge pool values for `owner`.
        _gaugePool().withdraw(address(this), owner, shares);
        // Execute withdrawal.
        _processWithdraw(msg.sender, receiver, owner, assets, shares, ta);
    }

    /// @notice Processes a deposit of `assets` from the market and mints
    ///         shares to `owner`, then increases `ta` by `assets`.
    /// @dev Emits a {Deposit} event.
    /// @param by The account that is executing the deposit.
    /// @param to The account that should receive `shares`.
    /// @param assets The amount of the underlying asset to deposit.
    /// @param shares The amount of shares minted to `to`.
    /// @param ta The current total number of assets for assets to shares
    ///           conversion.
    function _processDeposit(
        address by,
        address to,
        uint256 assets,
        uint256 shares,
        uint256 ta
    ) internal {
        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(asset(), by, address(this), assets);

        // Document addition of `assets` to `ta` due to deposit.
        unchecked {
            _totalAssets = ta + assets;
        }

        // Mint `shares` to `to`.
        _mint(to, shares);

        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Deposit} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log3(0x00, 0x40, _DEPOSIT_EVENT_SIGNATURE, and(m, by), and(m, to))
        }
    }

    /// @notice Processes a withdrawal of `shares` from the market by burning
    ///         `owner` shares and transferring `assets` to `to`, then
    ///         decreases `ta` by `assets`.
    /// @dev Emits a {Withdraw} event.
    /// @param by The account that is executing the withdrawal.
    /// @param to The account that should receive `assets`.
    /// @param owner The account that will have `shares` burned to withdraw
    ///              `assets`.
    /// @param assets The amount of the underlying asset to withdraw.
    /// @param shares The amount of shares redeemed from `owner`.
    /// @param ta The current total number of assets for assets to shares
    ///           conversion.
    function _processWithdraw(
        address by,
        address to,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 ta
    ) internal {
        // Validate caller is allowed to withdraw `shares` on behalf of
        // `owner`.
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, by);

            if (allowed != type(uint256).max) {
                _spendAllowance(owner, by, allowed - shares);
            }
        }

        // Burn `owner` `shares`.
        _burn(owner, shares);
        // Document removal of `assets` from `ta` due to withdrawal.
        _totalAssets = ta - assets;
        // Transfer the underlying assets to `to`.
        SafeTransferLib.safeTransfer(asset(), to, assets);

        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Withdraw} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log4(
                0x00,
                0x40,
                _WITHDRAW_EVENT_SIGNATURE,
                and(m, by),
                and(m, to),
                and(m, owner)
            )
        }
    }
}
