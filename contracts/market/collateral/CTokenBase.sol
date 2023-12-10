// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ERC4626, SafeTransferLib } from "contracts/libraries/ERC4626.sol";
import { Math } from "contracts/libraries/Math.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
abstract contract CTokenBase is ERC4626, ReentrancyGuard {
    using Math for uint256;

    /// CONSTANTS ///

    IERC20 private immutable _asset; // underlying asset for the vault
    uint8 private immutable _decimals; // vault assets decimals of precision
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// `bytes4(keccak256(bytes("CTokenBase__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xbf98a75b;
    /// `keccak256(bytes("Deposit(address,address,uint256,uint256)"))`.
    uint256 internal constant _DEPOSIT_EVENT_SIGNATURE =
        0xdcbc1c05240f31ff3ad067ef1ee35ce4997762752e3a095284754544f4c709d7;
    /// `keccak256(bytes("Withdraw(address,address,address,uint256,uint256)"))`.
    uint256 internal constant _WITHDRAW_EVENT_SIGNATURE =
        0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db;
    /// `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 internal constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _BALANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 internal constant _BALANCE_SLOT_SEED = 0x87a211a2;

    /// STORAGE ///

    /// @notice Lending Market controller
    ILendtroller public immutable lendtroller;

    /// @notice token name metadata
    string internal _name;
    /// @notice token symbol metadata
    string internal _symbol;
    uint256 internal _totalAssets; // total vault assets minus vesting
    uint256 internal _vaultStatus; // Vault Status: 2 = active; 0 or 1 = inactive

    /// ERRORS ///

    error CTokenBase__Unauthorized();
    error CTokenBase__InvalidCentralRegistry();
    error CTokenBase__LendtrollerIsNotLendingMarket();
    error CTokenBase__UnderlyingAssetTotalSupplyExceedsMaximum();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
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
            revert CTokenBase__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        // Set the lendtroller after consulting Central Registry
        // Ensure that lendtroller parameter is a lendtroller
        if (!centralRegistry.isLendingMarket(lendtroller_)) {
            revert CTokenBase__LendtrollerIsNotLendingMarket();
        }

        // Set lendtroller
        lendtroller = ILendtroller(lendtroller_);

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate of 1e18
        if (asset_.totalSupply() >= type(uint232).max) {
            revert CTokenBase__UnderlyingAssetTotalSupplyExceedsMaximum();
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
            msg.sender == lendtroller.positionFolding()
        ) {
            lendtroller.postCollateral(receiver, address(this), shares);
        }
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @dev   Forces collateral to be withdrawn
    /// @param assets The amount of the underlying asset to withdraw
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @return shares the amount of cToken shares redeemed by `owner`
    function withdrawCollateral(
        uint256 assets,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 shares) {
        shares = _withdraw(assets, receiver, owner, true);
    }

    /// @notice Caller withdraws assets from the market and burns their shares
    /// @dev   Forces collateral to be withdrawn
    /// @param shares The amount of shares to redeemed
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @return assets the amount of assets redeemed by `owner`
    function redeemCollateral(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 assets) {
        assets = _redeem(shares, receiver, owner, true);
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

    /// @notice Get exchange rate with lock
    /// @dev Price router tries to calculate CToken price from this exchange rate
    function exchangeRateSafe() external returns (uint256) {
        return convertToAssetsSafe(WAD);
    }

    /// @notice Get exchange rate
    /// @dev Price router tries to calculate CToken price from this exchange rate
    function exchangeRateCached() external view returns (uint256) {
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
    function rescueToken(address token, uint256 amount) external {
        _checkDaoPermissions();
        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (amount == 0) {
                amount = address(this).balance;
            }

            SafeTransferLib.forceSafeTransferETH(daoOperator, amount);
        } else {
            if (token == asset()) {
                _revert(_UNAUTHORIZED_SELECTOR);
            }

            if (amount == 0) {
                amount = IERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// CTOKEN MARKET START LOGIC TO OVERRIDE
    function startMarket(address by) external virtual returns (bool) {}

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

    /// @notice Returns the address of the underlying asset
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
    /// @dev   Does not force collateral to be withdrawn
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
    /// @dev   Does not force collateral to be withdrawn
    /// @param shares The amount of shares to redeemed
    /// @param receiver The account that should receive the assets
    /// @param owner The account that will burn their shares to withdraw assets
    /// @return assets the amount of assets redeemed by `owner`
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        assets = _redeem(shares, receiver, owner, false);
    }

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
        IGaugePool gaugePool = _gaugePool();
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
        IGaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), from, amount);

        super.transferFrom(from, to, amount);
        gaugePool.deposit(address(this), to, amount);

        return true;
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Will fail unless called by another cToken during the process
    ///      of liquidation.
    /// @param liquidator The account receiving seized collateral
    /// @param account The account having collateral seized
    /// @param liquidatedTokens The total number of cTokens to seize
    /// @param protocolTokens The number of cTokens to seize for protocol
    function seize(
        address liquidator,
        address account,
        uint256 liquidatedTokens,
        uint256 protocolTokens
    ) external nonReentrant {
        // Fails if borrower = liquidator
        assembly {
            if eq(liquidator, account) {
                // revert with "CTokenCompounding__Unauthorized"
                mstore(0x00, _UNAUTHORIZED_SELECTOR)
                revert(0x1c, 0x04)
            }
        }

        // Fails if seize not allowed
        lendtroller.canSeize(address(this), msg.sender);
        uint256 liquidatorTokens = liquidatedTokens - protocolTokens;

        // emit events on gauge pool
        IGaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), account, liquidatedTokens);

        _transferFromWithoutAllowance(account, liquidator, liquidatorTokens);
        gaugePool.deposit(address(this), liquidator, liquidatorTokens);

        if (protocolTokens > 0) {
            address daoAddress = centralRegistry.daoAddress();
            _transferFromWithoutAllowance(account, daoAddress, protocolTokens);
            gaugePool.deposit(address(this), daoAddress, protocolTokens);
        }
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Will fail unless called by the lendtroller itself during the process
    ///      of liquidation.
    ///      NOTE: The protocol never takes a fee on account liquidation
    ///            as lenders already are bearing a burden.
    /// @param liquidator The account receiving seized collateral
    /// @param account The account having collateral seized
    /// @param shares The total number of cTokens to seize
    function seizeAccountLiquidation(
        address liquidator,
        address account,
        uint256 shares
    ) external nonReentrant {
        // We check self liquidation in lendtroller before
        // this call so we do not need to check here

        // Make sure the lendtroller itself is calling since
        // then we know all liquidity checks have passed
        if (msg.sender != address(lendtroller)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
        // emit events on gauge pool
        IGaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), account, shares);

        // Transfer collateral over and deposit in gauge
        _transferFromWithoutAllowance(account, liquidator, shares);
        gaugePool.deposit(address(this), liquidator, shares);
    }

    /// @notice Returns whether the MToken is a cToken
    function isCToken() public pure returns (bool) {
        return true;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual returns (bool) {
        return
            interfaceId == type(IMToken).interfaceId ||
            interfaceId == type(ERC4626).interfaceId;
    }

    // ACCOUNTING LOGIC

    function totalAssetsSafe() public virtual nonReentrant returns (uint256) {
        // Returns stored internal balance.
        // Has added re-entry lock for protocols building ontop of us to have confidence in data quality
        return _totalAssets;
    }

    function totalAssets() public view virtual override returns (uint256) {
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

    /// @notice Used to start a CToken market, executed via lendtroller
    /// @dev This initial mint is a failsafe against rounding exploits,
    ///      although, we protect against it in many ways,
    ///      better safe than sorry
    /// @param by The account initializing the market
    function _startMarket(address by) internal {
        if (msg.sender != address(lendtroller)) {
            _revert(_UNAUTHORIZED_SELECTOR);
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
    function _gaugePool() internal view returns (IGaugePool) {
        return lendtroller.gaugePool();
    }

    /// @dev Checks whether the caller has sufficient permissioning
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// INTERNAL FUNCTIONS TO OVERRIDE ///

    /// @notice Caller deposits assets into the market and receives shares
    /// @param assets The amount of the underlying asset to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return shares the amount of cToken shares received by `receiver`
    function _deposit(
        uint256 assets,
        address receiver
    ) internal virtual returns (uint256 shares) {}

    /// @notice Caller deposits assets into the market and receives shares
    /// @param shares The amount of the underlying assets quoted in shares to supply
    /// @param receiver The account that should receive the cToken shares
    /// @return assets the amount of cToken shares quoted in assets received by `receiver`
    function _mint(
        uint256 shares,
        address receiver
    ) internal virtual returns (uint256 assets) {}

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
    ) internal virtual returns (uint256 shares) {}

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
    ) internal virtual returns (uint256 assets) {}
}
