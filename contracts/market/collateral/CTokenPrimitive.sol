// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ERC4626, SafeTransferLib, ERC20 } from "contracts/libraries/ERC4626.sol";
import { Math } from "contracts/libraries/Math.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { WAD } from "contracts/libraries/Constants.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
contract CTokenPrimitive is ERC4626, ReentrancyGuard {
    using Math for uint256;

    /// CONSTANTS ///

    ERC20 private immutable _asset; // underlying asset for the vault
    uint8 private immutable _decimals; // vault assets decimals of precision
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// `bytes4(keccak256(bytes("CTokenPrimitive__VaultNotActive()")))`
    uint256 internal constant VAULT_NOT_ACTIVE_SELECTOR = 0x665f0f11;
    /// `keccak256(bytes("Deposit(address,address,uint256,uint256)"))`.
    uint256 private constant _DEPOSIT_EVENT_SIGNATURE =
        0xdcbc1c05240f31ff3ad067ef1ee35ce4997762752e3a095284754544f4c709d7;
    /// `keccak256(bytes("Withdraw(address,address,address,uint256,uint256)"))`.
    uint256 private constant _WITHDRAW_EVENT_SIGNATURE =
        0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db;
    /// `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _BALANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _BALANCE_SLOT_SEED = 0x87a211a2;

    /// STORAGE ///

    /// @notice Current lending market controller
    ILendtroller public lendtroller;

    /// @notice token name metadata
    string internal _name;
    /// @notice token symbol metadata
    string internal _symbol;
    uint256 internal _totalAssets; // total vault assets minus vesting
    uint256 internal _vaultStatus; // Vault Status: 2 = active; 0 or 1 = inactive

    /// EVENTS ///

    event NewLendtroller(address oldLendtroller, address newLendtroller);
    event VaultStatusChanged(bool isShutdown);

    /// ERRORS ///

    error CTokenPrimitive__Unauthorized();
    error CTokenPrimitive__VaultNotActive();
    error CTokenPrimitive__VaultIsActive();
    error CTokenPrimitive__InvalidCentralRegistry();
    error CTokenPrimitive__RedeemMoreThanMax();
    error CTokenPrimitive__WithdrawMoreThanMax();
    error CTokenPrimitive__ZeroShares();
    error CTokenPrimitive__ZeroAssets();
    error CTokenPrimitive__UnderlyingAssetTotalSupplyExceedsMaximum();
    error CTokenPrimitive__LendtrollerIsNotLendingMarket();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert CTokenPrimitive__Unauthorized();
        }
        _;
    }

    modifier onlyElevatedPermissions() {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            revert CTokenPrimitive__Unauthorized();
        }
        _;
    }

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        ERC20 asset_,
        address lendtroller_
    ) {
        _asset = asset_;
        _name = string.concat("Curvance collateralized ", asset_.name());
        _symbol = string.concat("c", asset_.symbol());
        _decimals = asset_.decimals();

        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CTokenPrimitive__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;
        // Set the lendtroller after consulting Central Registry
        _setLendtroller(lendtroller_);

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate of 1e18
        if (asset_.totalSupply() >= type(uint232).max) {
            revert CTokenPrimitive__UnderlyingAssetTotalSupplyExceedsMaximum();
        }
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Caller deposits assets into the market, receives shares,
    ///         and turns on collateralization of the assets
    /// @param assets The amount of the underlying asset to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return shares The amount of cToken shares received by `receiver`
    function depositAsCollateral(
        uint256 assets,
        address receiver
    ) external nonReentrant returns (uint256 shares) {
        shares = _deposit(assets, receiver);
        if (
            msg.sender == receiver ||
            msg.sender != lendtroller.positionFolding()
        ) {
            lendtroller.postCollateral(receiver, address(this), shares);
        }
    }

    /// @notice Caller deposits assets into the market, receives cTokens
    ///         as shares, and turns on collateralization of the assets
    /// @param shares The amount of the underlying assets quoted in shares to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return assets The amount of cToken shares quoted in assets received by `receiver`
    function mintAsCollateral(
        uint256 shares,
        address receiver
    ) external nonReentrant returns (uint256 assets) {
        assets = _mint(shares, receiver);
        if (
            msg.sender == receiver ||
            msg.sender != lendtroller.positionFolding()
        ) {
            lendtroller.postCollateral(receiver, address(this), shares);
        }
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @dev   Forces collateral to be withdrawn
    /// @param assets The amount of the underlying asset to withdraw
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @return shares The amount of cToken shares redeemed by `owner`
    function withdrawCollateral(
        uint256 assets,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 shares) {
        shares = _withdraw(assets, receiver, owner, true);
    }

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
            revert CTokenPrimitive__Unauthorized();
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

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @dev   Forces collateral to be withdrawn
    /// @param shares The amount of shares to redeemed
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @return assets The amount of assets redeemed by `owner`
    function redeemCollateral(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 assets) {
        assets = _redeem(shares, receiver, owner, true);
    }

    // PERMISSIONED FUNCTIONS

    /// @notice Used to start a CToken market, executed via lendtroller
    /// @dev This initial mint is a failsafe against the empty market exploit
    ///      although we protect against it in many ways,
    ///      better safe than sorry
    /// @param by The account initializing the market
    function startMarket(address by) external nonReentrant returns (bool) {
        if (msg.sender != address(lendtroller)) {
            revert CTokenPrimitive__Unauthorized();
        }

        uint256 assets = 42069;
        address market = address(this);

        SafeTransferLib.safeTransferFrom(asset(), by, market, assets);

        // Because nobody can deposit into the market before startMarket() is called,
        // this will always be the initial call
        uint256 shares = _initialConvertToShares(assets);

        _mint(market, shares);
        _totalAssets = assets;

        assembly {
            // Emit the {Deposit} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log3(
                0x00,
                0x40,
                _DEPOSIT_EVENT_SIGNATURE,
                and(m, market),
                and(m, market)
            )
        }

        _vaultStatus = 2;
        emit VaultStatusChanged(false);

        return true;
    }

    /// @notice Shuts down the vault
    /// @dev Used in an emergency or if the vault has been deprecated
    function initiateShutdown() external onlyDaoPermissions {
        if (_vaultStatus != 2) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

        _vaultStatus = 1;

        emit VaultStatusChanged(true);
    }

    /// @notice Reactivate the vault
    /// @dev Allows for reconfiguration of cToken attached to vault
    function liftShutdown() external onlyElevatedPermissions {
        if (_vaultStatus == 2) {
            // revert with "CTokenPrimitive__VaultIsActive()"
            _revert(0x8bdb4dfb);
        }

        _vaultStatus = 2;
        emit VaultStatusChanged(false);
    }

    /// @notice Sets a new lendtroller for the market
    /// @dev Admin function to set a new lendtroller
    /// @param newLendtroller New lendtroller address
    function setLendtroller(
        address newLendtroller
    ) external onlyElevatedPermissions {
        _setLendtroller(newLendtroller);
    }

    /// @notice Get the underlying balance of the `account`
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlyingSafe(
        address account
    ) external returns (uint256) {
        return ((convertToAssetsSafe(WAD) * balanceOf(account)) / WAD);
    }

    /// @notice Get the underlying balance of the `account`
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlying(
        address account
    ) external view returns (uint256) {
        return ((convertToAssets(WAD) * balanceOf(account)) / WAD);
    }

    /// @notice Get exchange rate
    /// @dev Price router tries to calculate CToken price from this exchange rate
    function exchangeRateStored() external view returns (uint256) {
        return convertToAssets(WAD);
    }

    /// @notice Get a snapshot of the account's balances,
    ///         and the cached exchange rate
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    /// @return tokenBalance Current account shares balance
    /// @return borrowBalance Current account borrow balance (will always be 0, kept for composability)
    /// @return exchangeRate Current exchange rate between assets and shares, in `WAD`
    function getSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return (balanceOf(account), 0, convertToAssets(WAD));
    }

    /// @notice Get a snapshot of the cToken and `account` data
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// NOTE: Posted Debt Balance always return 0 to save gas in lendtroller
    ///       since it is unused
    function getSnapshotPacked(
        address
    ) external view returns (AccountSnapshot memory) {
        return (
            AccountSnapshot({
                asset: address(this),
                isCToken: true,
                decimals: decimals(),
                debtBalance: 0, // This is a cToken so always 0
                exchangeRate: convertToAssets(WAD)
            })
        );
    }

    /// @notice Rescue any token sent by mistake
    /// @param token The token to rescue
    /// @param amount Amount of `token` to rescue, 0 indicates to rescue all
    function rescueToken(
        address token,
        uint256 amount
    ) external onlyDaoPermissions {
        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (amount == 0) {
                amount = address(this).balance;
            }

            SafeTransferLib.forceSafeTransferETH(daoOperator, amount);
        } else {
            if (token == asset()) {
                revert CTokenPrimitive__Unauthorized();
            }

            if (amount == 0) {
                amount = ERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// PUBLIC FUNCTIONS ///

    // VAULT DATA FUNCTIONS

    /// @notice Returns the name of the token
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the address of the underlying asset
    function asset() public view override returns (address) {
        return address(_asset);
    }

    function underlying() external view returns (address) {
        return address(_asset);
    }

    /// @notice Returns the position vaults current status
    function vaultStatus() public view returns (string memory) {
        return _vaultStatus == 2 ? "Active" : "Inactive";
    }

    function maxDeposit(
        address to
    ) public view override returns (uint256 maxAssets) {
        maxAssets = _vaultStatus == 2 ? super.maxDeposit(to) : 0;
    }

    function maxMint(
        address to
    ) public view override returns (uint256 maxShares) {
        maxShares = _vaultStatus == 2 ? super.maxMint(to) : 0;
    }

    // TOKEN ACTION FUNCTIONS

    /// @notice Transfer `amount` tokens from `msg.sender` to `to`
    /// @param to The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transfer(
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        // Fails if transfer not allowed
        lendtroller.canTransfer(address(this), msg.sender, amount);

        // emit events on gauge pool
        GaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), msg.sender, amount);

        super.transfer(to, amount);
        gaugePool.deposit(address(this), to, amount);

        return true;
    }

    /// @notice Transfer `amount` tokens from `from` to `to`
    /// @param from The address of the source account
    /// @param to The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return bool true = success
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        // Fails if transfer not allowed
        lendtroller.canTransfer(address(this), from, amount);

        // emit events on gauge pool
        GaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), from, amount);

        super.transferFrom(from, to, amount);
        gaugePool.deposit(address(this), to, amount);

        return true;
    }

    /// @notice Caller deposits assets into the market and receives shares
    /// @param assets The amount of the underlying asset to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return shares the amount of cToken shares received by `receiver`
    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    /// @notice Caller deposits assets into the market and receives shares
    /// @param shares The amount of the underlying assets quoted in shares to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return assets the amount of cToken shares quoted in assets received by `receiver`
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        assets = _mint(shares, receiver);
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @param assets The amount of the underlying asset to withdraw
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their cTokens to withdraw assets
    /// @return shares the amount of cToken shares redeemed by `owner`
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        shares = _withdraw(assets, receiver, owner, false);
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @param shares The amount of shares to burn to withdraw assets
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their cTokens to withdraw assets
    /// @return assets the amount of assets received by `receiver`
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        assets = _redeem(shares, receiver, owner, false);
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Will fail unless called by another cToken during the process
    ///      of liquidation.
    /// @param liquidator The account receiving seized collateral
    /// @param borrower The account having collateral seized
    /// @param liquidatedTokens The total number of cTokens to seize
    /// @param protocolTokens The number of cTokens to seize for protocol
    function seize(
        address liquidator,
        address borrower,
        uint256 liquidatedTokens,
        uint256 protocolTokens
    ) external nonReentrant {
        // Fails if borrower = liquidator
        assembly {
            if eq(borrower, liquidator) {
                // revert with "CTokenPrimitive__Unauthorized()"
                mstore(0x00, 0xcb4ea030)
                revert(0x1c, 0x04)
            }
        }

        // Fails if seize not allowed
        lendtroller.canSeize(address(this), msg.sender);
        uint256 liquidatorTokens = liquidatedTokens - protocolTokens;

        // emit events on gauge pool
        GaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), borrower, liquidatedTokens);

        _transferFromWithoutAllowance(borrower, liquidator, liquidatorTokens);
        gaugePool.deposit(address(this), liquidator, liquidatorTokens);

        if (protocolTokens > 0) {
            address daoAddress = centralRegistry.daoAddress();
            _transferFromWithoutAllowance(
                borrower,
                daoAddress,
                protocolTokens
            );
            gaugePool.deposit(address(this), daoAddress, protocolTokens);
        }
    }

    /// @notice Returns whether the MToken is a cToken
    function isCToken() public pure returns (bool) {
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IMToken).interfaceId;
    }

    // ACCOUNTING LOGIC

    function totalAssetsSafe() public nonReentrant returns (uint256) {
        // Returns stored internal balance.
        // Has added re-entry lock for protocols building ontop of us to have confidence in data quality
        return _totalAssets;
    }

    function totalAssets() public view override returns (uint256) {
        // Returns stored internal balance.
        return _totalAssets;
    }

    /// @notice Returns the amount of shares that would be exchanged
    ///         by the vault for `assets` provided.
    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    /// @notice Returns the amount of shares that would be exchanged
    ///         by the vault for `assets` provided.
    /// @dev    Has added re-entry lock for protocols building ontop of us
    ///         to have confidence in data quality
    function convertToSharesSafe(
        uint256 assets
    ) public nonReentrant returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    /// @notice Returns the amount of assets that would be exchanged
    ///         by the vault for `shares` provided.
    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    /// @notice Returns the amount of assets that would be exchanged
    ///         by the vault for `shares` provided.
    /// @dev    Has added re-entry lock for protocols building ontop of us
    ///         to have confidence in data quality
    function convertToAssetsSafe(
        uint256 shares
    ) public nonReentrant returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their deposit at the current block.
    /// @return The shares received for depositing `assets`.
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        return _previewDeposit(assets, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their mint at the current block.
    /// @return The shares received quoted as assets for depositing `shares`.
    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        return _previewMint(shares, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their withdraw at the current block.
    /// @return The assets received quoted as shares for withdrawing `assets`.
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return _previewWithdraw(assets, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their redeem at the current block.
    /// @return The assets received for withdrawing `shares`.
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return _previewRedeem(shares, totalAssets());
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Caller deposits assets into the market and receives shares
    /// @param assets The amount of the underlying asset to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return shares the amount of cToken shares received by `receiver`
    function _deposit(
        uint256 assets,
        address receiver
    ) internal returns (uint256 shares) {
        if (assets == 0 || assets > maxDeposit(receiver)) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
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
    ) internal returns (uint256 assets) {
        if (shares == 0 || shares > maxMint(receiver)) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
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
    ) internal returns (uint256 shares) {
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
    ) internal returns (uint256 assets) {
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

    function _transferFromWithoutAllowance(
        address from,
        address to,
        uint256 amount
    ) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let from_ := shl(96, from)
            // Compute the balance slot and load its value.
            mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(
                0x20,
                0x20,
                _TRANSFER_EVENT_SIGNATURE,
                shr(96, from_),
                shr(96, mload(0x0c))
            )
        }
    }

    /// @notice Sets a new lendtroller for the market
    /// @param newLendtroller New lendtroller address
    function _setLendtroller(address newLendtroller) internal {
        // Ensure that lendtroller parameter is a lendtroller
        if (!centralRegistry.isLendingMarket(newLendtroller)) {
            revert CTokenPrimitive__LendtrollerIsNotLendingMarket();
        }

        // Cache the current lendtroller to save gas
        address oldLendtroller = address(lendtroller);

        // Set new lendtroller
        lendtroller = ILendtroller(newLendtroller);

        emit NewLendtroller(oldLendtroller, newLendtroller);
    }

    /// @dev Returns the decimals of the underlying asset
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    function _convertToShares(
        uint256 assets,
        uint256 ta
    ) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets
            : assets.mulDivDown(totalShares, ta);
    }

    function _convertToAssets(
        uint256 shares,
        uint256 ta
    ) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares
            : shares.mulDivDown(ta, totalShares);
    }

    function _previewDeposit(
        uint256 assets,
        uint256 ta
    ) internal view returns (uint256) {
        return _convertToShares(assets, ta);
    }

    function _previewMint(
        uint256 shares,
        uint256 ta
    ) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0 ? shares : shares.mulDivUp(ta, totalShares);
    }

    function _previewWithdraw(
        uint256 assets,
        uint256 ta
    ) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0 ? assets : assets.mulDivUp(totalShares, ta);
    }

    function _previewRedeem(
        uint256 shares,
        uint256 ta
    ) internal view returns (uint256) {
        return _convertToAssets(shares, ta);
    }

    /// @notice Returns gauge pool contract address
    /// @return The gauge controller contract address
    function _gaugePool() internal view returns (GaugePool) {
        return lendtroller.gaugePool();
    }
}
