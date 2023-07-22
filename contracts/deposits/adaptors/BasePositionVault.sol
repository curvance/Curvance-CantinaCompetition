// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC4626, SafeTransferLib, ERC20 } from "contracts/libraries/ERC4626.sol";
import { Math } from "contracts/libraries/Math.sol";

import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev The position vaults run must be a LOSSLESS position, since totalAssets
///      is not actually using the balances stored in the position,
///      rather it only uses an internal balance.
abstract contract BasePositionVault is ERC4626, ReentrancyGuard {
    using Math for uint256;

    /// EVENTS ///
    event vaultStatusChanged(bool isShutdown);


    /// ERRORS ///
    error BasePositionVault__InvalidPlatformFee(uint64 invalidFee);
    error BasePositionVault__InvalidUpkeepFee(uint64 invalidFee);
    error BasePositionVault__ContractShutdown();
    error BasePositionVault__ContractNotShutdown();

    /// STRUCTS ///
    struct VaultData {
        uint128 rewardRate;
        uint64 vestingPeriodEnd;
        uint64 lastVestClaim;
    }


    /// CONSTANTS ///
    ICentralRegistry public immutable centralRegistry;
    ERC20 private immutable _asset;
    uint8 private immutable _decimals;
    string private _name;
    string private _symbol;
    uint256 internal constant rewardOffset = 1e18;
    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);


    /// STORAGE ///
    VaultData public vaultData;
    bool public isShutdown;

    // Internal stored total assets, share price high watermark.
    uint256 internal _totalAssets;
    uint256 internal _sharePriceHighWatermark;

    /// @notice Period newly harvested rewards are vested over.
    uint256 public constant vestPeriod = 1 days;

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_
    ) {
        _asset = asset_;
        _name = string(abi.encodePacked("Curvance ", asset_.name()));
        _symbol = string(abi.encodePacked("cve", asset_.symbol()));
        _decimals = asset_.decimals();

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "BasePositionVault: invalid central registry"
        );

        centralRegistry = centralRegistry_;
    }

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "BasePositionVault: UNAUTHORIZED");
        _;
    }

    modifier onlyElevatedPermissions() {
            require(centralRegistry.hasElevatedPermissions(msg.sender), "BasePositionVault: UNAUTHORIZED");
            _;
    }

    modifier vaultActive() {
        if (isShutdown)
            revert BasePositionVault__ContractShutdown();
        _;
    }

    /// VAULT DATA QUERY FUNCTIONS ///

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @dev Returns the address of the underlying asset.
    function asset() public view override returns (address) {
        return address(_asset);
    }

    /// @dev Returns the decimals of the underlying asset.
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Vault compound fee is in basis point form
    /// @dev Returns the vaults current amount of yield used for compounding rewards
    function vaultCompoundFee() public view returns (uint256) {
        return centralRegistry.protocolCompoundFee();
    }

    /// @notice Vault yield fee is in basis point form
    /// @dev Returns the vaults current protocol fee for compounding rewards
    function vaultYieldFee() public view returns (uint256) {
        return centralRegistry.protocolYieldFee();
    }

    /// @notice Vault harvest fee is in basis point form
    /// @dev Returns the vaults current harvest fee for compounding rewards that pays for yield and compound fees
    function vaultHarvestFee() public view returns (uint256) {
        return centralRegistry.protocolHarvestFee();
    }

    /// @dev Returns the protocol price router
    function getPriceRouter() public view returns (IPriceRouter) {
        return IPriceRouter(centralRegistry.priceRouter());
    }

    /// PERMISSIONED FUNCTIONS ///

    /// @notice Shutdown the vault. Used in an emergency or if the vault has been deprecated.
    function initiateShutdown() external vaultActive onlyDaoPermissions {
        isShutdown = true;

        emit vaultStatusChanged(true);
    }

    /// @notice Reactivate the vault.
    function liftShutdown() external onlyElevatedPermissions {
        if (!isShutdown)
            revert BasePositionVault__ContractNotShutdown();
        delete isShutdown;

        emit vaultStatusChanged(false);
    }


    /// REWARD AND HARVESTING LOGIC ///

    /// @notice Calculates the pending rewards.
    /// @dev If there are no pending rewards or the vesting period has ended, it returns 0. 
    ///      Otherwise, it calculates the pending rewards and returns them.
    /// @return pendingRewards The calculated pending rewards.
    function _calculatePendingRewards()
        internal
        view
        returns (uint256 pendingRewards)
    {
        if (
            vaultData.rewardRate > 0 &&
            vaultData.lastVestClaim <
            vaultData.vestingPeriodEnd
        ) {
            // There are pending rewards.
            // Logic follows: If the vesting period has not ended
            //                pendingRewards = rewardRate * (block.timestamp - lastTimeVestClaimed)
            //                If the vesting period has ended
            //                rewardRate * (vestingPeriodEnd - lastTimeVestClaimed))
            // Divide the pending rewards by the reward offset of 18 decimals
            pendingRewards = (block.timestamp <
                vaultData.vestingPeriodEnd
                ? (vaultData.rewardRate *
                    (block.timestamp - vaultData.lastVestClaim))
                : (vaultData.rewardRate *
                    (vaultData.vestingPeriodEnd -
                        vaultData.lastVestClaim))) / rewardOffset;
        } 
        // else there are no pending rewards.
    }

    /// @notice Vests the pending rewards, updates vault data and share price high watermark.
    /// @param currentAssets The current assets of the vault.
    function _vestRewards(uint256 currentAssets) internal {
        // Update some reward timestamp.
        vaultData.lastVestClaim = uint64(block.timestamp);

        // Set internal balance equal to totalAssets value
        _totalAssets = currentAssets;

        // Update share price high watermark since rewards have been vested.
        _sharePriceHighWatermark = _convertToAssets(10 ** _decimals, currentAssets);
    }

    /// DEPOSIT AND WITHDRAWAL LOGIC ///
    function deposit(
        uint256 assets,
        address receiver
    ) public override vaultActive nonReentrant returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewDeposit.
        require((shares = _previewDeposit(assets, ta)) != 0, "BasePositionVault: ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(
            asset(),
            msg.sender,
            address(this),
            assets
        );

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Add the users newly deposited assets.
        ta = ta + assets;
        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) _vestRewards(ta);
        else _totalAssets = ta;

        _deposit(assets);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override vaultActive nonReentrant returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        assets = _previewMint(shares, ta); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(
            asset(),
            msg.sender,
            address(this),
            assets
        );

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Add the users newly deposited assets.
        ta = ta + assets;
        
        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) {
            _vestRewards(ta);
        } else {
            _totalAssets = ta;
        }

        _deposit(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        shares = _previewWithdraw(assets, ta); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);

            if (allowed != type(uint256).max) {
                decreaseAllowance(owner, allowed - shares);
            }
                
        }

        // Remove the users withdrawn assets.
        ta = ta - assets;

        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) {
            _vestRewards(ta);
        } else {
            _totalAssets = ta;
        }

        _withdraw(assets);
        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransfer(asset(), receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);

            if (allowed != type(uint256).max) {
                decreaseAllowance(owner, allowed - shares);
            }

        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = _previewRedeem(shares, ta)) != 0, "BasePositionVault: ZERO_ASSETS");

        // Remove the users withdrawn assets.
        ta = ta - assets;

        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) {
            _vestRewards(ta);
        } else {
            _totalAssets = ta;
        }

        _withdraw(assets);
        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransfer(asset(), receiver, assets);
    }

    /// ACCOUNTING LOGIC ///
    function totalAssets() public view override returns (uint256) {
        // Returns stored internal balance + pending rewards that are vested.
        return _totalAssets + _calculatePendingRewards();
    }

    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        return _convertToShares(assets, totalSupply());
    }

    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        return _previewMint(shares, totalAssets());
    }

    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return _previewWithdraw(assets, totalAssets());
    }

    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function _convertToShares(
        uint256 assets,
        uint256 _ta
    ) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets.changeDecimals(_asset.decimals(), 18)
            : assets.mulDivDown(totalShares, _ta);
    }

    function _convertToAssets(
        uint256 shares,
        uint256 _ta
    ) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares.changeDecimals(18, _asset.decimals())
            : shares.mulDivDown(_ta, totalShares);
    }

    function _previewDeposit(
        uint256 assets,
        uint256 _ta
    ) internal view returns (uint256) {
        return _convertToShares(assets, _ta);
    }

    function _previewMint(
        uint256 shares,
        uint256 _ta
    ) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares.changeDecimals(18, _asset.decimals())
            : shares.mulDivUp(_ta, totalShares);
    }

    function _previewWithdraw(
        uint256 assets,
        uint256 _ta
    ) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets.changeDecimals(_asset.decimals(), 18)
            : assets.mulDivUp(totalShares, _ta);
    }

    function _previewRedeem(
        uint256 shares,
        uint256 _ta
    ) internal view returns (uint256) {
        return _convertToAssets(shares, _ta);
    }

    /// INTERNAL POSITION LOGIC ///
    function _withdraw(uint256 assets) internal virtual;

    function _deposit(uint256 assets) internal virtual;

    function _getRealPositionBalance() internal view virtual returns (uint256);

    /// EXTERNAL POSITION LOGIC ///
    function harvest(bytes memory) public virtual returns (uint256 yield);
}
