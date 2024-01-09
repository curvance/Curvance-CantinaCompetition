// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DynamicInterestRateModel } from "contracts/market/interestRates/DynamicInterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import { WAD } from "contracts/libraries/Constants.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { ReentrancyGuard } from "contracts/libraries/external/ReentrancyGuard.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance's Debt Token Contract.
contract DToken is ERC165, ReentrancyGuard {
    /// TYPES ///

    struct DebtData {
        /// @notice principal total balance (with accrued interest).
        uint256 principal;
        /// @notice current exchange rate for account.
        uint256 accountExchangeRate;
    }

    struct MarketData {
        /// @notice Timestamp interest was last update.
        uint32 lastTimestampUpdated;
        /// @notice Borrow exchange rate at `lastTimestampUpdated`.
        uint224 exchangeRate;
        /// @notice Rate at which interest compounds, in seconds.
        uint256 compoundRate;
    }

    /// CONSTANTS ///

    /// @notice underlying asset for the DToken.
    address public immutable underlying;
    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Lending Market controller.
    ILendtroller public immutable lendtroller;
    /// `bytes4(keccak256(bytes("DToken__Unauthorized()")))`.
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xef419be2;

    /// STORAGE ///

    /// @notice token name metadata.
    string public name;
    /// @notice token symbol metadata.
    string public symbol;
    /// @notice Current Interest Rate Model.
    DynamicInterestRateModel public interestRateModel;
    /// @notice Information corresponding to borrow exchange rate.
    MarketData public marketData;
    /// @notice Total number of tokens in circulation.
    uint256 public totalSupply;
    /// @notice Total outstanding borrows of underlying.
    uint256 public totalBorrows;
    /// @notice Total protocol reserves of underlying.
    uint256 public totalReserves;
    /// @notice Interest rate reserve factor.
    uint256 public interestFactor;

    /// @notice account => token balance.
    mapping(address => uint256) public balanceOf;
    /// @notice account => spender => approved amount.
    mapping(address => mapping(address => uint256)) public allowance;
    /// @notice account => spender => can borrow on behalf.
    mapping(address => mapping(address => bool)) public isApprovedToBorrow;
    /// @notice account => DebtData (Principal Borrowed, Cached Account Exchange Rate).
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
    error DToken__LendtrollerIsNotLendingMarket();

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of Curvances Central Registry.
    /// @param underlying_ The address of the underlying asset.
    /// @param lendtroller_ The address of the Lendtroller.
    /// @param interestRateModel_ The address of the interest rate model.
    constructor(
        ICentralRegistry centralRegistry_,
        address underlying_,
        address lendtroller_,
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

        // Set the lendtroller after consulting Central Registry.
        // Ensure that lendtroller parameter is a lendtroller.
        if (!centralRegistry.isLendingMarket(lendtroller_)) {
            revert DToken__LendtrollerIsNotLendingMarket();
        }

        // Set new lendtroller.
        lendtroller = ILendtroller(lendtroller_);

        // Initialize timestamp and borrow index.
        marketData.lastTimestampUpdated = uint32(block.timestamp);
        marketData.exchangeRate = uint224(WAD);

        _setInterestRateModel(DynamicInterestRateModel(interestRateModel_));

        uint256 newInterestFactor = centralRegistry.protocolInterestFactor(
            lendtroller_
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

    /// @notice Used to start a DToken market, executed via lendtroller.
    /// @dev This initial mint is a failsafe against rounding exploits,
    ///      although, we protect against them in many ways,
    ///      better safe than sorry.
    /// @param by The account initializing the market.
    function startMarket(address by) external nonReentrant returns (bool) {
        if (msg.sender != address(lendtroller)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 amount = 42069;
        SafeTransferLib.safeTransferFrom(
            underlying,
            by,
            address(this),
            amount
        );

        // We do not need to calculate exchange rate here,
        // `by` will always be the first depositor with totalSupply = 0.
        // These values should always be zero but we will add them just incase.
        totalSupply = totalSupply + amount;
        balanceOf[address(this)] = balanceOf[address(this)] + amount;

        emit Transfer(address(0), address(this), amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `msg.sender` to `to`.
    /// @param to The address of the destination account.
    /// @param amount The number of tokens to transfer.
    /// @return Whether or not the transfer succeeded.
    function transfer(
        address to,
        uint256 amount
    ) external nonReentrant returns (bool) {
        _transfer(msg.sender, msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `from` to `to`.
    /// @param from The address of the source account.
    /// @param to The address of the destination account.
    /// @param amount The number of tokens to transfer.
    /// @return bool true = success.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external nonReentrant returns (bool) {
        _transfer(msg.sender, from, to, amount);
        return true;
    }

    /// @notice Allows a account to borrow assets from the protocol.
    /// @dev    Updates interest before executing the borrow.
    /// @param amount The amount of the underlying asset to borrow.
    function borrow(uint256 amount) external nonReentrant {
        accrueInterest();

        // Reverts if borrow not allowed.
        lendtroller.canBorrowWithNotify(address(this), msg.sender, amount);

        _borrow(msg.sender, amount, msg.sender);
    }

    /// @notice Allows a account to borrow assets from the protocol
    ///         on behalf of someone else.
    /// @dev    Updates interest before executing the borrow.
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

        accrueInterest();

        // Reverts if borrow not allowed.
        // Note: Be careful who you approve here!
        // Not only can they take borrowed funds,
        // but they can delay repayment through notify.
        lendtroller.canBorrowWithNotify(address(this), account, amount);

        _borrow(account, amount, recipient);
    }

    /// @notice Position folding borrows from the protocol for `account`.
    /// @dev Only Position folding contract can call this function,
    ///      updates interest before executing the borrow.
    /// @param account The account address.
    /// @param amount The amount of the underlying asset to borrow.
    function borrowForPositionFolding(
        address account,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        accrueInterest();
        // Record that the account borrowed before everything else is updated.
        lendtroller.notifyBorrow(address(this), account);

        _borrow(account, amount, msg.sender);

        IPositionFolding(msg.sender).onBorrow(
            address(this),
            account,
            amount,
            params
        );

        // Fail if position is not allowed,
        // after position folding has re-invested.
        lendtroller.canBorrow(address(this), account, 0);
    }

    /// @notice Caller repays their own debt.
    /// @dev    Updates interest before executing the repayment.
    /// @param amount The amount to repay, or 0 for the full outstanding amount.
    function repay(uint256 amount) external nonReentrant {
        accrueInterest();

        _repay(msg.sender, msg.sender, amount);
    }

    /// @notice Position folding repays `account`'s debt.
    /// @dev Only Position folding contract can call this function,
    ///      updates interest before executing the repay.
    /// @param amount The amount to repay, or 0 for the full outstanding amount.
    function repayFor(address account, uint256 amount) external nonReentrant {
        accrueInterest();

        _repay(msg.sender, account, amount);
    }

    function repayWithBadDebt(
        address liquidator,
        address account,
        uint256 repayRatio
    ) external nonReentrant {
        // We check self liquidation in lendtroller before
        // this call, so we do not need to check here.

        // Make sure the lendtroller itself is calling since
        // then we know all liquidity checks have passed.
        if (msg.sender != address(lendtroller)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // We do not need to check for interest accrual here since its done
        // at the top of liquidateAccount that calls this function.

        // Cache how much the account has to save gas.
        uint256 accountDebt = debtBalanceCached(account);
        uint256 repayAmount = (accountDebt * repayRatio) / WAD;

        // We do not need to check for listing here as we are
        // coming directly from the lendtroller itself.

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
    /// @dev    Updates interest before executing the liquidation.
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
    /// @dev    Updates interest before executing the liquidation.
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

    /// @notice Sender redeems dTokens in exchange for the underlying asset.
    /// @dev    Updates interest before executing the redemption.
    /// @param amount The number of dTokens to redeem into underlying.
    function redeem(uint256 amount) external nonReentrant {
        accrueInterest();

        lendtroller.canRedeem(address(this), msg.sender, amount);

        _redeem(
            msg.sender,
            msg.sender,
            amount,
            (exchangeRateCached() * amount) / WAD
        );
    }

    /// @notice Helper function for Position Folding contract to redeem underlying tokens.
    /// @dev    Updates interest before executing the redemption.
    /// @param account The account address.
    /// @param underlyingAmount The amount of the underlying asset to redeem.
    function redeemUnderlyingForPositionFolding(
        address account,
        uint256 underlyingAmount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        accrueInterest();

        _redeem(
            account,
            msg.sender,
            (underlyingAmount * WAD) / exchangeRateCached(),
            underlyingAmount
        );

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            account,
            underlyingAmount,
            params
        );

        // Fail if redeem not allowed, position folding has re-invested.
        lendtroller.canRedeem(address(this), account, 0);
    }

    /// @notice Sender supplies assets into the market and receives dTokens.
    /// @dev    Updates interest before executing the mint.
    /// @param amount The amount of the underlying asset to supply.
    /// @return bool true = successful mint.
    function mint(uint256 amount) external nonReentrant returns (bool) {
        _mint(msg.sender, msg.sender, amount);
        return true;
    }

    /// @notice Sender supplies assets into the market and `recipient`
    ///         receives dTokens.
    /// @dev    Updates interest before executing the mint.
    /// @param recipient The recipient address.
    /// @param amount The amount of the underlying asset to supply.
    /// @return bool true = successful mint.
    function mintFor(
        uint256 amount,
        address recipient
    ) external nonReentrant returns (bool) {
        _mint(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Adds reserves by transferring from Curvance DAO
    ///         to the market and depositing to the gauge.
    /// @dev    Updates interest before executing the reserve deposit.
    /// @param amount The amount of underlying token to add as reserves, 
    ///               in assets.
    function depositReserves(uint256 amount) external nonReentrant {
        _checkDaoPermissions();

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
    ///         and transferring to Curvance DAO.
    /// @dev If daoAddress is going to be moved all reserves should be
    ///      withdrawn first, updates interest before executing the reserve
    ///      withdrawal.
    /// @param amount Amount of reserves to withdraw, in assets.
    function withdrawReserves(uint256 amount) external nonReentrant {
        _checkDaoPermissions();

        accrueInterest();

        // Make sure we have enough underlying held to cover withdrawal.
        if (marketUnderlyingHeld() < amount) {
            revert DToken__InsufficientUnderlyingHeld();
        }

        uint256 tokens = (amount * WAD) / exchangeRateCached();

        // Update reserves with underflow check.
        totalReserves = totalReserves - tokens;

        // Query current DAO operating address.
        address daoAddress = centralRegistry.daoAddress();
        // Withdraw reserves from gauge.
        _gaugePool().withdraw(address(this), daoAddress, tokens);

        // Transfer underlying to DAO measured in assets.
        SafeTransferLib.safeTransfer(underlying, daoAddress, amount);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// Emits an {Approval} event.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @dev Approve or restricts `spender`'s authority to borrow
    //       on the caller's behalf.
    /// Emits a {BorrowApproval} event.
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
    /// @param token token to rescue.
    /// @param amount amount of `token` to rescue, 0 indicates to rescue all.
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

    /// @notice Accrues interest and updates the interest rate model.
    /// @dev Admin function to update the interest rate model.
    /// @param newInterestRateModel the new interest rate model to use.
    function setInterestRateModel(address newInterestRateModel) external {
        _checkElevatedPermissions();
        accrueInterest();

        _setInterestRateModel(DynamicInterestRateModel(newInterestRateModel));
    }

    /// @notice Accrues interest and updates the interest factor.
    /// @dev Admin function to update the interest factor value.
    /// @param newInterestFactor the new interest factor to use.
    function setInterestFactor(uint256 newInterestFactor) external {
        _checkElevatedPermissions();
        accrueInterest();

        _setInterestFactor(newInterestFactor);
    }

    /// @notice Get the underlying balance of the `account`.
    /// @dev    Updates interest before returning the value.
    /// @param account The address of the account to query.
    /// @return The amount of underlying owned by `account`.
    function balanceOfUnderlying(address account) external returns (uint256) {
        return ((exchangeRateWithUpdate() * balanceOf[account]) / WAD);
    }

    /// @notice Get a snapshot of the account's balances, and the cached exchange rate.
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks.
    /// @param account Address of the account to snapshot.
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
    /// @dev This is used by lendtroller to more efficiently perform
    ///      liquidity checks.
    ///      NOTE: Exchange Rate returns 0 to save gas in lendtroller
    ///            since its unused.
    /// @param account Address of the account to snapshot.
    function getSnapshotPacked(
        address account
    ) external view returns (AccountSnapshot memory) {
        return (
            AccountSnapshot({
                asset: address(this),
                isCToken: false,
                decimals: decimals(),
                debtBalance: debtBalanceCached(account),
                exchangeRate: 0 // Unused in lendtroller.
            })
        );
    }

    /// @notice Calculates the current dToken utilization rate.
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
    /// @return The borrow interest rate per year, in `WAD`.
    function borrowRatePerYear() external view returns (uint256) {
        return
            interestRateModel.getBorrowRatePerYear(
                marketUnderlyingHeld(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current dToken supply interest rate per year.
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

    /// @notice Accrues interest and then returns the current total borrows.
    /// @return The total borrows with interest.
    function totalBorrowsWithUpdate() external nonReentrant returns (uint256) {
        accrueInterest();
        return totalBorrows;
    }

    /// @notice Accrues interest and returns the current debt balance
    ///         for `account`.
    /// @param account The address whose balance should be calculated
    ///                after updating borrowIndex.
    /// @return `account`'s current balance index.
    function debtBalanceWithUpdate(
        address account
    ) external nonReentrant returns (uint256) {
        accrueInterest();
        return debtBalanceCached(account);
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Return the debt balance of account based on stored data.
    /// @param account The address whose balance should be calculated.
    /// @return `account`'s cached balance index.
    function debtBalanceCached(address account) public view returns (uint256) {
        // Cache borrow data to save gas
        DebtData storage userDebtData = _debtOf[account];

        // If debtBalance = 0 then borrowIndex is likely also 0.
        if (userDebtData.principal == 0) {
            return 0;
        }

        // Calculate debt balance using the interest index:
        // debtBalanceCached calculation:
        // (account.principal * DToken.borrowIndex) / account.accountExchangeRate.
        return
            (userDebtData.principal * marketData.exchangeRate) /
            userDebtData.accountExchangeRate;
    }

    /// @notice Returns the decimals of the token.
    /// @dev We pull directly from underlying incase its a proxy contract,
    ///      and changes decimals on us.
    function decimals() public view returns (uint8) {
        return IERC20(underlying).decimals();
    }

    /// @notice Gets balance of this contract in terms of the underlying.
    /// @dev This excludes changes in underlying token balance by the 
    ///      current transaction, if any.
    /// @return The quantity of underlying tokens owned by the market.
    function marketUnderlyingHeld() public view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /// @notice Returns the type of Curvance token, 1 = Collateral, 0 = Debt.
    function isCToken() public pure returns (bool) {
        return false;
    }

    /// @notice Accrues interest then return the up-to-date exchange rate.
    /// @return Calculated exchange rate, in `WAD`.
    function exchangeRateWithUpdate() public nonReentrant returns (uint256) {
        accrueInterest();
        return exchangeRateCached();
    }

    /// @notice Calculates the exchange rate from the underlying to the dToken.
    /// @return Cached exchange rate, in `WAD`.
    function exchangeRateCached() public view returns (uint256) {
        // We do not need to check for totalSupply = 0,
        // when we list a market we mint a small amount ourselves.
        // exchangeRate calculation:
        // (total underlying held + totalBorrows - totalReserves) / totalSupply.
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

    /// @notice Applies accrued interest to total borrows and reserves.
    /// @dev This calculates interest accrued from the last checkpoint
    ///      up to the latest available checkpoint.
    function accrueInterest() public {
        // Pull current exchange rate data.
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

        // Calculate the interest compounds to update, 
        // in `interestCompoundRate`.
        // Calculate the interest accumulated into borrows, reserves, 
        // and the new exchange rate.
        uint256 interestCompounds = (block.timestamp -
            cachedData.lastTimestampUpdated) / cachedData.compoundRate;
        uint256 interestAccumulated = borrowRate * interestCompounds;
        uint256 debtAccumulated = (interestAccumulated * borrowsPrior) / WAD;
        uint256 totalBorrowsNew = debtAccumulated + borrowsPrior;
        uint256 exchangeRateNew = ((interestAccumulated * exchangeRatePrior) /
            WAD) + exchangeRatePrior;

        // Update storage data.
        marketData.lastTimestampUpdated = uint32(
            cachedData.lastTimestampUpdated +
                (interestCompounds * cachedData.compoundRate)
        );
        marketData.exchangeRate = uint224(exchangeRateNew);
        totalBorrows = totalBorrowsNew;

        // Check whether the market takes interest,
        // and debt has been accumulated.
        uint256 newReserves = ((interestFactor * debtAccumulated) / WAD);
        if (newReserves > 0) {
            totalReserves = newReserves + reservesPrior;

            // Deposit new reserves into gauge.
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
    /// @param newInterestRateModel the new interest rate model to use.
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

    /// @notice Updates the interest factor value.
    /// @param newInterestFactor the new interest factor.
    function _setInterestFactor(uint256 newInterestFactor) internal {
        // The DAO cannot take more than 50% of interest collected.
        if (newInterestFactor > 5000) {
            revert DToken__ExcessiveValue();
        }

        uint256 oldInterestFactor = interestFactor;

        /// The Interest Rate Factor is in `WAD` format.
        /// So we need to multiply by 1e14 to format properly.
        /// from basis points to %.
        interestFactor = newInterestFactor * 1e14;

        emit NewInterestFactor(oldInterestFactor, newInterestFactor);
    }

    /// @notice Transfer `tokens` tokens from `from` to `to`,
    ///         by `spender` internally.
    /// @dev Called by both `transfer` and `transferFrom` internally.
    /// @param spender The address of the account performing the transfer.
    /// @param from The address of the source account.
    /// @param to The address of the destination account.
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
        lendtroller.canTransfer(address(this), from, tokens);

        // Get the allowance, if the spender is not the `from` address.
        if (spender != from) {
            // Validate that spender has enough allowance
            // for the transfer with underflow check.
            allowance[from][spender] = allowance[from][spender] - tokens;
        }

        // Update token balances
        balanceOf[from] = balanceOf[from] - tokens;
        // We know that from balance wont overflow 
        // due to underflow check above.
        unchecked {
            balanceOf[to] = balanceOf[to] + tokens;
        }

        // emit events on gauge pool.
        GaugePool gaugePool = _gaugePool();
        gaugePool.withdraw(address(this), from, tokens);
        gaugePool.deposit(address(this), to, tokens);

        // We emit a Transfer event.
        emit Transfer(from, to, tokens);
    }

    /// @notice User supplies assets into the market,
    ///         and receives dTokens in exchange.
    /// @dev Assumes interest has already been accrued up to
    ///      the current timestamp.
    /// @param account The address of the account which is supplying the assets.
    /// @param recipient The address of the account which will receive dToken.
    /// @param amount The amount of the underlying asset to supply.
    function _mint(
        address account,
        address recipient,
        uint256 amount
    ) internal {
        // Accrue interest if necessary.
        accrueInterest();

        // Fail if mint not allowed.
        lendtroller.canMint(address(this));

        // Get exchange rate before transfer.
        uint256 er = exchangeRateCached();

        // Transfer underlying in.
        SafeTransferLib.safeTransferFrom(
            underlying,
            account,
            address(this),
            amount
        );

        // Calculate dTokens to be minted.
        uint256 tokens = (amount * WAD) / er;

        unchecked {
            totalSupply = totalSupply + tokens;
            /// Calculate their new balance.
            balanceOf[recipient] = balanceOf[recipient] + tokens;
        }

        // emit events on gauge pool.
        _gaugePool().deposit(address(this), recipient, tokens);

        emit Transfer(address(0), recipient, tokens);
    }

    /// @notice User redeems dTokens in exchange for the underlying asset.
    /// @dev Assumes interest has already been accrued up to
    ///      the current timestamp.
    /// @param redeemer The address of the account which is 
    ///                 redeeming the tokens.
    /// @param recipient The recipient address.
    /// @param tokens The number of dTokens to redeem into underlying.
    /// @param amount The number of underlying tokens to receive from
    ///               redeeming dTokens.
    function _redeem(
        address redeemer,
        address recipient,
        uint256 tokens,
        uint256 amount
    ) internal {
        // Check if we have enough underlying held to support the redemption.
        if (marketUnderlyingHeld() < amount) {
            revert DToken__InsufficientUnderlyingHeld();
        }

        balanceOf[redeemer] = balanceOf[redeemer] - tokens;
        // We have account underflow check above so we do not need
        // a redundant check here.
        unchecked {
            totalSupply = totalSupply - tokens;
        }

        // emit events on gauge pool and check if tokens == 0.
        _gaugePool().withdraw(address(this), redeemer, tokens);

        SafeTransferLib.safeTransfer(underlying, recipient, amount);

        emit Transfer(redeemer, address(0), tokens);
    }

    /// @notice Users borrow assets from the protocol.
    /// @param account The account borrowing the assets.
    /// @param amount The amount of the underlying asset to borrow.
    /// @param recipient The account receiving the borrwed assets.
    function _borrow(
        address account,
        uint256 amount,
        address recipient
    ) internal {
        // Check if we have enough underlying held to support the borrow.
        if (marketUnderlyingHeld() - totalReserves < amount) {
            revert DToken__InsufficientUnderlyingHeld();
        }

        // We calculate the new account and total borrow balances, 
        // failing on overflow.
        _debtOf[account].principal = debtBalanceCached(account) + amount;
        _debtOf[account].accountExchangeRate = marketData.exchangeRate;
        totalBorrows = totalBorrows + amount;

        SafeTransferLib.safeTransfer(underlying, recipient, amount);

        emit Borrow(account, amount);
    }

    /// @notice Allows a payer to repay a loan on behalf of the account, 
    ///         usually themselves.
    /// @dev First validates that the payer is allowed to repay the loan, 
    ///      then repays. the loan by transferring in the repay amount.
    ///      Emits a repay event on successful repayment.
    /// @param payer The address paying off the borrow.
    /// @param account The account with the debt being paid off.
    /// @param amount The amount the payer wishes to repay, 
    ///               or 0 for the full outstanding amount.
    /// @return The actual amount repaid.
    function _repay(
        address payer,
        address account,
        uint256 amount
    ) internal returns (uint256) {
        // Validate that the payer is allowed to repay the loan.
        lendtroller.canRepay(address(this), account);

        // Cache how much the account has to save gas.
        uint256 accountDebt = debtBalanceCached(account);

        // If amount == 0, amount = accountDebt.
        amount = amount == 0 ? accountDebt : amount;

        SafeTransferLib.safeTransferFrom(
            underlying,
            payer,
            address(this),
            amount
        );

        // We calculate the new account and total borrow balances,
        // failing on underflow.
        _debtOf[account].principal = accountDebt - amount;
        _debtOf[account].accountExchangeRate = marketData.exchangeRate;
        totalBorrows -= amount;

        emit Repay(payer, account, amount);
        return amount;
    }

    /// @notice The liquidator liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @param account The account of this dToken to be liquidated.
    /// @param liquidator The address repaying the borrow and seizing collateral.
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
        // Update interest funding if necessary.
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
        (amount, liquidatedTokens, protocolTokens) = lendtroller
            .canLiquidateWithExecution(
                address(this),
                address(collateralToken),
                account,
                amount,
                exactAmount
            );

        // Validate that the token is listed inside the market.
        if (!lendtroller.isListed(address(this))) {
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

    /// @notice Returns gauge pool contract address.
    /// @return The gauge controller contract address.
    function _gaugePool() internal view returns (GaugePool) {
        return lendtroller.gaugePool();
    }

    /// @dev Internal helper for reverting efficiently.
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
