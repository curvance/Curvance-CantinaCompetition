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
/// @dev The CToken vaults run must be a LOSSLESS position, since totalAssets
///      is not actually using the balances stored in the position,
///      rather it only uses an internal balance.
abstract contract CTokenCompounding is CTokenBase {
    using Math for uint256;

    /// TYPES ///

    struct VaultData {
        uint128 rewardRate; // The rate that the vault vests fresh rewards
        uint64 vestingPeriodEnd; // When the current vesting period ends
        uint64 lastVestClaim; // Last time vesting rewards were claimed
    }

    struct NewVestingData {
        bool updateNeeded;
        uint248 newVestPeriod;
    }

    /// CONSTANTS ///

    // Mask of reward rate entry in packed vault data
    uint256 private constant _BITMASK_REWARD_RATE = (1 << 128) - 1;

    // Mask of a timestamp entry in packed vault data
    uint256 private constant _BITMASK_TIMESTAMP = (1 << 64) - 1;

    // Mask of all bits in packed vault data except the 64 bits for `lastVestClaim`
    uint256 private constant _BITMASK_LAST_CLAIM_COMPLEMENT = (1 << 192) - 1;

    // The bit position of `vestingPeriodEnd` in packed vault data
    uint256 private constant _BITPOS_VEST_END = 128;

    // The bit position of `lastVestClaim` in packed vault data
    uint256 private constant _BITPOS_LAST_VEST = 192;

    /// STORAGE ///

    // Period harvested rewards are vested over
    uint256 public vestPeriod = 1 days;
    NewVestingData public pendingVestUpdate;
    /// @dev 1 = unpaused; 2 = paused
    uint256 public compoundingPaused = 1;

    // Internal stored vault accounting
    // Bits Layout:
    // - [0..127]    `rewardRate`
    // - [128..191]  `vestingPeriodEnd`
    // - [192..255] `lastVestClaim`
    uint256 internal _vaultData; // Packed vault data

    /// EVENTS ///

    event CompoundingPaused(bool pauseState);

    /// ERRORS ///

    error CTokenCompounding__InvalidVestPeriod();
    error CTokenCompounding__CompoundingPaused();
    error CTokenCompounding__DepositMoreThanMax();
    error CTokenCompounding__MintMoreThanMax();
    error CTokenCompounding__RedeemMoreThanMax();
    error CTokenCompounding__WithdrawMoreThanMax();
    error CTokenCompounding__ZeroShares();
    error CTokenCompounding__ZeroAssets();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address lendtroller_
    ) CTokenBase(centralRegistry_, asset_, lendtroller_) {}

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

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;
        uint256 balancePrior = balanceOf(owner);

        // We use a modified version of maxWithdraw with newly vested assets
        if (assets > _convertToAssets(balancePrior, ta)) {
            // revert with "CTokenCompounding__WithdrawMoreThanMax"
            _revert(0x2735eaab);
        }

        // No need to check for rounding error, previewWithdraw rounds up
        uint256 shares = _previewWithdraw(assets, ta);

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
        _processWithdraw(
            msg.sender,
            msg.sender,
            owner,
            assets,
            shares,
            ta,
            pending
        );

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

    /// @notice Returns current position vault yield information in the form:
    ///         rewardRate: Yield per second in underlying asset
    ///         vestingPeriodEnd: When the current vesting period ends and a new harvest can execute
    ///         lastVestClaim: Last time pending vested yield was claimed
    function getVaultYieldStatus() external view returns (VaultData memory) {
        return _unpackedVaultData(_vaultData);
    }

    /// @notice Vault compound fee is in basis point form
    /// @dev Returns the vaults current amount of yield used
    ///      for compounding rewards
    ///      Used for frontend data query only
    function vaultCompoundFee() external view returns (uint256) {
        return centralRegistry.protocolCompoundFee();
    }

    /// @notice Vault yield fee is in basis point form
    /// @dev Returns the vaults current protocol fee for compounding rewards
    ///      Used for frontend data query only
    function vaultYieldFee() external view returns (uint256) {
        return centralRegistry.protocolYieldFee();
    }

    /// @notice Vault harvest fee is in basis point form
    /// @dev Returns the vaults current harvest fee for compounding rewards
    ///      that pays for yield and compound fees
    ///      Used for frontend data query only
    function vaultHarvestFee() external view returns (uint256) {
        return centralRegistry.protocolHarvestFee();
    }

    // PERMISSIONED FUNCTIONS

    /// @notice Used to start a CToken market, executed via lendtroller
    /// @dev This initial mint is a failsafe against rounding exploits,
    ///      although, we protect against them in many ways,
    ///      better safe than sorry
    /// @param by The account initializing the market
    function startMarket(
        address by
    ) external override nonReentrant returns (bool) {
        _startMarket(by);
        _afterDeposit(42069, 42069);
        _setlastVestClaim(uint64(block.timestamp));
        return true;
    }

    /// @notice Admin function to set a new compounding vesting period
    /// @dev Requires dao authority, 
    ///      and vesting period cannot be longer than a week
    /// @param newVestingPeriod New vesting period in seconds
    function setVestingPeriod(uint256 newVestingPeriod) external {
        _checkDaoPermissions();

        if (newVestingPeriod > 7 days) {
            revert CTokenCompounding__InvalidVestPeriod();
        }

        pendingVestUpdate.updateNeeded = true;
        pendingVestUpdate.newVestPeriod = uint248(newVestingPeriod);
    }

    /// @notice Admin function to set compounding paused
    /// @dev requires timelock authority if unpausing
    /// @param state pause or unpause
    function setCompoundingPaused(bool state) external {
        if (state) {
            _checkDaoPermissions();
        } else {
            _checkElevatedPermissions();
        }

        compoundingPaused = state ? 2 : 1;
        emit CompoundingPaused(state);
    }

    // EXTERNAL POSITION LOGIC TO OVERRIDE

    function harvest(bytes calldata) external virtual returns (uint256 yield);

    /// PUBLIC FUNCTIONS ///

    // ACCOUNTING LOGIC

    /// @notice Returns the current per second yield of the vault
    function rewardRate() public view returns (uint256) {
        return _vaultData & _BITMASK_REWARD_RATE;
    }

    /// @notice Returns the timestamp when the current vesting period ends
    function vestingPeriodEnd() public view returns (uint256) {
        return (_vaultData >> _BITPOS_VEST_END) & _BITMASK_TIMESTAMP;
    }

    /// @notice Returns the timestamp of the last claim during the current vesting period
    function lastVestClaim() public view returns (uint256) {
        return uint64(_vaultData >> _BITPOS_LAST_VEST);
    }

    /// @notice Returns the total amount of the underlying asset in the vault,
    ///         including pending rewards that are vested.
    /// @dev    Has added re-entry lock for protocols building ontop of us
    ///         to have confidence in data quality
    function totalAssetsSafe() public override nonReentrant returns (uint256) {
        return _totalAssets + _calculatePendingRewards();
    }

    /// @notice Returns the total amount of the underlying asset in the vault,
    ///         including pending rewards that are vested.
    function totalAssets() public view override returns (uint256) {
        return _totalAssets + _calculatePendingRewards();
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
            revert CTokenCompounding__ZeroAssets();
        }

        if (assets > maxDeposit(receiver)) {
            // revert with "CTokenCompounding__DepositMoreThanMax"
            _revert(0x6be8191);
        }

        // Fail if deposit not allowed
        lendtroller.canMint(address(this));

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewDeposit
        if ((shares = _previewDeposit(assets, ta)) == 0) {
            revert CTokenCompounding__ZeroShares();
        }

        _processDeposit(msg.sender, receiver, assets, shares, ta, pending);
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
            revert CTokenCompounding__ZeroShares();
        }

        if (shares > maxMint(receiver)) {
            // revert with "CTokenCompounding__MintMoreThanMax"
            _revert(0x178b829b);
        }

        // Fail if mint not allowed
        lendtroller.canMint(address(this));

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // No need to check for rounding error, previewMint rounds up
        assets = _previewMint(shares, ta);

        _processDeposit(msg.sender, receiver, assets, shares, ta, pending);
        // emit events on gauge pool
        _gaugePool().deposit(address(this), receiver, shares);
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @param assets The amount of the underlying asset to withdraw
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @param forceRedeemCollateral Whether the collateral should be always reduced
    /// @return shares The amount of shares redeemed by `owner`
    function _withdraw(
        uint256 assets,
        address receiver,
        address owner,
        bool forceRedeemCollateral
    ) internal override returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // We use a modified version of maxWithdraw with newly vested assets
        if (assets > _convertToAssets(balanceOf(owner), ta)) {
            // revert with "CTokenCompounding__WithdrawMoreThanMax"
            _revert(0x05203273);
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
            // revert with "CTokenCompounding__RedeemMoreThanMax"
            _revert(0xcc3c42c0);
        }

        lendtroller.canRedeemWithCollateralRemoval(
            address(this),
            owner,
            balanceOf(owner),
            shares,
            forceRedeemCollateral
        );

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewRedeem
        if ((assets = _previewRedeem(shares, ta)) == 0) {
            revert CTokenCompounding__ZeroAssets();
        }

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
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

    function _processDeposit(
        address by,
        address to,
        uint256 assets,
        uint256 shares,
        uint256 ta,
        uint256 pending
    ) internal {
        // Need to transfer before minting or ERC777s could reenter
        SafeTransferLib.safeTransferFrom(asset(), by, address(this), assets);

        unchecked {
            // We know that this will not overflow as rewards are part vested,
            // and assets added and hasnt overflown from those operations
            ta = ta + assets;
        }

        // Vest rewards, if there are any, then update asset invariant
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

        _afterDeposit(assets, shares);
    }

    function _processWithdraw(
        address by,
        address to,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 ta,
        uint256 pending
    ) internal {
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, by);

            if (allowed != type(uint256).max) {
                _spendAllowance(owner, by, allowed - shares);
            }
        }

        // Burn the owners shares
        _burn(owner, shares);
        ta = ta - assets;

        // Vest rewards, if there are any, then update asset invariant
        if (pending > 0) {
            _vestRewards(ta);
        } else {
            _totalAssets = ta;
        }

        // Prepare underlying assets
        _beforeWithdraw(assets, shares);
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

    /// @notice Packs parameters together with current block timestamp to calculate the new packed vault data value
    /// @param newRewardRate The new rate per second that the vault vests fresh rewards
    /// @param newVestPeriod The timestamp of when the new vesting period ends, which is block.timestamp + vestPeriod
    function _packVaultData(
        uint256 newRewardRate,
        uint256 newVestPeriod
    ) internal view returns (uint256 result) {
        assembly {
            // Mask `newRewardRate` to the lower 128 bits, in case the upper bits somehow aren't clean
            newRewardRate := and(newRewardRate, _BITMASK_REWARD_RATE)
            // `newRewardRate | (newVestPeriod << _BITPOS_VEST_END) | block.timestamp`
            result := or(
                newRewardRate,
                or(
                    shl(_BITPOS_VEST_END, newVestPeriod),
                    shl(_BITPOS_LAST_VEST, timestamp())
                )
            )
        }
    }

    /// @notice Returns the unpacked `VaultData` struct from `packedVaultData`
    /// @param packedVaultData The current packed vault data value
    /// @return vault Current vault data value but unpacked into a VaultData struct
    function _unpackedVaultData(
        uint256 packedVaultData
    ) internal pure returns (VaultData memory vault) {
        vault.rewardRate = uint128(packedVaultData);
        vault.vestingPeriodEnd = uint64(packedVaultData >> _BITPOS_VEST_END);
        vault.lastVestClaim = uint64(packedVaultData >> _BITPOS_LAST_VEST);
    }

    /// @notice Returns whether the current vesting period has ended based on the last vest timestamp
    /// @param packedVaultData Current packed vault data value
    function _checkVestStatus(
        uint256 packedVaultData
    ) internal pure returns (bool) {
        return
            uint64(packedVaultData >> _BITPOS_LAST_VEST) >=
            uint64(packedVaultData >> _BITPOS_VEST_END);
    }

    /// @notice Sets the last vest claim data for the vault
    /// @param newVestClaim The new timestamp to record as the last vesting claim
    function _setlastVestClaim(uint64 newVestClaim) internal {
        uint256 packedVaultData = _vaultData;
        uint256 lastVestClaimCasted;
        // Cast `newVestClaim` with assembly to avoid redundant masking
        assembly {
            lastVestClaimCasted := newVestClaim
        }
        packedVaultData =
            (packedVaultData & _BITMASK_LAST_CLAIM_COMPLEMENT) |
            (lastVestClaimCasted << _BITPOS_LAST_VEST);
        _vaultData = packedVaultData;
    }

    // REWARD AND HARVESTING LOGIC

    /// @notice Calculates the pending rewards
    /// @dev If there are no pending rewards or the vesting period has ended,
    ///      it returns 0
    /// @return pendingRewards The calculated pending rewards
    function _calculatePendingRewards()
        internal
        view
        returns (uint256 pendingRewards)
    {
        VaultData memory vaultData = _unpackedVaultData(_vaultData);
        if (
            vaultData.rewardRate > 0 &&
            vaultData.lastVestClaim < vaultData.vestingPeriodEnd
        ) {
            // If the vesting period has not ended:
            // pendingRewards = rewardRate * (block.timestamp - lastTimeVestClaimed)
            // If the vesting period has ended:
            // rewardRate * (vestingPeriodEnd - lastTimeVestClaimed))
            // Divide the pending rewards by WAD (1e18)
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
        // else there are no pending rewards
    }

    /// @notice Checks if the caller can compound the vaults rewards
    function _canCompound() internal {
        if (!centralRegistry.isHarvester(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        if (compoundingPaused == 2) {
            revert CTokenCompounding__CompoundingPaused();
        }
    }

    /// @notice Vests the pending rewards, and updates vault data
    /// @param currentAssets The current assets of the vault
    function _vestRewards(uint256 currentAssets) internal {
        // Update the lastVestClaim timestamp
        _setlastVestClaim(uint64(block.timestamp));

        // Set internal balance equal to totalAssets value
        _totalAssets = currentAssets;
    }

    /// @notice Vests the pending rewards, and updates vault data if needed
    function _vestIfNeeded() internal {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // vest pending rewards
            _vestRewards(_totalAssets + pending);
        }
    }

    /// @notice Updates the vesting period if needed
    /// @dev If there a pending vesting update,
    ///      and prior vest is done then `vestPeriod` is updated
    function _updateVestingPeriodIfNeeded() internal {
        if (pendingVestUpdate.updateNeeded) {
            vestPeriod = pendingVestUpdate.newVestPeriod;
            delete pendingVestUpdate.updateNeeded;
        }
    }

    /// INTERNAL POSITION LOGIC TO OVERRIDE

    function _getRealPositionBalance() internal view virtual returns (uint256);
}
