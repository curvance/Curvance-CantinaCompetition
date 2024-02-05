// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { ERC4626, SafeTransferLib } from "contracts/libraries/ERC4626.sol";
import { FixedPointMathLib } from "contracts/libraries/FixedPointMathLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev Curvance's cTokens are ERC4626 compliant. However, they follow their
///      own design flow modifying underlying mechanisms such as totalAssets
///      following a vesting mechanism in compounding vaults but a direct
///      conversion in basic or "primitive" vaults.
///
///      The "cToken" employs two different methods of engaging with the
///      Curvance protocol. Users can deposit an unlimited amount of assets,
///      which may or may not benefit from some form of auto compounded yield.
///
///      Users can at any time, choose to "post" their cTokens as collateral
///      inside the Curvance Protocol, unlocking their ability to borrow
///      against these assets. Posting collateral carries restrictions,
///      not all assets inside Curvance can be collateralized, and if they
///      can, they have a "Collateral Cap" which restricts the total amount of
///      exogeneous risk introduced by each asset into the system.
///      Rehypothecation of collateral assets has also been removed from the
///      system, reducing the likelihood of introducing systematic risk to the
///      broad DeFi landscape.
///
///      These caps can be updated as needed by the DAO and should be
///      configured based on "sticky" onchain liquidity in the corresponding
///      asset. 
///      The vaults have the ability to have their compounding, minting,
///      or redemption functionality paused. Modifying the maximum mint,
///      deposit, withdrawal, or redemptions possible.
///     
///      "Safe" versions of functions have been added that introduce
///      additional reentry and update protection logic to minimize risks
///      when integrating Curvance into external protocols.
///
abstract contract CTokenBase is ERC4626, ReentrancyGuard {
    /// CONSTANTS ///

    /// @dev `bytes4(keccak256(bytes("CTokenBase__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xbf98a75b;
    /// @dev `keccak256(bytes("Deposit(address,address,uint256,uint256)"))`.
    uint256 internal constant _DEPOSIT_EVENT_SIGNATURE =
        0xdcbc1c05240f31ff3ad067ef1ee35ce4997762752e3a095284754544f4c709d7;
    /// @dev `keccak256(bytes("Withdraw(address,address,address,uint256,uint256)"))`.
    uint256 internal constant _WITHDRAW_EVENT_SIGNATURE =
        0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db;
    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 internal constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _BALANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 internal constant _BALANCE_SLOT_SEED = 0x87a211a2;

    /// @notice Money Market Manager.
    IMarketManager public immutable marketManager;
    /// @notice Curvance DAO Hub.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Underlying asset for the CToken.
    IERC20 internal immutable _asset;
    /// @notice CToken decimals.
    uint8 internal immutable _decimals;
    
    /// STORAGE ///

    /// @notice Token name metadata.
    string internal _name;
    /// @notice Token symbol metadata.
    string internal _symbol;
    /// @notice Total CToken underlying token assets, minus pending vesting.
    uint256 internal _totalAssets;

    /// ERRORS ///

    error CTokenBase__Unauthorized();
    error CTokenBase__InvalidCentralRegistry();
    error CTokenBase__InvalidMarketManager();
    error CTokenBase__UnderlyingAssetTotalSupplyExceedsMaximum();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address MarketManager_
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

        // Ensure that marketManager parameter is a marketManager.
        if (!centralRegistry.isMarketManager(MarketManager_)) {
            revert CTokenBase__InvalidMarketManager();
        }

        // Set `marketManager`.
        marketManager = IMarketManager(MarketManager_);

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate, in `WAD`.
        if (asset_.totalSupply() >= type(uint232).max) {
            revert CTokenBase__UnderlyingAssetTotalSupplyExceedsMaximum();
        }
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Caller deposits assets into the market, receives shares,
    ///         and turns on collateralization of the assets.
    /// @param assets The amount of the underlying assets to deposit.
    /// @param receiver The account that should receive the cToken shares.
    /// @return shares The amount of cToken shares received by `receiver`.
    function depositAsCollateral(
        uint256 assets,
        address receiver
    ) external nonReentrant returns (uint256 shares) {
        shares = _deposit(assets, receiver);
        if (
            msg.sender == receiver ||
            msg.sender == marketManager.positionFolding()
        ) {
            marketManager.postCollateral(receiver, address(this), shares);
        }
    }

    /// @notice Caller withdraws assets from the market and burns their shares.
    /// @dev Forces collateral to be withdrawn from `owner` collateralPosted.
    /// @param assets The amount of the underlying assets to withdraw.
    /// @param receiver The account that should receive the assets.
    /// @param owner The account that will burn their shares to withdraw assets.
    /// @return shares the amount of cToken shares redeemed by `owner`.
    function withdrawCollateral(
        uint256 assets,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 shares) {
        shares = _withdraw(assets, receiver, owner, true);
    }

    /// @notice Caller withdraws assets from the market and burns their shares.
    /// @dev Forces collateral to be withdrawn from `owner` collateralPosted.
    /// @param shares The amount of shares to redeemed.
    /// @param receiver The account that should receive the assets.
    /// @param owner The account that will burn their shares to withdraw assets.
    /// @return assets the amount of assets redeemed by `owner`.
    function redeemCollateral(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 assets) {
        assets = _redeem(shares, receiver, owner, true);
    }

    /// @notice Returns the underlying balance of the `account`, safely.
    /// @param account The address of the account to query.
    /// @return The amount of underlying owned by `account`.
    function balanceOfUnderlyingSafe(
        address account
    ) external view returns (uint256) {
        return ((convertToAssetsSafe(WAD) * balanceOf(account)) / WAD);
    }

    /// @notice Returns the underlying balance of the `account`.
    /// @param account The address of the account to query.
    /// @return The amount of underlying owned by `account`.
    function balanceOfUnderlying(
        address account
    ) external view returns (uint256) {
        return ((convertToAssets(WAD) * balanceOf(account)) / WAD);
    }

    /// @notice Returns share -> asset exchange rate, in `WAD`, safely.
    /// @dev Oracle router calculates CToken value from this exchange rate.
    function exchangeRateSafe() external view returns (uint256) {
        return convertToAssetsSafe(WAD);
    }

    /// @notice Returns share -> asset exchange rate, in `WAD`.
    /// @dev Oracle router calculates CToken value from this exchange rate.
    function exchangeRateCached() external view returns (uint256) {
        return convertToAssets(WAD);
    }

    /// @notice Get a snapshot of the account's balances,
    ///         and the cached exchange rate.
    /// @dev Used by MarketManager to efficiently perform liquidity checks.
    /// @param account Address of the account to snapshot.
    /// @return Current account shares balance.
    /// @return Current account borrow balance, which will be 0, 
    ///         kept for composability.
    /// @return Current exchange rate between assets and shares, in `WAD`.
    function getSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return (balanceOf(account), 0, convertToAssets(WAD));
    }

    /// @notice Returns a snapshot of the cToken and `account` data.
    /// @dev Used by MarketManager to efficiently perform liquidity checks.
    /// NOTE: debtBalance always return 0 to runtime gas in MarketManager
    ///       since it is unused.
    function getSnapshotPacked(
        address
    ) external view returns (AccountSnapshot memory) {
        return (
            AccountSnapshot({
                asset: address(this),
                isCToken: true,
                decimals: decimals(),
                debtBalance: 0, // This is a cToken so always 0.
                exchangeRate: convertToAssets(WAD)
            })
        );
    }

    /// CTOKEN MARKET START LOGIC TO OVERRIDE

    function startMarket(address by) external virtual returns (bool) {}

    /// PUBLIC FUNCTIONS ///

    // VAULT DATA FUNCTIONS

    /// @notice Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the address of the underlying asset.
    /// @dev We have both asset() and underlying() for composability.
    function asset() public view override returns (address) {
        return address(_asset);
    }

    /// @notice Returns the address of the underlying asset.
    /// @dev We have both asset() and underlying() for composability.
    function underlying() external view returns (address) {
        return address(_asset);
    }

    /// @notice Returns the maximum assets that can be deposited at a time.
    /// @dev If depositing is disabled maxAssets should be equal to 0,
    ///      according to ERC4626 spec.
    /// @param to The address who would receive minted shares.
    function maxDeposit(
        address to
    ) public view override returns (uint256 maxAssets) {
        if (
            !marketManager.isListed(address(this)) || 
            marketManager.mintPaused(address(this)) == 2
            ) {
            // We do not need to set maxAssets here since its initialized
            // as 0 so we can just return.
            return maxAssets;
        }
        maxAssets = super.maxDeposit(to);
    }

    /// @notice Returns the maximum shares that can be minted at a time.
    /// @dev If depositing is disabled minMint should be equal to 0,
    ///      according to ERC4626 spec.
    /// @param to The address who would receive minted shares.
    function maxMint(
        address to
    ) public view override returns (uint256 maxShares) {
        if (
            !marketManager.isListed(address(this)) || 
            marketManager.mintPaused(address(this)) == 2
            ) {
            // We do not need to set maxShares here since its initialized
            // as 0 so we can just return.
            return maxShares;
        }
        maxShares = super.maxMint(to);
    }

    /// TOKEN ACTION FUNCTIONS ///

    /// @notice Caller deposits assets into the market and receives shares.
    /// @param assets The amount of the underlying assets to deposit.
    /// @param receiver The account that should receive the cToken shares.
    /// @return shares The amount of cToken shares received by `receiver`.
    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    /// @notice Caller deposits assets into the market and receives shares.
    /// @param shares The amount of the underlying assets quoted in shares
    ///               to deposit.
    /// @param receiver The account that should receive the cToken shares.
    /// @return assets The amount of cToken shares quoted in assets received
    ///                by `receiver`.
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        assets = _mint(shares, receiver);
    }

    /// @notice Withdraws `assets` from the market, and burns `owner` shares.
    /// @dev Does not force collateral posted to be withdrawn.
    /// @param assets The amount of the underlying assets to withdraw.
    /// @param receiver The account that should receive the assets.
    /// @param owner The account that will burn their shares to withdraw
    ///              assets.
    /// @return shares The amount of cToken shares redeemed by `owner`.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        shares = _withdraw(assets, receiver, owner, false);
    }

    /// @notice Withdraws assets, quoted in `shares` from the market,
    ///         and burns `owner` shares.
    /// @dev Does not force collateral to be withdrawn.
    /// @param shares The amount of shares to be redeemed.
    /// @param receiver The account that should receive the assets.
    /// @param owner The account that will burn their shares to withdraw
    ///              assets.
    /// @return assets The amount of assets redeemed by `owner`.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        assets = _redeem(shares, receiver, owner, false);
    }

    /// @notice Transfers `amount` tokens from caller to `to`.
    /// @param to The address of the destination account to receive `amount`
    ///           shares.
    /// @param amount The number of tokens to transfer from caller to `to`.
    /// @return Whether or not the transfer succeeded or not.
    function transfer(
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        // Fails if transfer not allowed.
        marketManager.canTransfer(address(this), msg.sender, amount);

        // Cache gaugePool, then update gauge pool values for caller.
        IGaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), msg.sender, amount);

        // Execute transfer.
        super.transfer(to, amount);
        // Update gauge pool values for `to`.
        gaugePool.deposit(address(this), to, amount);

        return true;
    }

    /// @notice Transfers `amount` tokens from `from` to `to`.
    /// @param from The address of the account transferring `amount`
    ///             shares from.
    /// @param to The address of the destination account to receive `amount`
    ///           shares.
    /// @param amount The number of tokens to transfer from `from` to `to`.
    /// @return Whether or not the transfer succeeded or not.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        // Fails if transfer not allowed.
        marketManager.canTransfer(address(this), from, amount);

        // Cache gaugePool, then update gauge pool values for `from`.
        IGaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), from, amount);

        // Execute transfer.
        super.transferFrom(from, to, amount);
        // Update gauge pool values for `to`.
        gaugePool.deposit(address(this), to, amount);

        return true;
    }

    /// @notice Transfers collateral tokens (this cToken) from `account`
    ///         to `liquidator`.
    /// @dev Will fail unless called by a dToken during the process
    ///      of liquidation.
    /// @param liquidator The account receiving seized collateral.
    /// @param account The account having collateral seized.
    /// @param liquidatedTokens The total number of cTokens to seize.
    /// @param protocolTokens The number of cTokens to seize for the protocol.
    function seize(
        address liquidator,
        address account,
        uint256 liquidatedTokens,
        uint256 protocolTokens
    ) external nonReentrant {
        // Fails if borrower = liquidator.
        assembly {
            if eq(liquidator, account) {
                // revert with "CTokenBase__Unauthorized".
                mstore(0x00, _UNAUTHORIZED_SELECTOR)
                revert(0x1c, 0x04)
            }
        }

        // Fails if seize not allowed.
        marketManager.canSeize(address(this), msg.sender);
        // Calculate tokens to transfer to `liquidator`.
        uint256 liquidatorTokens = liquidatedTokens - protocolTokens;

        // Cache gaugePool, then update gauge pool values for `account`.
        IGaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), account, liquidatedTokens);

        // Efficiently transfer token balances from `account` to `liquidator`.
        _transferFromWithoutAllowance(account, liquidator, liquidatorTokens);
        // Update gauge pool values for `liquidator`.
        gaugePool.deposit(address(this), liquidator, liquidatorTokens);

        if (protocolTokens > 0) {
            address daoAddress = centralRegistry.daoAddress();
            // Efficiently transfer token balances from `account` to `daoAddress`.
            _transferFromWithoutAllowance(account, daoAddress, protocolTokens);
            // Update gauge pool values for new reserves.
            gaugePool.deposit(address(this), daoAddress, protocolTokens);
        }
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Will fail unless called by the MarketManager itself during
    ///      the process of liquidation.
    ///      NOTE: The protocol never takes a fee on account liquidation
    ///            as lenders already are bearing a burden.
    /// @param liquidator The account receiving seized collateral.
    /// @param account The account having collateral seized.
    /// @param shares The total number of cTokens shares to seize.
    function seizeAccountLiquidation(
        address liquidator,
        address account,
        uint256 shares
    ) external nonReentrant {
        // We check self liquidation in MarketManager before
        // this call so we do not need to check here.

        // Make sure the MarketManager itself is calling since
        // then we know all liquidity checks have passed.
        if (msg.sender != address(marketManager)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Cache gaugePool, then update gauge pool values, for `account`.
        IGaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), account, shares);

        // Efficiently transfer token balances from `account` to `liquidator`.
        _transferFromWithoutAllowance(account, liquidator, shares);
        // Update gauge pool values for `liquidator`.
        gaugePool.deposit(address(this), liquidator, shares);
    }

    /// @notice Returns whether the MToken is a cToken or not.
    function isCToken() public pure returns (bool) {
        return true;
    }

    /// @dev Returns true that this contract implements both ERC4626
    ///      and IMToken interfaces.
    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual returns (bool) {
        return
            interfaceId == type(IMToken).interfaceId ||
            interfaceId == type(ERC4626).interfaceId;
    }

    // ACCOUNTING LOGIC

    /// @notice Returns the total number of assets backing shares, safely.
    function totalAssetsSafe() public view virtual nonReadReentrant returns (uint256) {
        return _totalAssets;
    }

    /// @notice Returns the total number of assets backing shares.
    function totalAssets() public view virtual override returns (uint256) {
        return _totalAssets;
    }

    /// @notice Returns the amount of shares that would be exchanged
    ///         by the vault for `assets` provided, safely.
    /// @param assets The number of assets to theoretically use
    ///               for conversion to shares.
    /// @return The number of shares a user would receive for converting
    ///         `assets`.
    function convertToSharesSafe(
        uint256 assets
    ) public view nonReadReentrant returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    /// @notice Returns the amount of shares that would be exchanged
    ///         by the vault for `assets` provided.
    /// @param assets The number of assets to theoretically use
    ///               for conversion to shares.
    /// @return The number of shares a user would receive for converting
    ///         `assets`.
    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    /// @notice Returns the amount of assets that would be exchanged
    ///         by the vault for `shares` provided, safely.
    /// @param shares The number of shares to theoretically use
    ///               for conversion to assets.
    /// @return The number of assets a user would receive for converting
    ///         `assets`.
    function convertToAssetsSafe(
        uint256 shares
    ) public view nonReadReentrant returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    /// @notice Returns the amount of assets that would be exchanged
    ///         by the vault for `shares` provided.
    /// @param shares The number of shares to theoretically use
    ///               for conversion to assets.
    /// @return The number of assets a user would receive for converting
    ///         `shares`.
    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their deposit at
    ///         the current block.
    /// @param assets The number of assets to preview a deposit call.
    /// @return The shares received for depositing `assets`.
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        return _previewDeposit(assets, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their mint at
    ///         the current block.
    /// @param shares The number of assets, quoted as shares to preview
    ///               a mint call.
    /// @return The shares received quoted as assets for depositing `shares`.
    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        return _previewMint(shares, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their withdraw
    ///         at the current block.
    /// @param assets The number of assets to preview a withdraw call.
    /// @return The assets received quoted as shares for withdrawing `assets`.
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return _previewWithdraw(assets, totalAssets());
    }

    /// @notice Allows users to simulate the effects of their redeem at
    ///         the current block.
    /// @param shares The number of assets, quoted as shares to preview
    ///               a redeem call.
    /// @return The assets received for withdrawing `shares`.
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return _previewRedeem(shares, totalAssets());
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Helper function to efficiently transfers cToken balances
    ///         without checking approvals.
    /// @dev This is only used in liquidations where maximal gas
    ///      optimization improves protocol MEV competitiveness,
    ///      improving protocol safety.
    ///      Emits a {Transfer} event.
    /// @param from The address of the account transferring `amount`
    ///             shares from.
    /// @param to The address of the destination account to receive `amount`
    ///           shares.
    /// @param amount The number of tokens to transfer from `from` to `to`.
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

    /// @notice Starts a cToken market, executed via marketManager.
    /// @dev This initial mint is a failsafe against rounding exploits,
    ///      although, we protect against them in many ways,
    ///      better safe than sorry.
    /// @dev Emits a {Deposit} event.
    /// @param by The account initializing the cToken market.
    function _startMarket(address by) internal {
        if (msg.sender != address(marketManager)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 assets = 42069;
        address market = address(this);

        SafeTransferLib.safeTransferFrom(asset(), by, market, assets);

        // Because nobody can deposit into the market before startMarket()
        // is called, this will always be the initial call.
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

    /// @dev Returns the decimals of the underlying asset.
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Returns the amount of shares that would be exchanged by the
    ///         vault for `assets` provided.
    /// @param assets The number of assets to theoretically use
    ///               for conversion to shares.
    /// @param ta The total number of assets to theoretically use
    ///           for conversion to shares.
    /// @return shares The number of shares a user would receive for
    ///                converting `assets`.
    function _convertToShares(
        uint256 assets,
        uint256 ta
    ) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets
            : FixedPointMathLib.mulDiv(assets, totalShares, ta);
    }

    /// @notice Returns the amount of assets that would be exchanged by the
    ///         vault for `shares` provided.
    /// @param shares The number of shares to theoretically use
    ///               for conversion to assets.
    /// @param ta The total number of assets to theoretically use
    ///           for conversion to assets.
    /// @return assets The number of assets a user would receive for
    ///                converting `shares`.
    function _convertToAssets(
        uint256 shares,
        uint256 ta
    ) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares
            : FixedPointMathLib.mulDiv(shares, ta, totalShares);
    }

    /// @notice Simulates the effects of a user deposit at the current
    ///         block.
    /// @param assets The number of assets to preview a deposit call.
    /// @param ta The total number of assets to simulate a deposit at the
    ///           current block.
    /// @return The shares received for depositing `assets`.
    function _previewDeposit(
        uint256 assets,
        uint256 ta
    ) internal view returns (uint256) {
        return _convertToShares(assets, ta);
    }

    /// @notice Simulates the effects of a user mint at the current
    ///         block.
    /// @param shares The number of shares to preview a mint call.
    /// @param ta The total number of assets to simulate a mint at the
    ///           current block.
    /// @return assets The assets received for minting `shares`.
    function _previewMint(
        uint256 shares,
        uint256 ta
    ) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0 ? shares : FixedPointMathLib.mulDivUp(
            shares, 
            ta, 
            totalShares
        );
    }

    /// @notice Simulates the effects of a user withdrawal at the current
    ///         block.
    /// @param assets The number of assets to preview a withdrawal call.
    /// @param ta The total number of assets to simulate a withdrawal at the
    ///           current block.
    /// @return shares The shares received for withdrawing `assets`.
    function _previewWithdraw(
        uint256 assets,
        uint256 ta
    ) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0 ? assets : FixedPointMathLib.mulDivUp(
            assets, 
            totalShares, 
            ta
        );
    }

    /// @notice Simulates the effects of a user redemption at the current
    ///         block.
    /// @param shares The number of shares to preview a redemption call.
    /// @param ta The total number of assets to simulate a redemption at the
    ///           current block.
    /// @return The assets received for redeeming `shares`.
    function _previewRedeem(
        uint256 shares,
        uint256 ta
    ) internal view returns (uint256) {
        return _convertToAssets(shares, ta);
    }

    /// @notice Returns the gauge pool contract address.
    /// @return The gauge controller contract address, in `IGaugePool` form.
    function _gaugePool() internal view returns (IGaugePool) {
        return marketManager.gaugePool();
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// INTERNAL CONVERSION FUNCTIONS TO OVERRIDE ///

    /// @notice Deposits `assets` and mints shares to `receiver`.
    /// @param assets The amount of the underlying assets to supply.
    /// @param receiver The account that should receive the cToken shares.
    /// @return shares The amount of cToken shares received by `receiver`.
    function _deposit(
        uint256 assets,
        address receiver
    ) internal virtual returns (uint256 shares) {}

    /// @notice Deposits assets and mints `shares` to `receiver`.
    /// @param shares The amount of the underlying assets quoted in shares
    ///               to supply.
    /// @param receiver The account that should receive the cToken shares.
    /// @return assets The amount of cToken shares quoted in assets received
    ///                by `receiver`.
    function _mint(
        uint256 shares,
        address receiver
    ) internal virtual returns (uint256 assets) {}

    /// @notice Withdraws `assets` to `receiver` from the market and burns
    ///         `owner` shares.
    /// @param assets The amount of the underlying assets to withdraw.
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
    ) internal virtual returns (uint256 shares) {}

    /// @notice Withdraws assets to `receiver` from the market and burns
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
    ) internal virtual returns (uint256 assets) {}
}
