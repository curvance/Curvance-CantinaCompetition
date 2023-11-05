// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165 } from "contracts/libraries/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ERC4626, SafeTransferLib, ERC20 } from "contracts/libraries/ERC4626.sol";
import { Math } from "contracts/libraries/Math.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { EXP_SCALE } from "contracts/libraries/Constants.sol";

/// @notice Vault Positions must have all assets ready for withdraw,
///         IE assets can NOT be locked.
///         This way assets can be easily liquidated when loans default.
/// @dev The CToken vaults run must be a LOSSLESS position, since totalAssets
///      is not actually using the balances stored in the position,
///      rather it only uses an internal balance.
abstract contract CTokenCompoundingBase is ERC4626, ReentrancyGuard {
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

    // Period harvested rewards are vested over
    uint256 public vestPeriod = 1 days;
    NewVestingData public pendingVestUpdate;
    ERC20 private immutable _asset; // underlying asset for the vault
    
    uint8 private immutable _decimals; // vault assets decimals of precision
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    // `bytes4(keccak256(bytes("CTokenCompoundingBase__VaultNotActive()")))`
    uint256 internal constant VAULT_NOT_ACTIVE_SELECTOR = 0xe4247f94;
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

    /// @notice Current lending market controller
    ILendtroller public lendtroller;
    
    /// @notice token name metadata
    string internal _name;
    /// @notice token symbol metadata
    string internal _symbol;
    // Internal stored vault accounting
    // Bits Layout:
    // - [0..127]    `rewardRate`
    // - [128..191]  `vestingPeriodEnd`
    // - [192..255] `lastVestClaim`
    uint256 internal _vaultData; // Packed vault data
    uint256 internal _totalAssets; // total vault assets minus vesting
    uint256 internal _vaultIsActive; // Vault Status: 2 = active; 0 or 1 = inactive

    /// EVENTS ///

    event NewLendtroller(address oldLendtroller, address newLendtroller);
    event vaultStatusChanged(bool isShutdown);

    /// ERRORS ///

    error CTokenCompoundingBase__InvalidVestPeriod();
    error CTokenCompoundingBase__Unauthorized();
    error CTokenCompoundingBase__InvalidCentralRegistry();
    error CTokenCompoundingBase__RedeemMoreThanMax();
    error CTokenCompoundingBase__WithdrawMoreThanMax();
    error CTokenCompoundingBase__VaultNotActive();
    error CTokenCompoundingBase__VaultIsActive();
    error CTokenCompoundingBase__ZeroShares();
    error CTokenCompoundingBase__ZeroAssets();
    error CTokenCompoundingBase__TransferError();
    error CTokenCompoundingBase__UnderlyingAssetTotalSupplyExceedsMaximum();
    error CTokenCompoundingBase__LendtrollerIsNotLendingMarket();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert CTokenCompoundingBase__Unauthorized();
        }
        _;
    }

    modifier onlyElevatedPermissions() {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            revert CTokenCompoundingBase__Unauthorized();
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
        _name = string.concat(
            "Curvance collateralized ",
            asset_.name()
        );
        _symbol = string.concat("c", asset_.symbol());
        _decimals = asset_.decimals();
        
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CTokenCompoundingBase__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;
        // Set the lendtroller after consulting Central Registry
        _setLendtroller(lendtroller_);

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate of 1e18
        if (asset_.totalSupply() >= type(uint232).max) {
            revert CTokenCompoundingBase__UnderlyingAssetTotalSupplyExceedsMaximum();
        }
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Used to start a CToken market, executed via lendtroller
    /// @dev this initial mint is a failsafe against the empty market exploit
    ///      although we protect against it in many ways,
    ///      better safe than sorry
    /// @param by the account initializing the market
    function startMarket(
        address by
    ) external nonReentrant returns (bool) {
        if (msg.sender != address(lendtroller)) {
            revert CTokenCompoundingBase__Unauthorized();
        }

        uint256 assets = 42069;
        address market = address(this);

        SafeTransferLib.safeTransferFrom(
            asset(),
            by,
            market,
            assets
        );

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
            log3(0x00, 0x40, _DEPOSIT_EVENT_SIGNATURE, and(m, market), and(m, market))
        }

        _afterDeposit(assets, shares);

        _vaultIsActive = 2;
        emit vaultStatusChanged(false);

        return true;
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

    function setVestingPeriod(uint256 newVestingPeriod) external onlyDaoPermissions {
        if (newVestingPeriod > 7 days) {
            revert CTokenCompoundingBase__InvalidVestPeriod();
        }
        
        pendingVestUpdate.updateNeeded = true;
        pendingVestUpdate.newVestPeriod = uint248(newVestingPeriod);
    }

    /// @notice Shuts down the vault
    /// @dev Used in an emergency or if the vault has been deprecated
    function initiateShutdown() external onlyDaoPermissions {
        if (_vaultIsActive != 2) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

        _vaultIsActive = 1;

        emit vaultStatusChanged(true);
    }

    /// @notice Reactivate the vault
    /// @dev Allows for reconfiguration of cToken attached to vault
    function liftShutdown() external onlyElevatedPermissions {
        if (_vaultIsActive == 2) {
            // revert with "CTokenCompoundingBase__VaultIsActive"
            _revert(0x3a2c4eed);
        }

        _vaultIsActive = 2;
        emit vaultStatusChanged(false);
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
    function balanceOfUnderlyingSafe(address account) external returns (uint256) {
        return ((convertToAssetsSafe(EXP_SCALE) * balanceOf(account)) / EXP_SCALE);
    }

    /// @notice Get the underlying balance of the `account`
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlying(address account) external view returns (uint256) {
        return ((convertToAssets(EXP_SCALE) * balanceOf(account)) / EXP_SCALE);
    }

    /// @notice Get a snapshot of the account's balances,
    ///         and the cached exchange rate
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    /// @return tokenBalance
    /// @return borrowBalance
    /// @return exchangeRate scaled 1e18
    function getSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return (balanceOf(account), 0, convertToAssets(EXP_SCALE));
    }

    /// @notice Get a snapshot of the cToken and `account` data
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    function getSnapshotPacked(
        address account
    ) external view returns (AccountSnapshot memory) {
        return (
            AccountSnapshot({
                asset: address(this),
                isCToken: true,
                decimals: decimals(),
                balance: balanceOf(account),
                debtBalance: 0,
                exchangeRate: convertToAssets(EXP_SCALE)
            })
        );
    }

    /// @notice Rescue any token sent by mistake
    /// @param token token to rescue
    /// @param amount amount of `token` to rescue, 0 indicates to rescue all
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
                revert CTokenCompoundingBase__TransferError();
            }

            if (amount == 0) {
                amount = ERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    // EXTERNAL POSITION LOGIC TO OVERRIDE

    function harvest(bytes calldata) external virtual returns (uint256 yield);

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

    /// @notice Returns the position vaults current status
    function vaultStatus() public view returns (string memory) {
        return _vaultIsActive == 2 ? "Active" : "Inactive";
    }

    function maxDeposit(
        address to
    ) public view override returns (uint256 maxAssets) {
        maxAssets = _vaultIsActive == 2 ? super.maxDeposit(to) : 0;
    }

    function maxMint(
        address to
    ) public view override returns (uint256 maxShares) {
        maxShares = _vaultIsActive == 2 ? super.maxMint(to) : 0;
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

    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        if (assets == 0 || assets > maxDeposit(receiver)) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

        // Fail if deposit not allowed
        lendtroller.canMint(address(this));

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewDeposit
        if ((shares = _previewDeposit(assets, ta)) == 0) {
            revert CTokenCompoundingBase__ZeroShares();
        }

        _deposit(msg.sender, receiver, assets, shares, ta, pending);
        // emit events on gauge pool
        _gaugePool().deposit(address(this), receiver, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        if (assets == 0 || assets > maxMint(receiver)) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

        // Fail if mint not allowed
        lendtroller.canMint(address(this));

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // No need to check for rounding error, previewMint rounds up
        assets = _previewMint(shares, ta);

        _deposit(msg.sender, receiver, assets, shares, ta, pending);
        // emit events on gauge pool
        _gaugePool().deposit(address(this), receiver, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // We use a modified version of maxWithdraw with newly vested assets
        if (assets > _convertToAssets(balanceOf(owner), ta)){
            // revert with "CTokenCompoundingBase__WithdrawMoreThanMax"
            _revert(0x2735eaab);
        } 

        // No need to check for rounding error, previewWithdraw rounds up
        shares = _previewWithdraw(assets, ta);
        lendtroller.canRedeem(address(this), owner, shares);

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
        _withdraw(msg.sender, receiver, owner, assets, shares, ta, pending);
    }

    /// @notice Helper function for Position Folding contract to
    ///         redeem underlying tokens
    /// @param owner The owner address of assets to redeem
    /// @param assets The amount of the underlying asset to redeem
    function withdrawByPositionFolding(
        address owner,
        uint256 assets,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert CTokenCompoundingBase__Unauthorized();
        }

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // We use a modified version of maxWithdraw with newly vested assets
        if (assets > _convertToAssets(balanceOf(owner), ta)){
            // revert with "CTokenCompoundingBase__WithdrawMoreThanMax"
            _revert(0x2735eaab);
        } 

        // No need to check for rounding error, previewWithdraw rounds up
        uint256 shares = _previewWithdraw(assets, ta);

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
        _withdraw(msg.sender, msg.sender, owner, assets, shares, ta, pending);

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            owner,
            assets,
            params
        );

        // Fail if redeem not allowed
        lendtroller.canRedeem(address(this), owner, 0);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        if (shares > maxRedeem(owner)){
            // revert with "CTokenCompoundingBase__RedeemMoreThanMax"
            _revert(0x682b852f);
        } 

        lendtroller.canRedeem(address(this), owner, shares);

        // Save _totalAssets and pendingRewards to memory
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewRedeem
        if ((assets = _previewRedeem(shares, ta)) == 0) {
            revert CTokenCompoundingBase__ZeroAssets();
        }

        // emit events on gauge pool
        _gaugePool().withdraw(address(this), owner, shares);
        _withdraw(msg.sender, receiver, owner, assets, shares, ta, pending);
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
                // revert with "CTokenCompoundingBase__Unauthorized"
                mstore(0x00, 0x3d6b2189)
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
            _transferFromWithoutAllowance(borrower, daoAddress, protocolTokens);
            gaugePool.deposit(address(this), daoAddress, protocolTokens);
        }

    }

    /// @notice Returns whether the MToken is a cToken
    function isCToken() public pure returns (bool) {
        return true;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public pure returns (bool) {
        return interfaceId == type(IMToken).interfaceId;
    }

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
        return _convertToShares(assets, totalAssets());
    }

    /// @notice Pull up-to-date exchange rate from the underlying to
    ///         the CToken with reEntry lock
    /// @return Calculated exchange rate scaled by 1e18
    function convertToAssetsSafe(uint256 shares) public nonReentrant returns (uint256) {
        return _convertToAssets(shares, totalAssets());
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

    function _deposit(
        address by,
        address to, 
        uint256 assets, 
        uint256 shares, 
        uint256 ta, 
        uint256 pending
    ) internal {

        // Need to transfer before minting or ERC777s could reenter
        SafeTransferLib.safeTransferFrom(
            asset(),
            by,
            address(this),
            assets
        );

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

    function _withdraw(
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

    function _transferFromWithoutAllowance(address from, address to, uint256 amount) internal {
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
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
        }
    }

    /// @notice Sets a new lendtroller for the market
    /// @param newLendtroller New lendtroller address
    function _setLendtroller(address newLendtroller) internal {
        // Ensure that lendtroller parameter is a lendtroller
        if (!centralRegistry.isLendingMarket(newLendtroller)) {
            revert CTokenCompoundingBase__LendtrollerIsNotLendingMarket();
        }

        // Cache the current lendtroller to save gas
        address oldLendtroller = address(lendtroller);

        // Set new lendtroller
        lendtroller = ILendtroller(newLendtroller);

        emit NewLendtroller(oldLendtroller, newLendtroller);
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

    /// @dev Returns the decimals of the underlying asset
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
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
            // Divide the pending rewards by EXP_SCALE
            pendingRewards =
                (
                    block.timestamp < vaultData.vestingPeriodEnd
                        ? (vaultData.rewardRate *
                            (block.timestamp - vaultData.lastVestClaim))
                        : (vaultData.rewardRate *
                            (vaultData.vestingPeriodEnd -
                                vaultData.lastVestClaim))
                ) /
                EXP_SCALE;
        }
        // else there are no pending rewards
    }

    /// @notice Vests the pending rewards, updates vault data
    ///         and share price high watermark
    /// @param currentAssets The current assets of the vault
    function _vestRewards(uint256 currentAssets) internal {
        // Update the lastVestClaim timestamp
        _setlastVestClaim(uint64(block.timestamp));

        // Set internal balance equal to totalAssets value
        _totalAssets = currentAssets;
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

    /// INTERNAL POSITION LOGIC TO OVERRIDE

    function _getRealPositionBalance() internal view virtual returns (uint256);
}
