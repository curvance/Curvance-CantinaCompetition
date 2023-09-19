// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ERC165 } from "contracts/libraries/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { InterestRateModel } from "contracts/market/interestRates/InterestRateModel.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance's Debt Token Contract
contract DToken is ERC165, ReentrancyGuard {
    /// TYPES ///

    struct DebtData {
        /// @notice principal total balance (with accrued interest)
        uint256 principal;
        /// @notice current exchange rate for user
        uint256 interestIndex;
    }

    struct ExchangeRateData {
        /// @notice Timestamp interest was last update
        uint32 lastTimestampUpdated;
        /// @notice Borrow exchange rate at `lastTimestampUpdated`
        uint224 exchangeRate;
        /// @notice Rate at which interest compounds, in seconds
        uint256 compoundRate;
    }

    /// CONSTANTS ///

    /// @notice Scalar for math
    uint256 internal constant EXP_SCALE = 1e18;

    /// @notice for inspection
    bool public constant isDToken = true;

    /// @notice underlying asset for the DToken
    address public immutable underlying;

    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice token name metadata
    string public name;

    /// @notice token symbol metadata
    string public symbol;

    /// @notice Current lending market controller
    ILendtroller public lendtroller;

    /// @notice Current Interest Rate Model
    InterestRateModel public interestRateModel;

    /// @notice Total outstanding borrows of underlying
    uint256 public totalBorrows;

    /// @notice Total protocol reserves of underlying
    uint256 public totalReserves;

    /// @notice Total number of tokens in circulation
    uint256 public totalSupply;

    /// @notice Information corresponding to borrow exchange rate
    ExchangeRateData public borrowExchangeRate;

    /// @notice Interest rate reserve factor
    uint256 internal interestFactor;

    /// @notice account => token balance
    mapping(address => uint256) public balanceOf;

    /// @notice account => spender => approved amount
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice account => BorrowSnapshot (Principal Borrowed, User Interest Index)
    mapping(address => DebtData) internal _debtOf;

    /// EVENTS ///

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event InterestAccrued(
        uint256 debtAccumulated,
        uint256 exchangeRate,
        uint256 totalBorrows
    );
    event Borrow(address borrower, uint256 amount);
    event Repay(address payer, address borrower, uint256 amount);
    event Liquidated(
        address liquidator,
        address borrower,
        uint256 amount,
        address cTokenCollateral,
        uint256 seizeTokens
    );
    event NewLendtroller(address oldLendtroller, address newLendtroller);
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

    error DToken__UnauthorizedCaller();
    error DToken__CannotEqualZero();
    error DToken__ExcessiveValue();
    error DToken__TransferNotAllowed();
    error DToken__CashNotAvailable();
    error DToken__ValidationFailed();
    error DToken__ConstructorParametersareInvalid();
    error DToken__LendtrollerIsNotLendingMarket();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "DToken: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "DToken: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of Curvances Central Registry
    /// @param underlying_ The address of the underlying asset
    /// @param lendtroller_ The address of the Lendtroller
    /// @param interestRateModel_ The address of the interest rate model
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
            revert DToken__ConstructorParametersareInvalid();
        }

        centralRegistry = centralRegistry_;

        // Set the lendtroller after consulting Central Registry
        _setLendtroller(lendtroller_);

        // Initialize timestamp and borrow index
        borrowExchangeRate.lastTimestampUpdated = uint32(block.timestamp);
        borrowExchangeRate.exchangeRate = uint224(EXP_SCALE);

        _setInterestRateModel(interestRateModel_);
        _setInterestFactor(
            centralRegistry.protocolInterestFactor(lendtroller_)
        );

        underlying = underlying_;
        name = string.concat(
            "Curvance interest bearing ",
            IERC20(underlying_).name()
        );
        symbol = string.concat("c", IERC20(underlying_).symbol());

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate of 1e18
        if (IERC20(underlying).totalSupply() >= type(uint232).max) {
            revert DToken__ConstructorParametersareInvalid();
        }
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Used to start a DToken market, executed via lendtroller
    /// @dev  this initial mint is a failsafe against the empty market exploit
    ///       although we protect against it in many ways, better safe than sorry
    /// @param initializer the account initializing the market
    function startMarket(
        address initializer
    ) external nonReentrant returns (bool) {
        if (msg.sender != address(lendtroller)) {
            revert DToken__UnauthorizedCaller();
        }

        uint256 amount = 42069;
        SafeTransferLib.safeTransferFrom(
            underlying,
            initializer,
            address(this),
            amount
        );

        // We do not need to calculate exchange rate here as we will always be the initial depositer
        // with totalSupply equal to 0
        totalSupply = totalSupply + amount;
        balanceOf[initializer] = balanceOf[initializer] + amount;

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), initializer, amount);

        emit Transfer(address(0), initializer, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `msg.sender` to `to`
    /// @param to The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transfer(
        address to,
        uint256 amount
    ) external nonReentrant returns (bool) {
        _transfer(msg.sender, msg.sender, to, amount);
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
    ) external nonReentrant returns (bool) {
        _transfer(msg.sender, from, to, amount);
        return true;
    }

    /// @notice Sender borrows assets from the protocol to their own address
    /// @param amount The amount of the underlying asset to borrow
    function borrow(uint256 amount) external nonReentrant {
        accrueInterest();

        // Reverts if borrow not allowed
        lendtroller.borrowAllowedWithNotify(address(this), msg.sender, amount);

        _borrow(msg.sender, amount, msg.sender);
    }

    /// @notice Position folding borrows from the protocol for `user`
    /// @dev Only Position folding contract can call this function
    /// @param user The user address
    /// @param amount The amount of the underlying asset to borrow
    function borrowForPositionFolding(
        address user,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert DToken__UnauthorizedCaller();
        }

        accrueInterest();
        // Record that the user borrowed before everything else is updated
        lendtroller.notifyAccountBorrow(user);

        _borrow(user, amount, msg.sender);

        IPositionFolding(msg.sender).onBorrow(
            address(this),
            user,
            amount,
            params
        );

        // Fail if position is not allowed, after position folding has re-invested
        lendtroller.borrowAllowed(address(this), user, 0);
    }

    /// @notice Sender repays their own borrow
    /// @param amount The amount to repay, or 0 for the full outstanding amount
    function repay(uint256 amount) external nonReentrant {
        accrueInterest();

        _repay(msg.sender, msg.sender, amount);
    }

    /// @notice Position folding repays `user`'s borrow
    /// @dev Only Position folding contract can call this function
    /// @param amount The amount to repay, or 0 for the full outstanding amount
    function repayForPositionFolding(
        address user,
        uint256 amount
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert DToken__UnauthorizedCaller();
        }

        accrueInterest();

        _repay(msg.sender, user, amount);
    }

    /// @notice Allows liquidation of a borrower's collateral,
    ///         Transferring the liquidated collateral to the liquidator
    /// @param borrower The address of the borrower to be liquidated
    /// @param amount The amount of underlying asset the liquidator wishes to repay
    /// @param mTokenCollateral The market in which to seize collateral from the borrower
    function liquidate(
        address borrower,
        uint256 amount,
        IMToken mTokenCollateral
    ) external nonReentrant {
        accrueInterest();

        _liquidate(msg.sender, borrower, amount, mTokenCollateral);
    }

    /// @notice Sender redeems dTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param amount The number of dTokens to redeem into underlying
    function redeem(uint256 amount) external nonReentrant {
        accrueInterest();

        lendtroller.redeemAllowed(address(this), msg.sender, amount);

        _redeem(
            msg.sender,
            amount,
            (exchangeRateStored() * amount) / EXP_SCALE,
            msg.sender
        );
    }

    /// @notice Sender redeems dTokens in exchange for a specified amount of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param underlyingAmount The amount of underlying to redeem
    function redeemUnderlying(uint256 underlyingAmount) external nonReentrant {
        accrueInterest();

        uint256 amount = (underlyingAmount * EXP_SCALE) / exchangeRateStored();

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), msg.sender, amount);

        _redeem(msg.sender, amount, underlyingAmount, msg.sender);
    }

    /// @notice Helper function for Position Folding contract to redeem underlying tokens
    /// @param user The user address
    /// @param underlyingAmount The amount of the underlying asset to redeem
    function redeemUnderlyingForPositionFolding(
        address user,
        uint256 underlyingAmount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert DToken__UnauthorizedCaller();
        }

        accrueInterest();

        _redeem(
            user,
            (underlyingAmount * EXP_SCALE) / exchangeRateStored(),
            underlyingAmount,
            msg.sender
        );

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            user,
            underlyingAmount,
            params
        );

        // Fail if redeem not allowed, position folding has re-invested
        lendtroller.redeemAllowed(address(this), user, 0);
    }

    /// @notice Sender supplies assets into the market and receives dTokens in exchange
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param mintAmount The amount of the underlying asset to supply
    /// @return bool true=success
    function mint(uint256 mintAmount) external nonReentrant returns (bool) {
        accrueInterest();

        _mint(msg.sender, msg.sender, mintAmount);
        return true;
    }

    /// @notice Sender supplies assets into the market and receives dTokens in exchange
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param recipient The recipient address
    /// @param mintAmount The amount of the underlying asset to supply
    /// @return bool true=success
    function mintFor(
        uint256 mintAmount,
        address recipient
    ) external nonReentrant returns (bool) {
        accrueInterest();

        _mint(msg.sender, recipient, mintAmount);
        return true;
    }

    /// @notice Adds reserves by transferring from Curvance DAO to the market and depositing to the gauge
    /// @param amount The amount of underlying token to add as reserves measured in assets
    function depositReserves(
        uint256 amount
    ) external nonReentrant onlyDaoPermissions {
        accrueInterest();

        // Calculate asset -> shares exchange rate
        uint256 tokens = (amount * EXP_SCALE) / exchangeRateStored();

        // On success, the market will deposit `amount` to the market
        SafeTransferLib.safeTransferFrom(
            underlying,
            msg.sender,
            address(this),
            amount
        );

        // Query current DAO operating address
        address daoAddress = centralRegistry.daoAddress();

        // Deposit new reserves into gauge
        GaugePool(gaugePool()).deposit(address(this), daoAddress, tokens);

        // Update reserves
        totalReserves = totalReserves + tokens;

        emit Transfer(address(0), address(this), tokens);
    }

    /// @notice Reduces reserves by withdrawing from the gauge and transferring to Curvance DAO
    /// @dev If daoAddress is going to be moved all reserves should be withdrawn first
    /// @param amount Amount of reserves to withdraw measured in assets
    function withdrawReserves(
        uint256 amount
    ) external nonReentrant onlyDaoPermissions {
        accrueInterest();

        // Make sure we have enough cash to cover withdrawal
        if (getCash() < amount) {
            revert DToken__CashNotAvailable();
        }

        uint256 tokens = (amount * EXP_SCALE) / exchangeRateStored();

        // Update reserves with underflow check
        totalReserves = totalReserves - tokens;

        // Query current DAO operating address
        address daoAddress = centralRegistry.daoAddress();
        // Withdraw reserves from gauge
        GaugePool(gaugePool()).withdraw(address(this), daoAddress, tokens);

        // Transfer underlying to DAO measured in assets
        SafeTransferLib.safeTransfer(underlying, daoAddress, amount);

        emit Transfer(address(this), address(0), tokens);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// Admin Functions

    /// @notice Rescue any token sent by mistake
    /// @param token The token to rescue.
    /// @param amount The amount of tokens to rescue.
    function rescueToken(
        address token,
        uint256 amount
    ) external onlyDaoPermissions {
        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (address(this).balance < amount) {
                revert DToken__ExcessiveValue();
            }

            (bool success, ) = payable(daoOperator).call{ value: amount }("");

            if (!success) {
                revert DToken__ValidationFailed();
            }
        } else {
            if (token == underlying) {
                revert DToken__TransferNotAllowed();
            }

            if (IERC20(token).balanceOf(address(this)) < amount) {
                revert DToken__ExcessiveValue();
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// @notice Sets a new lendtroller for the market
    /// @dev Admin function to set a new lendtroller
    /// @param newLendtroller New lendtroller address
    function setLendtroller(
        address newLendtroller
    ) external onlyElevatedPermissions {
        _setLendtroller(newLendtroller);
    }

    /// @notice accrues interest and updates the interest rate model
    /// @dev Admin function to update the interest rate model
    /// @param newInterestRateModel the new interest rate model to use
    function setInterestRateModel(
        address newInterestRateModel
    ) external onlyElevatedPermissions {
        accrueInterest();

        _setInterestRateModel(newInterestRateModel);
    }

    /// @notice accrues interest and updates the interest factor
    /// @dev Admin function to update the interest factor value
    /// @param newInterestFactor the new interest factor to use
    function setInterestFactor(
        uint256 newInterestFactor
    ) external onlyElevatedPermissions {
        accrueInterest();

        _setInterestFactor(newInterestFactor);
    }

    /// @notice Get the underlying balance of the `account`
    /// @dev This also accrues interest in a transaction
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlying(address account) external returns (uint256) {
        return ((exchangeRateCurrent() * balanceOf[account]) / EXP_SCALE);
    }

    /// @notice Get a snapshot of the account's balances, and the cached exchange rate
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    /// @return tokenBalance
    /// @return borrowBalance
    /// @return exchangeRate scaled 1e18
    function getAccountSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return (
            balanceOf[account],
            borrowBalanceStored(account),
            exchangeRateStored()
        );
    }

    /// @notice Get a snapshot of the dToken and `account` data
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    function getAccountSnapshotPacked(
        address account
    ) external view returns (AccountSnapshot memory) {
        return (
            AccountSnapshot({
                asset: address(this),
                tokenType: 0,
                mTokenBalance: balanceOf[account],
                borrowBalance: borrowBalanceStored(account),
                exchangeRate: exchangeRateStored()
            })
        );
    }

    /// @notice Calculates the current dToken utilization rate
    /// @return The utilization rate between [0, EXP_SCALE]
    function utilizationRate() external view returns (uint256) {
        return
            interestRateModel.utilizationRate(
                getCash(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current dToken borrow interest rate per year
    /// @return The borrow interest rate per year, scaled by 1e18
    function borrowRatePerYear() external view returns (uint256) {
        return
            interestRateModel.getBorrowRatePerYear(
                getCash(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current dToken supply interest rate per year
    /// @return The supply interest rate per year, scaled by 1e18
    function supplyRatePerYear() external view returns (uint256) {
        return
            interestRateModel.getSupplyRatePerYear(
                getCash(),
                totalBorrows,
                totalReserves,
                interestFactor
            );
    }

    /// @notice Returns the current total borrows plus accrued interest
    /// @return The total borrows with interest
    function totalBorrowsCurrent() external nonReentrant returns (uint256) {
        accrueInterest();
        return totalBorrows;
    }

    /// @notice Accrue interest to updated borrowIndex
    ///  and then calculate account's borrow balance using the updated borrowIndex
    /// @param account The address whose balance should be calculated after updating borrowIndex
    /// @return The calculated balance
    function borrowBalanceCurrent(
        address account
    ) external nonReentrant returns (uint256) {
        accrueInterest();
        return borrowBalanceStored(account);
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Return the borrow balance of account based on stored data
    /// @param account The address whose balance should be calculated
    /// @return The calculated balance
    function borrowBalanceStored(
        address account
    ) public view returns (uint256) {
        // Cache borrow data to save gas
        DebtData storage borrowSnapshot = _debtOf[account];

        // If borrowBalance = 0 then borrowIndex is likely also 0
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        // Calculate new borrow balance using the interest index:
        // borrowBalanceStored = borrower.principal * DToken.borrowIndex / borrower.interestIndex
        return
            (borrowSnapshot.principal * borrowExchangeRate.exchangeRate) /
            borrowSnapshot.interestIndex;
    }

    /// @notice Returns the decimals of the token
    /// @dev We pull directly from underlying incase its a proxy contract
    ///      and changes decimals on us
    function decimals() public view returns (uint8) {
        return IERC20(underlying).decimals();
    }

    /// @notice Gets balance of this contract in terms of the underlying
    /// @dev This excludes changes in underlying token balance by the current transaction, if any
    /// @return The quantity of underlying tokens owned by this contract
    function getCash() public view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /// @notice Returns the type of Curvance token, 1 = Collateral, 0 = Debt
    function tokenType() public pure returns (uint256) {
        return 0;
    }

    /// @notice Returns gauge pool contract address
    /// @return gaugePool the gauge controller contract address
    function gaugePool() public view returns (address) {
        return lendtroller.gaugePool();
    }

    /// @notice Accrue interest then return the up-to-date exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateCurrent() public nonReentrant returns (uint256) {
        accrueInterest();
        return exchangeRateStored();
    }

    /// @notice Calculates the exchange rate from the underlying to the dToken
    /// @dev This function does not accrue interest before calculating the exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateStored() public view returns (uint256) {
        // We do not need to check for totalSupply = 0,
        // when we list a market we mint a small amount ourselves
        // exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
        return
            ((getCash() + totalBorrows - totalReserves) * EXP_SCALE) /
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

    /// @notice Applies accrued interest to total borrows and reserves
    /// @dev This calculates interest accrued from the last checkpoint
    ///      up to the latest available checkpoint.
    function accrueInterest() public {
        // Pull current exchange rate data
        ExchangeRateData memory borrowData = borrowExchangeRate;

        // If we are up to date there is no reason to continue
        if (
            borrowData.lastTimestampUpdated + borrowData.compoundRate >
            block.timestamp
        ) {
            return;
        }

        // Cache current values to save gas
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 exchangeRatePrior = borrowData.exchangeRate;

        // Calculate the current borrow interest rate
        uint256 borrowRate = interestRateModel.getBorrowRate(
            getCash(),
            borrowsPrior,
            reservesPrior
        );

        // Calculate the interest compounds to update, in `interestCompoundRate`
        // Calculate the interest accumulated into borrows and reserves and the new exchange rate:
        uint256 interestCompounds = (block.timestamp -
            borrowData.lastTimestampUpdated) / borrowData.compoundRate;
        uint256 interestAccumulated = borrowRate * interestCompounds;
        uint256 debtAccumulated = (interestAccumulated * borrowsPrior) /
            EXP_SCALE;
        uint256 totalBorrowsNew = debtAccumulated + borrowsPrior;
        uint256 exchangeRateNew = ((interestAccumulated * exchangeRatePrior) /
            EXP_SCALE) + exchangeRatePrior;

        // Update storage data
        borrowExchangeRate.lastTimestampUpdated = uint32(
            borrowData.lastTimestampUpdated +
                (interestCompounds * borrowData.compoundRate)
        );
        borrowExchangeRate.exchangeRate = uint224(exchangeRateNew);
        totalBorrows = totalBorrowsNew;
        totalReserves =
            ((interestFactor * debtAccumulated) / EXP_SCALE) +
            reservesPrior;

        emit InterestAccrued(
            debtAccumulated,
            exchangeRateNew,
            totalBorrowsNew
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Sets a new lendtroller for the market
    /// @param newLendtroller New lendtroller address
    function _setLendtroller(address newLendtroller) internal {
        // Ensure that lendtroller parameter is a lendtroller
        if (!centralRegistry.isLendingMarket(newLendtroller)) {
            revert DToken__LendtrollerIsNotLendingMarket();
        }

        // Cache the current lendtroller to save gas
        address oldLendtroller = address(lendtroller);

        // Set new lendtroller
        lendtroller = ILendtroller(newLendtroller);

        emit NewLendtroller(oldLendtroller, newLendtroller);
    }

    /// @notice Updates the interest rate model
    /// @param newInterestRateModel the new interest rate model to use
    function _setInterestRateModel(address newInterestRateModel) internal {
        // Ensure we are switching to an actual Interest Rate Model
        InterestRateModel(newInterestRateModel).IS_INTEREST_RATE_MODEL();

        // Cache the current interest rate model to save gas
        address oldInterestRateModel = address(interestRateModel);

        // Set new interest rate model and compound rate
        interestRateModel = InterestRateModel(newInterestRateModel);
        borrowExchangeRate.compoundRate = InterestRateModel(
            newInterestRateModel
        ).compoundRate();

        emit NewMarketInterestRateModel(
            oldInterestRateModel,
            newInterestRateModel,
            borrowExchangeRate.compoundRate
        );
    }

    /// @notice Updates the interest factor value
    /// @param newInterestFactor the new interest factor
    function _setInterestFactor(uint256 newInterestFactor) internal {
        if (newInterestFactor > 5000) {
            revert DToken__ExcessiveValue();
        }

        uint256 oldInterestFactor = interestFactor;

        /// The Interest Rate Factor is in `EXP_SCALE` format
        /// So we need to multiply by 1e14 to format properly
        /// from basis points to %
        interestFactor = newInterestFactor * 1e14;

        emit NewInterestFactor(oldInterestFactor, newInterestFactor);
    }

    /// @notice Transfer `tokens` tokens from `from` to `to` by `spender` internally
    /// @dev Called by both `transfer` and `transferFrom` internally
    /// @param spender The address of the account performing the transfer
    /// @param from The address of the source account
    /// @param to The address of the destination account
    /// @param tokens The number of tokens to transfer
    function _transfer(
        address spender,
        address from,
        address to,
        uint256 tokens
    ) internal {
        // Do not allow self-transfers
        if (from == to) {
            revert DToken__TransferNotAllowed();
        }

        // Fails if transfer not allowed
        lendtroller.transferAllowed(address(this), from, to, tokens);

        // Get the allowance, if the spender is not the `from` address
        if (spender != from) {
            // Validate that spender has enough allowance for the transfer with underflow check
            allowance[from][spender] = allowance[from][spender] - tokens;
        }

        // Update token balances
        balanceOf[from] = balanceOf[from] - tokens;
        /// We know that from balance wont overflow due to underflow check above
        unchecked {
            balanceOf[to] = balanceOf[to] + tokens;
        }

        // emit events on gauge pool
        address _gaugePool = gaugePool();
        GaugePool(_gaugePool).withdraw(address(this), from, tokens);
        GaugePool(_gaugePool).deposit(address(this), to, tokens);

        // We emit a Transfer event
        emit Transfer(from, to, tokens);
    }

    /// @notice User supplies assets into the market and receives dTokens in exchange
    /// @dev Assumes interest has already been accrued up to the current timestamp
    /// @param user The address of the account which is supplying the assets
    /// @param recipient The address of the account which will receive dToken
    /// @param amount The amount of the underlying asset to supply
    function _mint(address user, address recipient, uint256 amount) internal {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), recipient);

        // Get exchange rate before transfer
        uint256 er = exchangeRateStored();

        // Transfer underlying in
        SafeTransferLib.safeTransferFrom(
            underlying,
            user,
            address(this),
            amount
        );

        // Calculate dTokens to be minted
        uint256 tokens = (amount * EXP_SCALE) / er;

        unchecked {
            totalSupply = totalSupply + tokens;
            /// Calculate their new balance
            balanceOf[recipient] = balanceOf[recipient] + tokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), recipient, tokens);

        emit Transfer(address(0), recipient, tokens);
    }

    /// @notice User redeems dTokens in exchange for the underlying asset
    /// @dev Assumes interest has already been accrued up to the current timestamp
    /// @param redeemer The address of the account which is redeeming the tokens
    /// @param tokens The number of dTokens to redeem into underlying
    /// @param amount The number of underlying tokens to receive from redeeming dTokens
    /// @param recipient The recipient address
    function _redeem(
        address redeemer,
        uint256 tokens,
        uint256 amount,
        address recipient
    ) internal {
        // Check if we have enough cash to support the redeem
        if (getCash() < amount) {
            revert DToken__CashNotAvailable();
        }

        // Validate redemption parameters
        if (tokens == 0 && amount > 0) {
            revert DToken__CannotEqualZero();
        }

        balanceOf[redeemer] = balanceOf[redeemer] - tokens;
        // We have user underflow check above so we do not need a redundant check here
        unchecked {
            totalSupply = totalSupply - tokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), redeemer, tokens);

        SafeTransferLib.safeTransfer(underlying, recipient, amount);

        emit Transfer(redeemer, address(0), tokens);
    }

    /// @notice Users borrow assets from the protocol to their own address
    /// @param amount The amount of the underlying asset to borrow
    function _borrow(
        address borrower,
        uint256 amount,
        address recipient
    ) internal {
        // Check if we have enough cash to support the borrow
        if (getCash() - totalReserves < amount) {
            revert DToken__CashNotAvailable();
        }

        // We calculate the new borrower and total borrow balances, failing on overflow:
        _debtOf[borrower].principal = borrowBalanceStored(borrower) + amount;
        _debtOf[borrower].interestIndex = borrowExchangeRate.exchangeRate;
        totalBorrows = totalBorrows + amount;

        SafeTransferLib.safeTransfer(underlying, recipient, amount);

        emit Borrow(borrower, amount);
    }

    /// @notice Allows a payer to repay a loan on behalf of the borrower, usually themselves
    /// @dev First validates that the payer is allowed to repay the loan, then repays
    ///      the loan by transferring in the repay amount. Emits a repay event on
    ///      successful repayment.
    /// @param payer The address paying off the borrow
    /// @param borrower The account with the debt being paid off
    /// @param amount The amount the payer wishes to repay, or 0 for the full outstanding amount
    /// @return The actual amount repaid
    function _repay(
        address payer,
        address borrower,
        uint256 amount
    ) internal returns (uint256) {
        // Validate that the payer is allowed to repay the loan
        lendtroller.repayAllowed(address(this), borrower);

        // Cache how much the borrower has to save gas
        uint256 accountBorrowsPrev = borrowBalanceStored(borrower);

        // If amount == uint max, amount = accountBorrows
        amount = amount == 0 ? accountBorrowsPrev : amount;

        SafeTransferLib.safeTransferFrom(
            underlying,
            payer,
            address(this),
            amount
        );

        // We calculate the new borrower and total borrow balances, failing on underflow:
        _debtOf[borrower].principal = accountBorrowsPrev - amount;
        _debtOf[borrower].interestIndex = borrowExchangeRate.exchangeRate;
        totalBorrows -= amount;

        emit Repay(payer, borrower, amount);
        return amount;
    }

    /// @notice The liquidator liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @param borrower The borrower of this dToken to be liquidated
    /// @param liquidator The address repaying the borrow and seizing collateral
    /// @param mTokenCollateral The market in which to seize collateral from the borrower
    /// @param amount The amount of the underlying borrowed asset to repay
    function _liquidate(
        address liquidator,
        address borrower,
        uint256 amount,
        IMToken mTokenCollateral
    ) internal {
        // Fail if borrower = liquidator
        assembly {
            if eq(borrower, liquidator) {
                // revert with DToken__UnauthorizedCaller()
                mstore(0x00, 0xefeae624)
                revert(0x1c, 0x04)
            }
        }

        /// The MToken must be a collateral token E.G. tokenType == 1
        if (mTokenCollateral.tokenType() == 0) {
            revert DToken__ValidationFailed();
        }

        // Fail if liquidate not allowed,
        // trying to pay down too much with excessive repayAmount will revert here
        lendtroller.liquidateAllowed(
            address(this),
            address(mTokenCollateral),
            borrower,
            amount
        );

        // calculates DTokens to repay for liquidation, reverts if repay fails
        uint256 repayAmount = _repay(liquidator, borrower, amount);

        // We calculate the number of CTokens that will be liquidated
        (uint256 liquidatedTokens, uint256 protocolTokens) = lendtroller
            .calculateLiquidatedTokens(
                address(this),
                address(mTokenCollateral),
                repayAmount
            );

        // Revert if borrower does not have enough collateral
        if (mTokenCollateral.balanceOf(borrower) < liquidatedTokens) {
            revert DToken__ExcessiveValue();
        }

        // We check above that the mToken must be a collateral token,
        // so we cant be seizing this mToken as it is a debt token,
        // so there is no reEntry risk
        mTokenCollateral.seize(
            liquidator,
            borrower,
            liquidatedTokens,
            protocolTokens
        );

        emit Liquidated(
            liquidator,
            borrower,
            repayAmount,
            address(mTokenCollateral),
            liquidatedTokens
        );
    }
}
