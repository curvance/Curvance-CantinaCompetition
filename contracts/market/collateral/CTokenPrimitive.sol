// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenBase, SafeTransferLib, ERC4626 } from "contracts/market/collateral/CTokenBase.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { Math } from "contracts/libraries/Math.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
contract CTokenPrimitive is CTokenBase {
    using Math for uint256;

    /// ERRORS ///

    error CTokenPrimitive__DepositMoreThanMax();
    error CTokenPrimitive__MintMoreThanMax();
    error CTokenPrimitive__RedeemMoreThanMax();
    error CTokenPrimitive__WithdrawMoreThanMax();
    error CTokenPrimitive__ZeroShares();
    error CTokenPrimitive__ZeroAssets();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address lendtroller_
    ) CTokenBase(centralRegistry_,  asset_, lendtroller_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Helper function for Position Folding contract to
    ///         redeem assets
    /// @param owner The owner address of assets to redeem
    /// @param assets The amount of the underlying assets to redeem
    function withdrawByPositionFolding(
        address owner,
        uint256 assets,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Save _totalAssets to memory
        uint256 ta = _totalAssets;
        uint256 balancePrior = balanceOf(owner);

        // We use a modified version of maxWithdraw with newly vested assets
        if (assets > _convertToAssets(balancePrior, ta)) {
            // revert with "CTokenPrimitive__WithdrawMoreThanMax"
            _revert(0xc6e63cc0);
        }

        // No need to check for rounding error, previewWithdraw rounds up
        uint256 shares = _previewWithdraw(assets, ta);

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
        _processWithdraw(msg.sender, msg.sender, owner, assets, shares, ta);

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            owner,
            assets,
            params
        );

        // Fail if redeem not allowed
        lendtroller.reduceCollateralIfNecessary(
            owner,
            address(this),
            balancePrior,
            shares
        );
        lendtroller.canRedeem(address(this), owner, 0);
    }

    // PERMISSIONED FUNCTIONS

    /// @notice Used to start a CToken market, executed via lendtroller
    /// @dev This initial mint is a failsafe against the empty market exploit
    ///      although we protect against it in many ways,
    ///      better safe than sorry
    /// @param by The account initializing the market
    function startMarket(address by) external nonReentrant override returns (bool) {
        _startMarket(by);
        return true;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Caller deposits assets into the market and receives shares
    /// @param assets The amount of the underlying asset to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return shares the amount of cToken shares received by `receiver`
    function _deposit(
        uint256 assets,
        address receiver
    ) internal override returns (uint256 shares) {
        if (assets == 0) {
            revert CTokenPrimitive__ZeroAssets();
        }

        if (assets > maxDeposit(receiver)) {
            // revert with "CTokenPrimitive__DepositMoreThanMax"
            _revert(0xc4c35f89);
        }

        // Fail if deposit not allowed
        lendtroller.canMint(address(this));

        // Save _totalAssets to memory
        uint256 ta = _totalAssets;

        // Check for rounding error since we round down in previewDeposit
        if ((shares = _previewDeposit(assets, ta)) == 0) {
            revert CTokenPrimitive__ZeroShares();
        }

        _processDeposit(msg.sender, receiver, assets, shares, ta);
        // emit events on gauge pool
        _gaugePool().deposit(address(this), receiver, shares);
    }

    /// @notice Caller deposits assets into the market and receives shares
    /// @param shares The amount of the underlying assets quoted in shares to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return assets the amount of cToken shares quoted in assets received by `receiver`
    function _mint(
        uint256 shares,
        address receiver
    ) internal override returns (uint256 assets) {
        if (shares == 0) {
            revert CTokenPrimitive__ZeroShares();
        }

        if (shares > maxMint(receiver)) {
            // revert with "CTokenPrimitive__MintMoreThanMax"
            _revert(0xb03d0ce7);
        }

        // Fail if mint not allowed
        lendtroller.canMint(address(this));

        // Save _totalAssets to memory
        uint256 ta = _totalAssets;

        // No need to check for rounding error, previewMint rounds up
        assets = _previewMint(shares, ta);

        _processDeposit(msg.sender, receiver, assets, shares, ta);
        // emit events on gauge pool
        _gaugePool().deposit(address(this), receiver, shares);
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @param assets The amount of the underlying asset to withdraw
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @param forceRedeemCollateral Whether the collateral should be always reduced
    /// @return shares The amount of cToken shares redeemed by `owner`
    function _withdraw(
        uint256 assets,
        address receiver,
        address owner,
        bool forceRedeemCollateral
    ) internal override returns (uint256 shares) {
        // Save _totalAssets to memory
        uint256 ta = _totalAssets;

        // We use a modified version of maxWithdraw with newly vested assets
        if (assets > _convertToAssets(balanceOf(owner), ta)) {
            // revert with "CTokenPrimitive__WithdrawMoreThanMax"
            _revert(0xc6e63cc0);
        }

        // No need to check for rounding error, previewWithdraw rounds up
        shares = _previewWithdraw(assets, ta);
        lendtroller.canRedeemWithCollateralRemoval(
            address(this),
            owner,
            balanceOf(owner),
            shares,
            forceRedeemCollateral
        );

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
        _processWithdraw(msg.sender, receiver, owner, assets, shares, ta);
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @param shares The amount of shares to burn to withdraw assets
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @param forceRedeemCollateral Whether the collateral should be always reduced
    /// @return assets The amount of assets received by `receiver`
    function _redeem(
        uint256 shares,
        address receiver,
        address owner,
        bool forceRedeemCollateral
    ) internal override returns (uint256 assets) {
        if (shares > maxRedeem(owner)) {
            // revert with "CTokenPrimitive__RedeemMoreThanMax"
            _revert(0xb1652d68);
        }

        lendtroller.canRedeemWithCollateralRemoval(
            address(this),
            owner,
            balanceOf(owner),
            shares,
            forceRedeemCollateral
        );

        // Save _totalAssets to memory
        uint256 ta = _totalAssets;

        // Check for rounding error since we round down in previewRedeem
        if ((assets = _previewRedeem(shares, ta)) == 0) {
            revert CTokenPrimitive__ZeroAssets();
        }

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
        _processWithdraw(msg.sender, receiver, owner, assets, shares, ta);
    }

    function _processDeposit(
        address by,
        address to,
        uint256 assets,
        uint256 shares,
        uint256 ta
    ) internal {
        // Need to transfer before minting or ERC777s could reenter
        SafeTransferLib.safeTransferFrom(asset(), by, address(this), assets);

        // update asset invariant
        unchecked {
            _totalAssets = ta + assets;
        }

        // Mint the users shares
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

    function _processWithdraw(
        address by,
        address to,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 ta
    ) internal {
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, by);

            if (allowed != type(uint256).max) {
                _spendAllowance(owner, by, allowed - shares);
            }
        }

        // Burn the owners shares
        _burn(owner, shares);
        // Update asset invariant
        _totalAssets = ta - assets;
        // Transfer the underlying assets
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
