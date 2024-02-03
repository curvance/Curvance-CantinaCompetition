// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenBase, FixedPointMathLib, SafeTransferLib, ERC4626 } from "contracts/market/collateral/CTokenBase.sol";

import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev The CToken vaults run must be a LOSSLESS position, since totalAssets
///      is not actually using the balances stored in the contract,
///      rather it only uses an internal balance.
abstract contract CTokenCompounding is CTokenBase {
    /// TYPES ///

    /// @param rewardRate The rate that the vault vests fresh rewards.
    /// @param vestingPeriodEnd When the current vesting period ends.
    /// @param lastVestClaim Last time vesting rewards were claimed.
    struct VaultData {
        uint128 rewardRate;
        uint64 vestingPeriodEnd;
        uint64 lastVestClaim;
    }

    /// @param updateNeeded Whether there is a pending update to vault
    ///                     vesting schedule.
    /// @param newVestPeriod The pending new compounding vesting schedule.
    struct NewVestingData {
        bool updateNeeded;
        uint248 newVestPeriod;
    }

    /// CONSTANTS ///

    /// @dev Mask of reward rate entry in packed vault data.
    uint256 private constant _BITMASK_REWARD_RATE = (1 << 128) - 1;
    /// @dev Mask of a timestamp entry in packed vault data.
    uint256 private constant _BITMASK_TIMESTAMP = (1 << 64) - 1;
    /// @dev Mask of all bits in packed vault data except the 64 bits
    ///      for `lastVestClaim`.
    uint256 private constant _BITMASK_LAST_CLAIM_COMPLEMENT = (1 << 192) - 1;
    /// @dev The bit position of `vestingPeriodEnd` in packed vault data.
    uint256 private constant _BITPOS_VEST_END = 128;
    /// @dev The bit position of `lastVestClaim` in packed vault data.
    uint256 private constant _BITPOS_LAST_VEST = 192;

    /// STORAGE ///

    /// @notice The period of time harvested rewards are vested over,
    ///         in seconds.
    uint256 public vestPeriod = 1 days;
    /// @notice Whether there is a pending update to vesting period,
    ///         after this vesting period ends.
    NewVestingData public pendingVestUpdate;
    /// @notice Whether compounding is currently paused. 
    /// @dev Starts paused until market started, 1 = unpaused; 2 = paused.
    uint256 public compoundingPaused = 2;

    /// Internal packed vault accounting data.
    /// @dev Bits Layout:
    /// - [0..127]    `rewardRate`
    /// - [128..191]  `vestingPeriodEnd`
    /// - [192..255] `lastVestClaim`
    uint256 internal _vaultData;

    /// EVENTS ///

    event CompoundingPaused(bool pauseState);

    /// ERRORS ///

    error CTokenCompounding__InvalidVestPeriod();
    error CTokenCompounding__CompoundingPaused();
    error CTokenCompounding__RedeemMoreThanMax();
    error CTokenCompounding__WithdrawMoreThanMax();
    error CTokenCompounding__ZeroShares();
    error CTokenCompounding__ZeroAssets();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_
    ) CTokenBase(centralRegistry_, asset_, marketManager_) {}

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

        // Cache pendingRewards, _totalAssets, balanceOf.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;
        uint256 balancePrior = balanceOf(owner);

        // We use a modified version of maxWithdraw with newly vested assets.
        if (assets > _convertToAssets(balancePrior, ta)) {
            // revert with "CTokenCompounding__WithdrawMoreThanMax".
            _revert(0x2735eaab);
        }

        // No need to check for rounding error, previewWithdraw rounds up.
        uint256 shares = _previewWithdraw(assets, ta);

        // Update gauge pool values for `owner`.
        _gaugePool().withdraw(address(this), owner, shares);
        // Process withdraw on behalf of `owner`.
        _processWithdraw(
            msg.sender,
            msg.sender,
            owner,
            assets,
            shares,
            ta,
            pending
        );

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

    /// @notice Returns the current cToken yield status information.
    /// @return rewardRate: Yield per second in underlying asset.
    ///         vestingPeriodEnd: When the current vesting period ends and
    ///                           a new harvest can execute.
    ///         lastVestClaim: Last time pending vested yield was claimed.
    function getVaultYieldStatus() external view returns (VaultData memory) {
        return _unpackedVaultData(_vaultData);
    }

    /// @notice Returns cToken vault compound fee, in `basis points`.
    function vaultCompoundFee() external view returns (uint256) {
        return centralRegistry.protocolCompoundFee();
    }

    /// @notice Returns cToken vault yield fee, in `basis points`.
    function vaultYieldFee() external view returns (uint256) {
        return centralRegistry.protocolYieldFee();
    }

    /// @notice Returns cToken vault harvest fee, in `basis points`.
    function vaultHarvestFee() external view returns (uint256) {
        return centralRegistry.protocolHarvestFee();
    }

    // PERMISSIONED FUNCTIONS

    /// @notice Starts a CToken market, executed via marketManager.
    /// @dev This initial mint is a failsafe against rounding exploits,
    ///      although, we protect against them in many ways,
    ///      better safe than sorry.
    /// @param by The account initializing the cToken market.
    /// @return Returns with true when successful.
    function startMarket(
        address by
    ) external override nonReentrant returns (bool) {
        _startMarket(by);
        _afterDeposit(42069, 42069);
        _setlastVestClaim(uint64(block.timestamp));
        compoundingPaused = 1;
        return true;
    }

    /// @notice Permissioned function to set a new compounding vesting period.
    /// @dev Requires dao authority, `newVestingPeriod` cannot be longer
    ///      than a week (7 days).
    /// @param newVestingPeriod New vesting period, in seconds.
    function setVestingPeriod(uint256 newVestingPeriod) external {
        _checkDaoPermissions();

        if (newVestingPeriod > 7 days) {
            revert CTokenCompounding__InvalidVestPeriod();
        }

        pendingVestUpdate.updateNeeded = true;
        pendingVestUpdate.newVestPeriod = uint248(newVestingPeriod);
    }

    /// @notice Permissioned function to set compounding paused.
    /// @dev Requires elevated authority if unpausing.
    /// @param state Whether compounded should be paused or unpaused.
    function setCompoundingPaused(bool state) external {
        // If the market has not been started,
        // do not allow compounding changes.
        if (lastVestClaim() == 0) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        if (state) {
            _checkDaoPermissions();
        } else {
            _checkElevatedPermissions();
        }

        // Pause state is stored as a uint256 to minimize gas overhead.
        compoundingPaused = state ? 2 : 1;
        emit CompoundingPaused(state);
    }

    // EXTERNAL POSITION LOGIC TO OVERRIDE

    function harvest(bytes calldata) external virtual returns (uint256 yield);

    /// PUBLIC FUNCTIONS ///

    // ACCOUNTING LOGIC

    /// @notice Returns the current per second yield of the vault.
    /// @return The yield received per second in this vault,
    ///         in assets with `WAD` precision.
    function rewardRate() public view returns (uint256) {
        return _vaultData & _BITMASK_REWARD_RATE;
    }

    /// @notice Returns the timestamp when the current vesting period ends.
    /// @return The timestamp when the current vesting period ends,
    ///         in Unix time.
    function vestingPeriodEnd() public view returns (uint256) {
        return (_vaultData >> _BITPOS_VEST_END) & _BITMASK_TIMESTAMP;
    }

    /// @notice Returns the timestamp of the last claim during
    ///         the current vesting period.
    /// @return The timestamp when the last claim occurred,
    ///         in Unix time.
    function lastVestClaim() public view returns (uint256) {
        return uint64(_vaultData >> _BITPOS_LAST_VEST);
    }

    /// @notice Returns the total amount of the underlying asset in the vault,
    ///         including pending rewards that are vested, safely.
    /// @return The total number of underlying assets.
    function totalAssetsSafe() public view override nonReadReentrant returns (uint256) {
        return _totalAssets + _calculatePendingRewards();
    }

    /// @notice Returns the total amount of the underlying asset in the vault,
    ///         including pending rewards that are vested.
    /// @return The total number of underlying assets.
    function totalAssets() public view override returns (uint256) {
        return _totalAssets + _calculatePendingRewards();
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
            revert CTokenCompounding__ZeroAssets();
        }

        // Fails if deposit not allowed, this stands in for a maxDeposit
        // check reviewing isListed and mintPaused != 2.
        marketManager.canMint(address(this));

        // Cache _totalAssets and pendingRewards.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error, since we round down in previewDeposit.
        if ((shares = _previewDeposit(assets, ta)) == 0) {
            revert CTokenCompounding__ZeroShares();
        }

        // Execute deposit.
        _processDeposit(msg.sender, receiver, assets, shares, ta, pending);
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
            revert CTokenCompounding__ZeroShares();
        }

        // Fail if mint not allowed, this stands in for a maxMint
        // check reviewing isListed and mintPaused != 2.
        marketManager.canMint(address(this));

        // Cache _totalAssets and pendingRewards.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // No need to check for rounding error, previewMint rounds up.
        assets = _previewMint(shares, ta);

        // Execute deposit.
        _processDeposit(msg.sender, receiver, assets, shares, ta, pending);
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
        // Cache _totalAssets and pendingRewards.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // We use a modified version of maxWithdraw with newly vested assets.
        if (assets > _convertToAssets(balanceOf(owner), ta)) {
            // revert with "CTokenCompounding__WithdrawMoreThanMax".
            _revert(0x05203273);
        }

        // No need to check for rounding error, previewWithdraw rounds up.
        shares = _previewWithdraw(assets, ta);
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
        _processWithdraw(
            msg.sender,
            receiver,
            owner,
            assets,
            shares,
            ta,
            pending
        );
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
            // revert with "CTokenCompounding__RedeemMoreThanMax".
            _revert(0xcc3c42c0);
        }

        // Validate that `owner` can redeem `shares`.
        marketManager.canRedeemWithCollateralRemoval(
            address(this),
            owner,
            balanceOf(owner),
            shares,
            forceRedeemCollateral
        );

        // Cache _totalAssets and pendingRewards.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error, since we round down in previewRedeem.
        if ((assets = _previewRedeem(shares, ta)) == 0) {
            revert CTokenCompounding__ZeroAssets();
        }

        // Update gauge pool values for `owner`.
        _gaugePool().withdraw(address(this), owner, shares);
        // Execute withdrawal.
        _processWithdraw(
            msg.sender,
            receiver,
            owner,
            assets,
            shares,
            ta,
            pending
        );
    }

    /// @notice Processes a deposit of `assets` from the market and mints
    ///         shares to `owner`, then increases `ta` by `assets`,
    ///         and vests rewards if `pending` > 0.
    /// @param by The account that is executing the deposit.
    /// @param to The account that should receive `shares`.
    /// @param assets The amount of the underlying asset to deposit.
    /// @param shares The amount of shares minted to `to`.
    /// @param ta The current total number of assets for assets to shares
    ///           conversion.
    /// @param pending The current rewards that are pending and will be vested
    ///                during this deposit.
    function _processDeposit(
        address by,
        address to,
        uint256 assets,
        uint256 shares,
        uint256 ta,
        uint256 pending
    ) internal {
        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(asset(), by, address(this), assets);

        // Document addition of `assets` to `ta` due to deposit.
        unchecked {
            // We know that this will not overflow as rewards are partly vested,
            // and assets added and have not overflown from those operations.
            ta = ta + assets;
        }

        // Vest rewards, if there are any, then update `_totalAssets` invariant.
        if (pending > 0) {
            _vestRewards(ta);
        } else {
            _totalAssets = ta;
        }

        _mint(to, shares);

        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Deposit} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log3(0x00, 0x40, _DEPOSIT_EVENT_SIGNATURE, and(m, by), and(m, to))
        }

        // Execute any deposit strategy.
        _afterDeposit(assets, shares);
    }

    /// @notice Processes a withdrawal of `shares` from the market by burning
    ///         `owner` shares and transferring `assets` to `to`, then
    ///         decreases `ta` by `assets`, and vests rewards if
    ///         `pending` > 0.
    /// @param by The account that is executing the withdrawal.
    /// @param to The account that should receive `assets`.
    /// @param owner The account that will have `shares` burned to withdraw
    ///              `assets`.
    /// @param assets The amount of the underlying asset to withdraw.
    /// @param shares The amount of shares redeemed from `owner`.
    /// @param ta The current total number of assets for assets to shares
    ///           conversion.
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
    ) internal virtual {
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
        ta = ta - assets;

        // Vest rewards, if there are any, then update `_totalAssets`
        // invariant.
        if (pending > 0) {
            _vestRewards(ta);
        } else {
            _totalAssets = ta;
        }

        // Prepare underlying assets.
        _beforeWithdraw(assets, shares);
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

    /// @notice Sets a new `_vaultData` invariant based on `yieldToVest`,
    ///         and `periodToVest` parameters together with the current
    ///         block timestamp.
    /// @param yieldToVest The yield to vest over `periodToVest`.
    /// @param periodToVest The period in which `yieldToVest` is vested
    ///                     over to users.
    function _setNewVaultData(
        uint256 yieldToVest, 
        uint256 periodToVest
    ) internal {
        // Set rewardRate equal to prorated `yieldToVest` over `periodToVest`,
        // in `WAD` (1e18).
        _vaultData = _packVaultData(
            FixedPointMathLib.mulDiv(yieldToVest, 1e18, periodToVest),
            block.timestamp + periodToVest
            );
    }

    /// @notice Packs parameters together with current block timestamp to
    ///         calculate the new packed vault data value.
    /// @param newRewardRate The new rate, per second, that the vault vests
    ///                      fresh rewards.
    /// @param newVestPeriod The timestamp of when the new vesting period
    ///                      ends, which is block.timestamp + `vestPeriod`.
    function _packVaultData(
        uint256 newRewardRate,
        uint256 newVestPeriod
    ) internal view returns (uint256 result) {
        assembly {
            // Mask `newRewardRate` to the lower 128 bits, 
            // in case the upper bits somehow aren't clean.
            newRewardRate := and(newRewardRate, _BITMASK_REWARD_RATE)
            // Equal to `newRewardRate | (newVestPeriod << _BITPOS_VEST_END) |
            //          block.timestamp`.
            result := or(
                newRewardRate,
                or(
                    shl(_BITPOS_VEST_END, newVestPeriod),
                    shl(_BITPOS_LAST_VEST, timestamp())
                )
            )
        }
    }

    /// @notice Returns the unpacked `VaultData` struct
    ///         from `packedVaultData`.
    /// @param packedVaultData The current packed vault data value.
    /// @return vault The current vault data value, but unpacked into
    ///               a VaultData struct.
    function _unpackedVaultData(
        uint256 packedVaultData
    ) internal pure returns (VaultData memory vault) {
        vault.rewardRate = uint128(packedVaultData);
        vault.vestingPeriodEnd = uint64(packedVaultData >> _BITPOS_VEST_END);
        vault.lastVestClaim = uint64(packedVaultData >> _BITPOS_LAST_VEST);
    }

    /// @notice Returns whether the current vesting period has ended,
    ///         based on the last vest timestamp.
    /// @param packedVaultData Current packed vault data value.
    /// @return Bool of whether the current vesting period has ended or not.
    function _checkVestStatus(
        uint256 packedVaultData
    ) internal pure returns (bool) {
        return
            uint64(packedVaultData >> _BITPOS_LAST_VEST) >=
            uint64(packedVaultData >> _BITPOS_VEST_END);
    }

    /// @notice Sets the last vest claim data for the vault.
    /// @param newVestClaim The new timestamp to record as
    ///                     the last vesting claim.
    function _setlastVestClaim(uint64 newVestClaim) internal {
        // Cache vault data.
        uint256 packedVaultData = _vaultData;
        uint256 lastVestClaimCasted;
        // Cast `newVestClaim` with assembly to avoid redundant masking.
        assembly {
            lastVestClaimCasted := newVestClaim
        }
        // Calculate new packed vault data.
        packedVaultData =
            (packedVaultData & _BITMASK_LAST_CLAIM_COMPLEMENT) |
            (lastVestClaimCasted << _BITPOS_LAST_VEST);

        // Update `_vaultData` invariant.
        _vaultData = packedVaultData;
    }

    // REWARD AND HARVESTING LOGIC

    /// @notice Calculates pending rewards that have been vested.
    /// @dev If there are no pending rewards or the vesting period has ended,
    ///      it returns 0.
    /// @return pendingRewards The calculated pending rewards.
    function _calculatePendingRewards()
        internal
        view
        returns (uint256 pendingRewards)
    {
        VaultData memory vaultData = _unpackedVaultData(_vaultData);
        // Check whether there are pending rewards vesting.
        if (
            vaultData.rewardRate > 0 &&
            vaultData.lastVestClaim < vaultData.vestingPeriodEnd
        ) {
            // When calculating pending rewards:
            // pendingRewards = 
            // If the vesting period has not ended:
            // PR = rewardRate * (block.timestamp - lastTimeVestClaimed).
            // If the vesting period has ended:
            // PR = rewardRate * (vestingPeriodEnd - lastTimeVestClaimed)).
            // Then in either case:
            // Divide the pending rewards by `WAD` (1e18) for precision.
            pendingRewards =
                (
                    block.timestamp < vaultData.vestingPeriodEnd
                        ? (vaultData.rewardRate *
                            (block.timestamp - vaultData.lastVestClaim))
                        : (vaultData.rewardRate *
                            (vaultData.vestingPeriodEnd -
                                vaultData.lastVestClaim))
                ) /
                1e18;
        }
    }

    /// @notice Checks if the caller can compound pending vaults rewards.
    function _canCompound() internal view {
        if (!centralRegistry.isHarvester(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        if (compoundingPaused == 2) {
            revert CTokenCompounding__CompoundingPaused();
        }
    }

    /// @notice Vests pending rewards, and updates vault data.
    /// @param currentAssets The current assets of the vault.
    function _vestRewards(uint256 currentAssets) internal {
        // Update the lastVestClaim timestamp.
        _setlastVestClaim(uint64(block.timestamp));

        // Set internal _totalAssets balance to `currentAssets`.
        _totalAssets = currentAssets;
    }

    /// @notice Vests pending rewards, and updates vault data,
    ///         but only if needed.
    function _vestIfNeeded() internal {
        uint256 pending = _calculatePendingRewards();
        // Check whether there are pending rewards to vest.
        if (pending > 0) {
            // Vest pending rewards.
            _vestRewards(_totalAssets + pending);
        }
    }

    /// @notice Updates the vesting period, if needed.
    /// @dev If there a pending vesting update,
    ///      and prior vest is done then `vestPeriod` is updated.
    function _updateVestingPeriodIfNeeded() internal {
        // Check whether there is a pending update to reward vesting schedule.
        if (pendingVestUpdate.updateNeeded) {
            // Update vesting period.
            vestPeriod = pendingVestUpdate.newVestPeriod;
            // Remove pending vesting update flag.
            delete pendingVestUpdate.updateNeeded;
        }
    }
}
