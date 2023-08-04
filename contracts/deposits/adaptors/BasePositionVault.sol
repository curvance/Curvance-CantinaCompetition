// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ERC4626, SafeTransferLib, ERC20 } from "contracts/libraries/ERC4626.sol";
import { Math } from "contracts/libraries/Math.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev The position vaults run must be a LOSSLESS position, since totalAssets
///      is not actually using the balances stored in the position,
///      rather it only uses an internal balance.
abstract contract BasePositionVault is ERC4626, ReentrancyGuard {
    using Math for uint256;

    /// TYPES ///
    struct VaultData {
        uint128 rewardRate;
        uint64 vestingPeriodEnd;
        uint64 lastVestClaim;
    }

    /// CONSTANTS ///

    /// @notice Period newly harvested rewards are vested over.
    uint256 public constant vestPeriod = 1 days;
    uint256 internal constant rewardOffset = 1e18;
    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ICentralRegistry public immutable centralRegistry;
    ERC20 private immutable _asset;
    uint8 private immutable _decimals;

    /// STORAGE ///

    address public cToken;
    string private _name;
    string private _symbol;

    // Internal stored total assets, share price high watermark.
    uint256 internal _totalAssets;
    uint256 internal _sharePriceHighWatermark;

    VaultData public vaultData;
    bool public vaultIsActive;

    /// EVENTS ///

    event vaultStatusChanged(bool isShutdown);

    /// MODIFIERS ///

    modifier onlyCToken() {
        require(cToken == msg.sender, "BasePositionVault: UNAUTHORIZED");
        _;
    }

    modifier onlyHarvestor() {
        require(
            centralRegistry.harvester(msg.sender),
            "BasePositionVault: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "BasePositionVault: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "BasePositionVault: UNAUTHORIZED"
        );
        _;
    }

    modifier vaultActive() {
        require(vaultIsActive, "BasePositionVault: vault not active");
        _;
    }

    /// CONSTRUCTOR ///

    constructor(ERC20 asset_, ICentralRegistry centralRegistry_) {
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

    /// EXTERNAL FUNCTIONS ///

    // PERMISSIONED FUNCTIONS

    /// @notice Initializes the vault and the cToken attached to it
    function initiateVault(address cTokenAddress) external onlyDaoPermissions {
        require(!vaultIsActive, "BasePositionVault: vault not active");
        require(
            IMToken(cToken).tokenType() > 0,
            "BasePositionVault: not cToken"
        );

        cToken = cTokenAddress;
        vaultIsActive = true;
    }

    /// @notice Shuts down the vault
    /// @dev Used in an emergency or if the vault has been deprecated
    function initiateShutdown() external vaultActive onlyDaoPermissions {
        delete vaultIsActive;

        emit vaultStatusChanged(true);
    }

    /// @notice Reactivate the vault
    /// @dev Allows for reconfiguration of cToken attached to vault
    function liftShutdown(
        address cTokenAddress
    ) external onlyElevatedPermissions {
        require(!vaultIsActive, "BasePositionVault: vault not active");
        require(
            IMToken(cToken).tokenType() > 0,
            "BasePositionVault: not cToken"
        );

        cToken = cTokenAddress;
        vaultIsActive = true;

        emit vaultStatusChanged(false);
    }

    // EXTERNAL POSITION LOGIC TO OVERRIDE

    function harvest(
        bytes calldata
    ) external virtual returns (uint256 yield);

    /// PUBLIC FUNCTIONS ///

    // VAULT DATA QUERY FUNCTIONS

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

    // DEPOSIT AND WITHDRAWAL LOGIC

    function deposit(
        uint256 assets,
        address receiver
    ) public override vaultActive onlyCToken returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewDeposit.
        require(
            (shares = _previewDeposit(assets, ta)) != 0,
            "BasePositionVault: ZERO_SHARES"
        );

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

        // If there are pending rewards to vest,
        // or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) {
            _vestRewards(ta);
        } else {
            _totalAssets = ta;
        }

        _deposit(assets);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override vaultActive onlyCToken returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // No need to check for rounding error, previewMint rounds up.
        assets = _previewMint(shares, ta);

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

        // If there are pending rewards to vest,
        // or if high watermark is not set, vestRewards.
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
    ) public override onlyCToken returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // No need to check for rounding error, previewWithdraw rounds up.
        shares = _previewWithdraw(assets, ta);

        /// We do not need to check for msg.sender == owner or msg.sender != owner
        /// since CToken is the only contract who can call deposit, mint, withdraw, or redeem
        /// We just keep owner parameter for 4626 compliance

        // Remove the users withdrawn assets.
        ta = ta - assets;

        // If there are pending rewards to vest,
        // or if high watermark is not set, vestRewards.
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
    ) public override onlyCToken returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        /// We do not need to check for msg.sender == owner or msg.sender != owner
        /// since CToken is the only contract who can call deposit, mint, withdraw, or redeem
        /// We just keep owner parameter for 4626 compliance

        // Check for rounding error since we round down in previewRedeem.
        require(
            (assets = _previewRedeem(shares, ta)) != 0,
            "BasePositionVault: ZERO_ASSETS"
        );

        // Remove the users withdrawn assets.
        ta = ta - assets;

        // If there are pending rewards to vest,
        // or if high watermark is not set, vestRewards.
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

    function migrateStart(
        address newVault
    ) public onlyCToken nonReentrant returns (bytes memory) {
        // withdraw all assets (including pending rewards)
        uint256 assets = totalAssetsSafe();
        _withdraw(assets);

        SafeTransferLib.safeTransfer(asset(), newVault, assets);

        return abi.encode(_totalAssets, _sharePriceHighWatermark, vaultData);
    }

    /// @notice migrate confirm function
    /// @dev this function can be upgraded on new vault contract
    function migrateConfirm(
        address, // oldVault,
        bytes memory params
    ) public onlyCToken nonReentrant {
        (_totalAssets, _sharePriceHighWatermark, vaultData) = abi.decode(
            params,
            (uint256, uint256, VaultData)
        );

        // deposit all assets (including pending rewards)
        uint256 assets = totalAssetsSafe();
        _deposit(assets);
    }

    // ACCOUNTING LOGIC

    function totalAssetsSafe() public nonReentrant returns (uint256) {
        // Returns stored internal balance + pending rewards that are vested.
        // Has added re-entry lock for protocols building ontop of us to have confidence in data quality
        return _totalAssets + _calculatePendingRewards();
    }

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

    /// INTERNAL FUNCTIONS ///

    // REWARD AND HARVESTING LOGIC

    /// @notice Calculates the pending rewards.
    /// @dev If there are no pending rewards or the vesting period has ended,
    ///      it returns 0.
    ///      Otherwise, it calculates the pending rewards and returns them.
    /// @return pendingRewards The calculated pending rewards.
    function _calculatePendingRewards()
        internal
        view
        returns (uint256 pendingRewards)
    {
        if (
            vaultData.rewardRate > 0 &&
            vaultData.lastVestClaim < vaultData.vestingPeriodEnd
        ) {
            // There are pending rewards.
            // Logic follows: If the vesting period has not ended
            //                pendingRewards = rewardRate * (block.timestamp - lastTimeVestClaimed)
            //                If the vesting period has ended
            //                rewardRate * (vestingPeriodEnd - lastTimeVestClaimed))
            // Divide the pending rewards by the reward offset of 18 decimals
            pendingRewards =
                (
                    block.timestamp < vaultData.vestingPeriodEnd
                        ? (vaultData.rewardRate *
                            (block.timestamp - vaultData.lastVestClaim))
                        : (vaultData.rewardRate *
                            (vaultData.vestingPeriodEnd -
                                vaultData.lastVestClaim))
                ) /
                rewardOffset;
        }
        // else there are no pending rewards.
    }

    /// @notice Vests the pending rewards, updates vault data
    ///         and share price high watermark.
    /// @param currentAssets The current assets of the vault.
    function _vestRewards(uint256 currentAssets) internal {
        // Update some reward timestamp.
        vaultData.lastVestClaim = uint64(block.timestamp);

        // Set internal balance equal to totalAssets value
        _totalAssets = currentAssets;

        // Update share price high watermark since rewards have been vested.
        _sharePriceHighWatermark = _convertToAssets(
            10 ** _decimals,
            currentAssets
        );
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

    // INTERNAL POSITION LOGIC TO OVERRIDE

    function _deposit(uint256 assets) internal virtual;

    function _withdraw(uint256 assets) internal virtual;

    function _getRealPositionBalance() internal view virtual returns (uint256);
}
