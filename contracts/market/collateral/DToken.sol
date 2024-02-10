// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DynamicInterestRateModel } from "contracts/market/DynamicInterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import { WAD } from "contracts/libraries/Constants.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance's Debt Token Contract.
/// @dev Curvance's dTokens are ERC20 compliant with a close relation
///      to ERC4626. However, they follow their own design flow, without an
///      inherited base contract. This is done intentionally, to maximize
///      security in an age of rapidly developing security attack vectors.
///
///      The "dToken" employs a share/asset structure with slightly different
///      configuration, and terminology (to prevent confusion). The variable
///      terms "tokens", and "amount" are used to refer to dTokens values, 
///      and underlying asset values. When you see "Tokens" that is associated
///      with dTokens, when you see "amount" that is associated with
///      underlying assets.
///
///      Users who have active positions inside a dToken are referred to
///      as accounts. For actions that can be performed by an external party,
///      that will not result in active positions for themselves, more general
///      terms are used such as "Liquidator", "Minter", or "Payer".
///
///      "Safe" versions of functions have been added that introduce
///      additional reentry and update protection logic to minimize risks
///      when integrating Curvance into external protocols.
contract DToken is ERC165, ReentrancyGuard {
    /// TYPES ///

    /// @param principal Principal total balance (with accrued interest).
    /// @param accountExchangeRate Current exchange rate for account.
    struct DebtData {
        uint256 principal;
        uint256 accountExchangeRate;
    }

    /// @param lastTimestampUpdated Timestamp interest was last update.
    /// @param exchangeRate Borrow exchange rate at `lastTimestampUpdated`.
    /// @param compoundRate Rate at which interest compounds, in seconds.
    struct MarketData {
        uint40 lastTimestampUpdated;
        uint216 exchangeRate;
        uint256 compoundRate;
    }

    /// CONSTANTS ///

    /// @notice The underlying asset for the DToken.
    address public immutable underlying;
    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Address of the Market Manager linked to this contract.
    IMarketManager public immutable marketManager;

    /// @dev `bytes4(keccak256(bytes("DToken__Unauthorized()")))`.
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xef419be2;
    /// @dev The base underlying asset requirement held in order to minimize
    ///      rounding exploits, and more generally, invariant manipulation.
    uint256 internal constant _BASE_UNDERLYING_RESERVE = 42069;

    /// STORAGE ///

    /// @notice token name metadata.
    string public name;
    /// @notice token symbol metadata.
    string public symbol;
    /// @notice Total number of tokens in circulation.
    uint256 public totalSupply;
    /// @notice Returns total amount of outstanding borrows of the
    ///         underlying in this dToken market.
    uint256 public totalBorrows;
    /// @notice Total protocol reserves of underlying.
    uint256 public totalReserves;
    /// @notice Interest rate reserve factor.
    uint256 public interestFactor;
    /// @notice Current Interest Rate Model.
    DynamicInterestRateModel public interestRateModel;
    /// @notice Information corresponding to borrow exchange rate.
    MarketData public marketData;

    /// @notice The dToken balance of an account.
    /// @dev Account address => Account token balance.
    mapping(address => uint256) public balanceOf;
    /// @notice The allowance on token transfers a spender has for an account.
    /// @dev Account address => Spender address => Approved token amount.
    mapping(address => mapping(address => uint256)) public allowance;
    /// @notice Status of whether a spender has the ability to borrow
    ///         on behalf of an account.
    /// @dev Account address => Spender address => Can borrow on behalf.
    mapping(address => mapping(address => bool)) public isApprovedToBorrow;
    /// @notice Debt information associated with an account.
    /// @dev Account address => DebtData struct.
    mapping(address => DebtData) internal _debtOf;

    /// EVENTS ///

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event BorrowApproval(
        address indexed owner,
        address indexed spender,
        bool isApproved
    );
    event InterestAccrued(
        uint256 debtAccumulated,
        uint256 exchangeRate,
        uint256 totalBorrows
    );
    event Borrow(address account, uint256 amount);
    event Repay(address payer, address account, uint256 amount);
    event Liquidated(
        address liquidator,
        address account,
        uint256 amount,
        address cTokenCollateral,
        uint256 seizeTokens
    );
    event BadDebtRecognized(
        address liquidator,
        address account,
        uint256 amount
    );
    event NewMarketInterestRateModel(
        address oldInterestRateModel,
        address newInterestRateModel,
        uint256 newInterestCompoundRate
    );
    event NewInterestFactor(
        uint256 oldInterestFactor,
        uint256 newInterestFactor
    );
    /// ERRORS ///

    error DToken__Unauthorized();
    error DToken__ExcessiveValue();
    error DToken__TransferError();
    error DToken__InsufficientUnderlyingHeld();
    error DToken__ValidationFailed();
    error DToken__InvalidCentralRegistry();
    error DToken__UnderlyingAssetTotalSupplyExceedsMaximum();
    error DToken__MarketManagerIsNotLendingMarket();

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of Curvances Central Registry.
    /// @param underlying_ The address of the underlying asset
    ///                    for this dToken.
    /// @param marketManager_ The address of the MarketManager.
    /// @param interestRateModel_ The address of the interest rate model.
    constructor(
        ICentralRegistry centralRegistry_,
        address underlying_,
        address marketManager_,
        address interestRateModel_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert DToken__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        // Set the marketManager after consulting Central Registry.
        // Ensure that marketManager parameter is a marketManager.
        if (!centralRegistry.isMarketManager(marketManager_)) {
            revert DToken__MarketManagerIsNotLendingMarket();
        }

        // Set new marketManager.
        marketManager = IMarketManager(marketManager_);

        // Initialize timestamp and borrow index.
        marketData.lastTimestampUpdated = uint40(block.timestamp);
        marketData.exchangeRate = uint216(WAD);

        _setInterestRateModel(DynamicInterestRateModel(interestRateModel_));

        // Assign the interest factor for interest generated
        // inside this market.
        uint256 newInterestFactor = centralRegistry.protocolInterestFactor(
            marketManager_
        );
        interestFactor = newInterestFactor;

        emit NewInterestFactor(0, newInterestFactor);

        underlying = underlying_;
        name = string.concat(
            "Curvance interest bearing ",
            IERC20(underlying_).name()
        );
        symbol = string.concat("c", IERC20(underlying_).symbol());

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate, in `WAD`.
        if (IERC20(underlying).totalSupply() >= type(uint232).max) {
            revert DToken__UnderlyingAssetTotalSupplyExceedsMaximum();
        }
    }

    /// EXTERNAL FUNCTIONS ///

    //// @notice Starts a dToken market, executed via marketManager.
    /// @dev This initial mint is a failsafe against rounding exploits,
    ///      although, we protect against them in many ways,
    ///      better safe than sorry.
    /// @dev Emits a {Transfer} event.
    /// @param by The account initializing the dToken market.
    /// @return Returns with true when successful.
    function startMarket(address by) external nonReentrant returns (bool) {
        if (msg.sender != address(marketManager)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 amount = _BASE_UNDERLYING_RESERVE;
        SafeTransferLib.safeTransferFrom(
            underlying,
            by,
            address(this),
            amount
        );

        // We do not need to calculate exchange rate here,
        // `by` will always be the first depositor with totalSupply = 0.
        // Total Supply and contracy balance should always be 0 prior,
        // but we increment incase somehow invariants have been modified.
        totalSupply = totalSupply + amount;
        balanceOf[address(this)] = balanceOf[address(this)] + amount;

        emit Transfer(address(0), address(this), amount);
        return true;
    }

    /// @notice Transfers `amount` dTokens from caller to `to`.
    /// @param to The address to receive `amount` dTokens.
    /// @param tokens The number of dTokens to transfer.
    /// @return Returns true on success.
    function transfer(
        address to,
        uint256 tokens
    ) external nonReentrant returns (bool) {
        _transfer(msg.sender, msg.sender, to, tokens);
        return true;
    }

    /// @notice Transfers `amount` tokens from `from` to `to`.
    /// @param from The address of to transfer `amount` dTokens.
    /// @param to The address to receive `amount` dTokens.
    /// @param tokens The number of dTokens to transfer.
    /// @return Returns true on success.
    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) external nonReentrant returns (bool) {
        _transfer(msg.sender, from, to, tokens);
        return true;
    }

    /// @notice Borrows underlying tokens from lenders, based on collateral
    ///         posted inside this market.
    /// @dev Updates pending interest before executing the borrow.
    /// @param amount The amount of the underlying asset to borrow.
    function borrow(uint256 amount) external nonReentrant {
        // Update pending interest.
        accrueInterest();

        // Reverts if borrow not allowed.
        // Notifies the Market Manager that a user is taking on more debt,
        // and to pause user redemptions for 20 minutes.
        marketManager.canBorrowWithNotify(address(this), msg.sender, amount);

        _borrow(msg.sender, amount, msg.sender);
    }

    /// @notice Used by a delegated user to borrow underlying tokens
    ///         from lenders, based on collateral posted inside this market
    ///         by `account`.
    /// @dev Updates pending interest before executing the borrow.
    /// @param account The account who will have their assets borrowed against.
    /// @param recipient The account who will receive the borrowed assets.
    /// @param amount The amount of the underlying asset to borrow.
    function borrowFor(
        address account,
        address recipient,
        uint256 amount
    ) external nonReentrant {
        if (!isApprovedToBorrow[account][msg.sender]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Update pending interest.
        accrueInterest();

        // Reverts if borrow not allowed.
        // Notifies the Market Manager that a user is taking on more debt,
        // and to pause user redemptions for 20 minutes.
        // Note: Be careful who you approve here!
        // Not only can they take borrowed funds, but, they can delay
        // repayment through repeated notifications.
        marketManager.canBorrowWithNotify(address(this), account, amount);

        _borrow(account, amount, recipient);
    }

    /// @notice Used by the position folding contract to borrow underlying tokens
    ///         from lenders, based on collateral posted inside this market
    ///         by `account` to apply a complex action.
    /// @dev Only Position folding contract can call this function.
    ///      Updates pending interest before executing the borrow.
    /// @param account The account address to borrow on behalf of.
    /// @param amount The amount of the underlying asset to borrow.
    /// @param params Callback calldata to execute after borrow.
    function borrowForPositionFolding(
        address account,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != marketManager.positionFolding()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Update pending interest.
        accrueInterest();

        // Notifies the Market Manager that a user is taking on more debt,
        // and to pause user redemptions for 20 minutes.
        marketManager.notifyBorrow(address(this), account);

        _borrow(account, amount, msg.sender);

        // Callback to position folding to execute additional action.
        IPositionFolding(msg.sender).onBorrow(
            address(this),
            account,
            amount,
            params
        );

        // Fail if terminal position is not allowed with no additional
        // adjustment.
        marketManager.canBorrow(address(this), account, 0);
    }

    /// @notice Repays underlying tokens to lenders, freeing up their
    ///         collateral posted inside this market.
    /// @dev Updates interest before executing the repayment.
    /// @param amount The amount to repay, or 0 for the full outstanding amount.
    function repay(uint256 amount) external nonReentrant {
        // Update pending interest.
        accrueInterest();

        _repay(msg.sender, msg.sender, amount);
    }

    /// @notice Repays underlying tokens to lenders, on behalf of `account`,
    ///         freeing up their collateral posted inside this market.
    /// @dev Updates pending interest before executing the repay.
    /// @param account The account address to repay on behalf of.
    /// @param amount The amount to repay, or 0 for the full outstanding amount.
    function repayFor(address account, uint256 amount) external nonReentrant {
        // Update pending interest.
        accrueInterest();

        _repay(msg.sender, account, amount);
    }

    /// @notice Used by the market manager contract to repay a portion
    ///         of underlying token debt to lenders, remaining debt shortfall
    ///        is recognized equally by lenders due to `account` default.
    /// @dev Only market manager contract can call this function.
    ///      Updates pending interest prior to execution of the repay, 
    ///      inside the market manager contract.
    /// @param liquidator The account liquidating `account`'s collateral, 
    ///                   and repaying a portion of `account`'s debt.
    /// @param account The account being liquidated and repaid on behalf of.
    /// @param repayRatio The ratio of outstanding debt that `liquidator`
    ///                   will repay from `account`'s obligations,
    ///                   out of 100%, in `WAD`.
    function repayWithBadDebt(
        address liquidator,
        address account,
        uint256 repayRatio
    ) external nonReentrant {
        // We check self liquidation in marketManager before
        // this call, so we do not need to check here.

        // Make sure the marketManager itself is calling since
        // then we know all liquidity checks have passed.
        if (msg.sender != address(marketManager)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // We do not need to check for interest accrual here since its done
        // at the top of liquidateAccount, inside market manager contract,
        // that calls this function.

        // Cache account debt balance to save gas.
        uint256 accountDebt = debtBalanceCached(account);
        uint256 repayAmount = (accountDebt * repayRatio) / WAD;

        // We do not need to check for listing here as we are
        // coming directly from the marketManager itself,
        // so we know it is listed.

        // Process a partial repay directly by transferring underlying tokens
        // back to the dToken contract.
        SafeTransferLib.safeTransferFrom(
            underlying,
            liquidator,
            address(this),
            repayAmount
        );

        // Wipe out the accounts debt since we are recognizing
        // unpaid debt as bad debt.
        delete _debtOf[account].principal;
        totalBorrows -= accountDebt;

        emit Repay(liquidator, account, repayAmount);
        emit BadDebtRecognized(liquidator, account, accountDebt - repayAmount);
    }

    /// @notice Liquidates `account`'s collateral by repaying `amount` debt
    ///         and transferring the liquidated collateral to the liquidator.
    /// @dev Updates pending interest before executing the liquidation.
    /// @param account The address of the account to be liquidated.
    /// @param amount The amount of underlying asset the liquidator wishes to repay.
    /// @param collateralToken The market in which to seize collateral from `account`.
    function liquidateExact(
        address account,
        uint256 amount,
        IMToken collateralToken
    ) external nonReentrant {
        _liquidate(msg.sender, account, amount, collateralToken, true);
    }

    /// @notice Liquidates `account`'s as much collateral as possible by
    ///         repaying debt and transferring the liquidated collateral
    ///         to the liquidator.
    /// @dev Updates pending interest before executing the liquidation.
    /// @param account The address of the account to be liquidated.
    /// @param collateralToken The market in which to seize collateral from `account`.
    function liquidate(
        address account,
        IMToken collateralToken
    ) external nonReentrant {
        _liquidate(
            msg.sender,
            account,
            0, // Amount = 0 is passed since the max amount possible will be liquidated.
            collateralToken,
            false
        );
    }

    /// @notice Redeems dTokens in exchange for the underlying asset.
    /// @dev Updates pending interest before executing the redemption.
    /// @param tokens The number of dTokens to redeem for underlying tokens.
    function redeem(uint256 tokens) external nonReentrant {
        // Update pending interest.
        accrueInterest();

        // Validate that `tokens` can be redeemed and maintain collateral
        // requirements.
        marketManager.canRedeem(address(this), msg.sender, tokens);

        _redeem(
            msg.sender,
            msg.sender,
            tokens,
            (exchangeRateCached() * tokens) / WAD
        );
    }

    /// @notice Used by the position folding contract to redeem underlying tokens
    ///         from the market, on behalf of `account` to apply a complex action.
    /// @dev Only Position folding contract can call this function. 
    ///      Updates interest before executing the redemption. 
    ///      This function may seem weird at first since dTokens can not be
    ///      collateralized, but with this technology a user can redeem lent
    ///      assets and route them directly into collateral deposits in a
    ///      single transaction.
    /// @param account The account address to redeem dTokens on behalf of.
    /// @param amount The amount of the underlying asset to redeem.
    /// @param params Callback calldata to execute after redemption.
    function redeemUnderlyingForPositionFolding(
        address account,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != marketManager.positionFolding()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Update pending interest.
        accrueInterest();

        _redeem(
            account,
            msg.sender,
            (amount * WAD) / exchangeRateCached(),
            amount
        );

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            account,
            amount,
            params
        );

        // Fail if redeem not allowed, after position folding
        // has executed `account`'s extra actions.
        marketManager.canRedeem(address(this), account, 0);
    }

    /// @notice Deposits underlying assets into the market, 
    ///         and receives dTokens.
    /// @dev Updates pending interest before executing the mint inside
    ///      the internal helper function.
    /// @param amount The amount of the underlying assets to deposit.
    /// @return Returns true on success.
    function mint(uint256 amount) external nonReentrant returns (bool) {
        _mint(msg.sender, msg.sender, amount);
        return true;
    }

    /// @notice Deposits underlying assets into the market, 
    ///         and `recipient` receives dTokens.
    /// @dev Updates pending interest before executing the mint inside
    ///      the internal helper function.
    /// @param amount The amount of the underlying assets to deposit.
    /// @param recipient The account that should receive the dTokens.
    /// @return Returns true on success.
    function mintFor(
        uint256 amount,
        address recipient
    ) external nonReentrant returns (bool) {
        _mint(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Adds reserves by transferring from Curvance DAO
    ///         to the market and deposits into the gauge.
    /// @dev Updates pending interest before executing the reserve deposit.
    /// @param amount The amount of underlying tokens to add as reserves,
    ///               in assets.
    function depositReserves(uint256 amount) external nonReentrant {
        _checkDaoPermissions();

        // Update pending interest.
        accrueInterest();

        // Calculate asset -> shares exchange rate.
        uint256 tokens = (amount * WAD) / exchangeRateCached();

        // On success, the market will deposit `amount` to the market.
        SafeTransferLib.safeTransferFrom(
            underlying,
            msg.sender,
            address(this),
            amount
        );

        // Query current DAO operating address.
        address daoAddress = centralRegistry.daoAddress();

        // Deposit new reserves into gauge.
        _gaugePool().deposit(address(this), daoAddress, tokens);

        // Update reserves
        totalReserves = totalReserves + tokens;
    }

    /// @notice Reduces reserves by withdrawing from the gauge
    ///         and transfers them to Curvance DAO.
    /// @dev If daoAddress is going to be moved all reserves should be
    ///      withdrawn first. Updates pending interest before executing
    ///      the reserve withdrawal.
    /// @param amount Amount of reserves to withdraw, in assets.
    function withdrawReserves(uint256 amount) external nonReentrant {
        _checkDaoPermissions();

        // Update pending interest.
        accrueInterest();

        // Make sure we have enough underlying held to cover withdrawal.
        if (marketUnderlyingHeld() < amount) {
            revert DToken__InsufficientUnderlyingHeld();
        }

        // Convert `amount` assets to shares to match totalReserves
        // denomination.
        uint256 tokens = (amount * WAD) / exchangeRateCached();

        // Update reserves with underflow check.
        totalReserves = totalReserves - tokens;

        // Query current DAO operating address.
        address daoAddress = centralRegistry.daoAddress();

        // Withdraw reserves from gauge, in shares.
        _gaugePool().withdraw(address(this), daoAddress, tokens);
        // Transfer underlying to DAO, in assets.
        SafeTransferLib.safeTransfer(underlying, daoAddress, amount);
    }

    /// @notice Withdraws all reserves from the gauge and transfers them to
    ///         Curvance DAO.
    /// @dev If daoAddress is going to be moved all reserves should be
    ///      withdrawn first. Updates pending interest before executing
    ///      the reserve withdrawal.
    function processWithdrawReserves() external {
        // Only callable via the DAO Central Registry.
        if (msg.sender != address(centralRegistry)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Update pending interest.
        accrueInterest();

        uint256 totalReservesCached = totalReserves;
        uint256 amount = (totalReservesCached * exchangeRateCached()) / WAD;

        // Make sure we have enough underlying held to cover withdrawal.
        if (marketUnderlyingHeld() < amount) {
            revert DToken__InsufficientUnderlyingHeld();
        }

        // Update reserves to 0 and receive a gas refund.
        delete totalReserves;

        // Query current DAO operating address.
        address daoAddress = centralRegistry.daoAddress();
        // Withdraw reserves from gauge.
        _gaugePool().withdraw(address(this), daoAddress, totalReservesCached);

        // Transfer underlying to DAO measured in assets.
        SafeTransferLib.safeTransfer(underlying, daoAddress, amount);
    }

    /// @notice Sets `amount` as the allowance of `spender` over the
    ///         caller's tokens.
    /// @dev Emits an {Approval} event.
    /// @param spender The address that will be approved to spend `amount`
    ///                dTokens on behalf of the caller.
    /// @param tokens The amount of dTokens that should be approved
    ///               for spending by `spender`.
    /// @return Returns true on success.
    function approve(address spender, uint256 tokens) external returns (bool) {
        allowance[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    /// @notice Approves or restricts `spender`'s authority to borrow
    //          on the caller's behalf.
    /// @dev Emits a {BorrowApproval} event.
    /// @param spender The address that will be approved or restricted
    ///                from borrowing on behalf of the caller.
    /// @param isApproved Whether `spender` is being approved or restricted
    ///                   of authority to borrow on behalf of caller.
    /// @return Returns true on success.
    function setBorrowApproval(
        address spender,
        bool isApproved
    ) external returns (bool) {
        isApprovedToBorrow[msg.sender][spender] = isApproved;

        emit BorrowApproval(msg.sender, spender, isApproved);
        return true;
    }

    /// Admin Functions

    /// @notice Rescue any token sent by mistake.
    /// @dev Restricts the ability to rescue underlying tokens inside the
    ///      market since Curvance is non-custodial.
    /// @param token The token to rescue.
    /// @param amount The amount of `token` to rescue, 0 indicates to
    ///               rescue all.
    function rescueToken(address token, uint256 amount) external {
        _checkDaoPermissions();
        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (amount == 0) {
                amount = address(this).balance;
            }

            SafeTransferLib.forceSafeTransferETH(daoOperator, amount);
        } else {
            if (token == underlying) {
                revert DToken__TransferError();
            }

            if (amount == 0) {
                amount = IERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// @notice Accrues pending interest and updates the interest rate model.
    /// @dev Admin function to update the interest rate model.
    /// @param newInterestRateModel The new interest rate model for this
    ///                             dToken to use.
    function setInterestRateModel(address newInterestRateModel) external {
        _checkElevatedPermissions();

        // Update pending interest.
        accrueInterest();

        _setInterestRateModel(DynamicInterestRateModel(newInterestRateModel));
    }

    /// @notice Accrues pending interest and updates the interest factor.
    /// @dev Admin function to update the interest factor value.
    /// @param newInterestFactor The new interest factor for this
    ///                          dToken to use.
    function setInterestFactor(uint256 newInterestFactor) external {
        _checkElevatedPermissions();

        // Update pending interest.
        accrueInterest();

        _setInterestFactor(newInterestFactor);
    }

    /// @notice Updates pending interest and returns the up-to-date balance
    ///         of `account`, in underlying assets, safely.
    /// @param account The account address to have their balance measured.
    /// @return The amount of underlying owned by `account`.
    function balanceOfUnderlyingSafe(address account) external returns (uint256) {
        return ((exchangeRateWithUpdateSafe() * balanceOf[account]) / WAD);
    }

    /// @notice Get a snapshot of the account's balances, and the cached
    ///         exchange rate.
    /// @dev This is used by marketManager to more efficiently perform
    ///      liquidity checks.
    /// @param account The address of the account to snapshot.
    /// @return Account token balance.
    /// @return Account debt balance.
    /// @return Token => Underlying exchange rate, in `WAD`.
    function getSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return (
            balanceOf[account],
            debtBalanceCached(account),
            exchangeRateCached()
        );
    }

    /// @notice Get a snapshot of the dToken and `account` data.
    /// @dev Used by marketManager to more efficiently perform
    ///      liquidity checks.
    ///      NOTE: Exchange Rate returns 0 to save gas in marketManager
    ///            since its unused.
    /// @param account The address of the account to snapshot.
    /// @return The account snapshot of `account`.
    function getSnapshotPacked(
        address account
    ) external view returns (AccountSnapshot memory) {
        return (
            AccountSnapshot({
                asset: address(this),
                isCToken: false,
                decimals: decimals(),
                debtBalance: debtBalanceCached(account),
                exchangeRate: 0 // Unused in marketManager.
            })
        );
    }

    /// @notice Calculates the current dToken utilization rate.
    /// @dev Used for third party integrations, and frontends.
    /// @return The utilization rate, in `WAD`.
    function utilizationRate() external view returns (uint256) {
        return
            interestRateModel.utilizationRate(
                marketUnderlyingHeld(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current dToken borrow interest rate per year.
    /// @dev Used for third party integrations, and frontends.
    /// @return The borrow interest rate per year, in `WAD`.
    function borrowRatePerYear() external view returns (uint256) {
        return
            interestRateModel.getBorrowRatePerYear(
                marketUnderlyingHeld(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns predicted upcoming dToken borrow interest rate
    ///         per year.
    /// @dev Used for third party integrations, and frontends.
    /// @return The predicted borrow interest rate per year, in `WAD`.
    function predictedBorrowRatePerYear() external view returns (uint256) {
        return
            interestRateModel.getPredictedBorrowRatePerYear(
                marketUnderlyingHeld(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current dToken supply interest rate per year.
    /// @dev Used for third party integrations, and frontends.
    /// @return The supply interest rate per year, in `WAD`.
    function supplyRatePerYear() external view returns (uint256) {
        return
            interestRateModel.getSupplyRatePerYear(
                marketUnderlyingHeld(),
                totalBorrows,
                totalReserves,
                interestFactor
            );
    }

    /// @notice Updates pending interest and then returns the current
    ///         total borrows, safely.
    /// @dev Used for third party integrations.
    /// @return Total borrows underlying token, with pending interest applied.
    function totalBorrowsWithUpdateSafe() external nonReentrant returns (uint256) {
        // Update pending interest.
        accrueInterest();

        return totalBorrows;
    }

    /// @notice Updates pending interest and returns the current debt balance
    ///         for `account`, safely.
    /// @param account The address whose balance should be calculated.
    /// @return The current balance index of `account`, with pending interest
    ///         applied.
    function debtBalanceWithUpdateSafe(
        address account
    ) external nonReentrant returns (uint256) {
        // Update pending interest.
        accrueInterest();

        return debtBalanceCached(account);
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Returns the current debt balance for `account`.
    /// @dev Note: Pending interest is not applied in this calculation.
    /// @param account The address whose balance should be calculated.
    /// @return The current balance index of `account`.
    function debtBalanceCached(address account) public view returns (uint256) {
        // Cache borrow data to save gas.
        DebtData storage userDebtData = _debtOf[account];

        // If debtBalance = 0, then borrowIndex is also 0.
        if (userDebtData.principal == 0) {
            return 0;
        }

        // Calculate debt balance using the interest index:
        // debtBalanceCached calculation:
        // ((Account's principal * DToken's exchange rate) / 
        // Account's exchange rate).
        return
            (userDebtData.principal * marketData.exchangeRate) /
            userDebtData.accountExchangeRate;
    }

    /// @notice Returns the decimals of the dToken.
    /// @dev We pull directly from underlying incase its a proxy contract,
    ///      and changes decimals on us.
    /// @return The number of decimals for this dToken, 
    ///         matching the underlying token.
    function decimals() public view returns (uint8) {
        return IERC20(underlying).decimals();
    }

    /// @notice Gets balance of this contract, in terms of the underlying.
    /// @dev This excludes changes in underlying token balance by the
    ///      current transaction, if any.
    /// @return The quantity of underlying tokens held by the market.
    function marketUnderlyingHeld() public view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /// @notice Returns the type of Curvance token.
    /// @dev true = Collateral token; false = Debt token.
    /// @return Whether this token is a cToken or not.
    function isCToken() public pure returns (bool) {
        return false;
    }

    /// @notice Updates pending interest and returns the up-to-date exchange
    ///         rate from the underlying to the dToken, safely.
    /// @return Calculated exchange rate, in `WAD`.
    function exchangeRateWithUpdateSafe() public nonReentrant returns (uint256) {
        // Update pending interest.
        accrueInterest();
        return exchangeRateCached();
    }

    /// @notice Returns the up-to-date exchange rate from the underlying
    ///         to the dToken.
    /// @return Cached exchange rate, in `WAD`.
    function exchangeRateCached() public view returns (uint256) {
        // We do not need to check for totalSupply = 0, because, 
        // when we list a market we mint `_BASE_UNDERLYING_RESERVE` initially.
        // exchangeRate calculation:
        // (Underlying Held + Total Borrows - Total Reserves) / Total Supply.
        return
            ((marketUnderlyingHeld() + totalBorrows - totalReserves) * WAD) /
            totalSupply;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IMToken).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Applies pending interest to all holders, updating
    ///         `totalBorrows` and `totalReserves`.
    /// @dev This calculates interest accrued from the last checkpoint
    ///      up to the latest available checkpoint, if `compoundRate`
    ///      seconds has passed.
    ///      Emits a {InterestAccrued} event.
    function accrueInterest() public {
        // Cache current exchange rate data.
        MarketData memory cachedData = marketData;

        // If we are up to date there is no reason to continue.
        if (
            cachedData.lastTimestampUpdated + cachedData.compoundRate >
            block.timestamp
        ) {
            return;
        }

        // Cache current values to save gas.
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 exchangeRatePrior = cachedData.exchangeRate;

        // Calculate the current borrow interest rate.
        uint256 borrowRate = interestRateModel.getBorrowRateWithUpdate(
            marketUnderlyingHeld(),
            borrowsPrior,
            reservesPrior
        );

        // Calculate the interest compound cycles to update,
        // in `interestCompounds`.
        uint256 interestCompounds = (block.timestamp -
            cachedData.lastTimestampUpdated) / cachedData.compoundRate;
        // Calculate the interest and debt accumulated.
        uint256 interestAccumulated = borrowRate * interestCompounds;
        uint256 debtAccumulated = (interestAccumulated * borrowsPrior) / WAD;
        // Calculate new borrows, and the new exchange rate, based on
        // accumulation values above.
        uint256 totalBorrowsNew = debtAccumulated + borrowsPrior;
        uint256 exchangeRateNew = ((interestAccumulated * exchangeRatePrior) /
            WAD) + exchangeRatePrior;

        // Update update timestamp, exchange rate, and total outstanding
        // borrows.
        marketData.lastTimestampUpdated = uint40(
            cachedData.lastTimestampUpdated +
                (interestCompounds * cachedData.compoundRate)
        );
        marketData.exchangeRate = uint216(exchangeRateNew);
        totalBorrows = totalBorrowsNew;

        // Check whether the DAO takes a cut of interest, and whether new debt
        // has accumulated (!= 0). Then update reserves if necessary.
        uint256 newReserves = ((interestFactor * debtAccumulated) / WAD);
        if (newReserves > 0) {
            totalReserves = newReserves + reservesPrior;

            // Update gauge pool values for new reserves.
            _gaugePool().deposit(
                address(this),
                centralRegistry.daoAddress(),
                newReserves
            );
        }

        emit InterestAccrued(
            debtAccumulated,
            exchangeRateNew,
            totalBorrowsNew
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Updates the interest rate model.
    /// @dev Emits a {NewMarketInterestRateModel} event.
    /// @param newInterestRateModel The new interest rate model for this
    ///                             dToken to use.
    function _setInterestRateModel(
        DynamicInterestRateModel newInterestRateModel
    ) internal {
        // Ensure we are switching to an actual Interest Rate Model.
        newInterestRateModel.IS_INTEREST_RATE_MODEL();

        // Cache the current interest rate model to save gas.
        address oldInterestRateModel = address(interestRateModel);

        // Set new interest rate model and compound rate.
        interestRateModel = newInterestRateModel;
        marketData.compoundRate = newInterestRateModel.compoundRate();

        emit NewMarketInterestRateModel(
            oldInterestRateModel,
            address(newInterestRateModel),
            marketData.compoundRate
        );
    }

    /// @notice Updates the interest factor.
    /// @dev Emits a {NewInterestFactor} event.
    /// @param newInterestFactor The new interest factor for this
    ///                          dToken to use.
    function _setInterestFactor(uint256 newInterestFactor) internal {
        // The DAO cannot take more than 50% of interest collected.
        if (newInterestFactor > 5000) {
            revert DToken__ExcessiveValue();
        }

        // Cache the other interest factor for event emission.
        uint256 oldInterestFactor = interestFactor;

        /// The Interest Rate Factor should be stored is in `WAD` format.
        /// So, we need to multiply by 1e14 to convert from basis points
        /// to `WAD`.
        interestFactor = newInterestFactor * 1e14;

        emit NewInterestFactor(oldInterestFactor, newInterestFactor);
    }

    /// @notice Transfers `tokens` tokens from `from` to `to`, executed by
    ///         `spender`.
    /// @dev Emits a {Transfer} event.
    /// @param spender The address of the account executing the transfer.
    /// @param from The address of to transfer `amount` dTokens.
    /// @param to The address to receive `amount` dTokens.
    /// @param tokens The number of tokens to transfer.
    function _transfer(
        address spender,
        address from,
        address to,
        uint256 tokens
    ) internal {
        // Do not allow self-transfers.
        if (from == to) {
            revert DToken__TransferError();
        }

        // Fails if transfer not allowed.
        marketManager.canTransfer(address(this), from, tokens);

        // Get the allowance, if the spender is not the `from` address.
        if (spender != from) {
            // Validate that spender has enough allowance
            // for the transfer with underflow check.
            allowance[from][spender] = allowance[from][spender] - tokens;
        }

        // Update account token balances.
        balanceOf[from] = balanceOf[from] - tokens;
        // We know that from balance wont overflow
        // due to underflow check above.
        unchecked {
            balanceOf[to] = balanceOf[to] + tokens;
        }

        // Cache gaugePool, then update gauge pool values for `from` and `to`.
        GaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), from, tokens);
        gaugePool.deposit(address(this), to, tokens);

        // We emit a Transfer event.
        emit Transfer(from, to, tokens);
    }

    /// @notice Mints dTokens to `recipient`, based on the deposit of
    ///         underlying assets into the market by `minter`.
    /// @dev Updates pending interest before executing the mint.
    ///      Emits a {Transfer} event.
    /// @param minter The address of the account which is supplying the assets.
    /// @param recipient The address of the account which will receive dToken.
    /// @param amount The amount of the underlying asset to supply.
    function _mint(
        address minter,
        address recipient,
        uint256 amount
    ) internal {
        // Update pending interest.
        accrueInterest();

        // Fail if mint not allowed.
        marketManager.canMint(address(this));

        // Get exchange rate before mint.
        uint256 er = exchangeRateCached();

        // Transfer underlying into the dToken contract.
        SafeTransferLib.safeTransferFrom(
            underlying,
            minter,
            address(this),
            amount
        );

        // Calculate dTokens to be minted.
        uint256 tokens = (amount * WAD) / er;

        // Update totalSupply, and recipient balance.
        unchecked {
            totalSupply = totalSupply + tokens;
            /// Calculate their new balance.
            balanceOf[recipient] = balanceOf[recipient] + tokens;
        }

        // Update gauge pool values for `recipient`.
        _gaugePool().deposit(address(this), recipient, tokens);

        emit Transfer(address(0), recipient, tokens);
    }

    /// @notice Redeems dTokens, in exchange for the underlying asset.
    /// @dev Emits a {Transfer} event.
    /// @param account The address of the account which is redeeming the dTokens.
    /// @param recipient The address of the account which will receive the
    ///                  underlying tokens.
    /// @param tokens The number of dTokens to redeem for underlying tokens.
    /// @param amount The number of underlying tokens to distribute to `recipient`.
    function _redeem(
        address account,
        address recipient,
        uint256 tokens,
        uint256 amount
    ) internal {
        // Check if we have enough underlying held to support the redemption.
        // We do not need to add _BASE_UNDERLYING_RESERVE to the calculation
        // because the startMarket() assets can never be withdraw since the
        // market itself owns the corresponding dTokens.
        if (marketUnderlyingHeld() < amount) {
            revert DToken__InsufficientUnderlyingHeld();
        }

        // Update account balance and totalSupply.
        balanceOf[account] = balanceOf[account] - tokens;
        // We have account underflow check above so we do not need
        // a redundant check here.
        unchecked {
            totalSupply = totalSupply - tokens;
        }

        // Update gauge pool values for `account`, while also checking
        // if tokens == 0, causing reversion.
        _gaugePool().withdraw(address(this), account, tokens);

        // Transfer underlying to `recipient`.
        SafeTransferLib.safeTransfer(underlying, recipient, amount);

        emit Transfer(account, address(0), tokens);
    }

    /// @notice Executes borrowing of assets for `account` from lenders.
    /// @dev Emits a {Borrow} event.
    /// @param account The account borrowing assets.
    /// @param amount The amount of the underlying asset to borrow.
    /// @param recipient The account receiving the borrowed assets.
    function _borrow(
        address account,
        uint256 amount,
        address recipient
    ) internal {
        // Check if we have enough underlying held to support the borrow.
        // We add _BASE_UNDERLYING_RESERVE to the calculation to ensure that
        // the market never actually runs out of assets and may introduce
        // invariant manipulation. 
        if (
            marketUnderlyingHeld() - totalReserves <
            amount + _BASE_UNDERLYING_RESERVE
            ) {
            revert DToken__InsufficientUnderlyingHeld();
        }

        // Update account and total borrow balances, failing on overflow.
        _debtOf[account].principal = debtBalanceCached(account) + amount;
        _debtOf[account].accountExchangeRate = marketData.exchangeRate;
        totalBorrows = totalBorrows + amount;

        // Transfer underlying to `recipient`.
        SafeTransferLib.safeTransfer(underlying, recipient, amount);

        emit Borrow(account, amount);
    }

    /// @notice Repays an outstanding loan of `account` through repayment
    ///         by `payer`, who usually is themselves.
    /// @dev Emits a {Repay} event.
    /// @param payer The address paying down the account debt.
    /// @param account The account with the debt being paid down.
    /// @param amount The amount the payer wishes to repay,
    ///               or 0 for the full outstanding amount.
    /// @return The amount of underlying token debt repaid for `account`.
    function _repay(
        address payer,
        address account,
        uint256 amount
    ) internal returns (uint256) {
        // Validate that the payer is allowed to repay the loan.
        marketManager.canRepay(address(this), account);

        // Cache how much the account has to save gas.
        uint256 accountDebt = debtBalanceCached(account);

        // Validate repayment amount is not excessive.
        if (amount > accountDebt) {
            revert DToken__ExcessiveValue();
        }

        // If amount == 0, repay max; amount = accountDebt.
        amount = amount == 0 ? accountDebt : amount;

        SafeTransferLib.safeTransferFrom(
            underlying,
            payer,
            address(this),
            amount
        );

        // We calculate the new account and total borrow balances,
        // we check that amount is <= accountDebt so we can skip
        // underflow check here.
        unchecked {
            _debtOf[account].principal = accountDebt - amount;
        }
        _debtOf[account].accountExchangeRate = marketData.exchangeRate;
        totalBorrows -= amount;

        emit Repay(payer, account, amount);
        return amount;
    }

    /// @notice The liquidator liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @dev Emits {Repay} and {Liquidated} events.
    /// @param liquidator The address repaying the borrow and seizing collateral.
    /// @param account The account of this dToken to be liquidated.
    /// @param amount The amount of the underlying borrowed asset to repay.
    /// @param collateralToken The market in which to seize collateral from
    ///                        the account.
    /// @param exactAmount Whether a specific amount of debt token assets
    ///                    should be liquidated inputting false will attempt
    ///                    to liquidate the maximum amount possible.
    function _liquidate(
        address liquidator,
        address account,
        uint256 amount,
        IMToken collateralToken,
        bool exactAmount
    ) internal {
        // Update pending interest.
        accrueInterest();

        // Fail if account = liquidator.
        assembly {
            if eq(account, caller()) {
                // revert with DToken__Unauthorized().
                mstore(0x00, 0xefeae624)
                revert(0x1c, 0x04)
            }
        }

        // The MToken must be a collateral token.
        if (!collateralToken.isCToken()) {
            revert DToken__ValidationFailed();
        }

        uint256 liquidatedTokens;
        uint256 protocolTokens;

        // Fail if liquidate not allowed,
        // trying to pay too much debt with excessive `amount` will revert.
        (amount, liquidatedTokens, protocolTokens) = marketManager
            .canLiquidateWithExecution(
                address(this),
                address(collateralToken),
                account,
                amount,
                exactAmount
            );

        // Validate that the token is listed inside the market.
        if (!marketManager.isListed(address(this))) {
            revert DToken__ValidationFailed();
        }

        // Cache how much the account has to save gas.
        uint256 accountDebt = debtBalanceCached(account);

        // Repay `account`'s debt.
        SafeTransferLib.safeTransferFrom(
            underlying,
            liquidator,
            address(this),
            amount
        );

        // We calculate the new `account` and total borrow balances,
        // failing on underflow.
        _debtOf[account].principal = accountDebt - amount;
        _debtOf[account].accountExchangeRate = marketData.exchangeRate;
        totalBorrows -= amount;

        emit Repay(liquidator, account, amount);

        // We check above that the mToken must be a collateral token,
        // so we cant seize this mToken as it is a debt token,
        // so there is no reEntry risk.
        collateralToken.seize(
            liquidator,
            account,
            liquidatedTokens,
            protocolTokens
        );

        emit Liquidated(
            liquidator,
            account,
            amount,
            address(collateralToken),
            liquidatedTokens
        );
    }

    /// @notice Returns the gauge pool contract address.
    /// @return The gauge controller contract address, in `IGaugePool` form.
    function _gaugePool() internal view returns (GaugePool) {
        return marketManager.gaugePool();
    }

    /// @dev Helper function for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
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
}
