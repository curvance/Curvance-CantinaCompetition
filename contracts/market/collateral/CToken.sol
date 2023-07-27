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
import { ICToken } from "contracts/interfaces/market/ICToken.sol";
import { IEIP20NonStandard } from "contracts/interfaces/market/IEIP20NonStandard.sol";

/// @title Curvance's CToken Contract
/// @notice Abstract base for CTokens
contract CToken is ICToken, ERC165, ReentrancyGuard {
    /// STRUCTS ///

    /// @notice Container for borrow balance information
    /// @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
    /// @member interestIndex Global borrowIndex as of the most recent balance-changing action
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    struct AccountData {
        // The token balance of the user.
        uint216 balance;
        // Stores the timestamp of the last time a user deposited tokens.
        uint40 lastTimestamp;
}

    /// CONSTANTS ///

    uint256 internal constant expScale = 1e18;

    // Maximum borrow rate that can ever be applied (.0005% / second)
    uint256 internal constant borrowRateMaxScaled = 0.0005e16;

    // Maximum fraction of interest that can be set aside for reserves
    uint256 internal constant reserveFactorMaxScaled = 1e18;

    // Mask of all bits in account data excluding timestamp, meaning all room reserved for balanceOf
    uint256 private constant _BITMASK_BALANCE_OF_ENTRY = (1 << 216) - 1;

    // The bit position of `timestamp` in packed address data
    uint256 private constant _BITPOS_TIMESTAMP = 216;

    /// @notice Indicator that this is a CToken contract (for inspection)
    bool public constant override isCToken = true;

    /// @notice Underlying asset for this CToken
    address public immutable underlying;

    /// @notice Decimals for this CToken
    uint8 public immutable decimals;

    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///
    string public name;
    string public override symbol;
    ILendtroller public override lendtroller;
    InterestRateModel public interestRateModel;
    /// Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
    uint256 internal initialExchangeRateScaled;
    /// @notice Fraction of interest currently set aside for reserves
    uint256 public reserveFactorScaled;
    /// @notice Timestamp that interest was last accrued at
    uint256 public override accrualBlockTimestamp;
    /// @notice Accumulator of the total earned interest rate since the opening of the market
    uint256 public borrowIndex;
    /// @notice Total amount of outstanding borrows of the underlying in this market
    uint256 public override totalBorrows;
    /// @notice Total amount of reserves of the underlying held in this market
    uint256 public totalReserves;
    /// @notice Total number of tokens in circulation
    uint256 public totalSupply;

    // Official record of token balances for each account
    // uint256 bit layout:
    // - [0..215]    `balance`
    // - [216..255]  `borrowTimestamp`
    mapping(address => uint256) internal _accountData;

    // Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint256))
        internal transferAllowances;

    // Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "CToken: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "CToken: UNAUTHORIZED"
        );
        _;
    }

    modifier interestUpdated() {
        require(
            accrualBlockTimestamp == block.timestamp, "CToken: Freshness check failed"
        );
        _;
    }

    /// @param centralRegistry_ The address of Curvances Central Registry
    /// @param underlying_ The address of the underlying asset
    /// @param lendtroller_ The address of the Lendtroller
    /// @param interestRateModel_ The address of the interest rate model
    /// @param initialExchangeRateScaled_ The initial exchange rate, scaled by 1e18
    /// @param name_ ERC-20 name of this token
    /// @param symbol_ ERC-20 symbol of this token
    /// @param decimals_ ERC-20 decimal precision of this token
    constructor(
        ICentralRegistry centralRegistry_,
        address underlying_,
        address lendtroller_,
        InterestRateModel interestRateModel_,
        uint256 initialExchangeRateScaled_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        // Validate that initialize has not been called prior
        if (accrualBlockTimestamp != 0 && borrowIndex != 0) {
            revert PreviouslyInitialized();
        }

        // Set initial exchange rate
        initialExchangeRateScaled = initialExchangeRateScaled_;
        if (initialExchangeRateScaled == 0) {
            revert CannotEqualZero();
        }

        ILendtroller initializedLendtroller = ILendtroller(lendtroller_);

        /// Set the lendtroller ///
        // Ensure invoke lendtroller.isLendtroller() returns true
        if (!initializedLendtroller.isLendtroller()) {
            revert LendtrollerMismatch();
        }

        // Set market's lendtroller to newLendtroller
        lendtroller = initializedLendtroller;

        // Emit NewLendtroller(address(0), newLendtroller)
        emit NewLendtroller(ILendtroller(address(0)), initializedLendtroller);

        // Initialize timestamp and borrow index (timestamp mocks depend on lendtroller being set)
        accrualBlockTimestamp = block.timestamp;
        borrowIndex = expScale;

        /// Set Interest Rate Model ///
        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        if (!interestRateModel_.isInterestRateModel()) {
            revert ValidationFailed();
        }

        // Configure initial interest rate model
        interestRateModel = interestRateModel_;

        // Emit NewMarketInterestRateModel(address(0), newInterestRateModel)
        emit NewMarketInterestRateModel(
            InterestRateModel(address(0)),
            interestRateModel_
        );

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "CToken: invalid central registry"
        );

        centralRegistry = centralRegistry_;
        underlying = underlying_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;

        // Sanity check underlying so that we know users will not need to mint anywhere close to balance cap
        require (IERC20(underlying).totalSupply() < type(uint208).max, "CToken: Underlying token assumptions not met");

    }

    /// @notice Transfer `amount` tokens from `msg.sender` to `to`
    /// @param to The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transfer(
        address to,
        uint256 amount
    ) external override nonReentrant returns (bool) {
        transferTokens(msg.sender, msg.sender, to, amount);
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
    ) external override nonReentrant returns (bool) {
        transferTokens(msg.sender, from, to, amount);
        return true;
    }

    /// @notice Sender borrows assets from the protocol to their own address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrow(uint256 borrowAmount) external override {
        accrueInterest();

        // Reverts if borrow not allowed
        lendtroller.borrowAllowed(address(this), msg.sender, borrowAmount);

        _borrow(payable(msg.sender), borrowAmount, payable(msg.sender));
    }

    /// @notice Position folding contract will call this function
    /// @param user The user address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrowForPositionFolding(
        address payable user,
        uint256 borrowAmount,
        bytes calldata params
    ) external {
        if (msg.sender != lendtroller.positionFolding()) {
            revert FailedNotFromPositionFolding();
        }

        accrueInterest();

        _borrow(user, borrowAmount, payable(msg.sender));

        IPositionFolding(msg.sender).onBorrow(
            address(this),
            user,
            borrowAmount,
            params
        );

        // Fail if position is not allowed
        lendtroller.borrowAllowed(address(this), user, 0);
    }

    /// @notice Sender repays their own borrow
    /// @param repayAmount The amount to repay, or -1 for the full outstanding amount
    function repayBorrow(uint256 repayAmount) external override nonReentrant {
        accrueInterest();

        _repayBorrow(msg.sender, msg.sender, repayAmount);
    }

    function repayBorrowForPositionFolding(address user, uint256 repayAmount) external nonReentrant {

        if (msg.sender != lendtroller.positionFolding()) {
            revert FailedNotFromPositionFolding();
        }

        accrueInterest();

        _repayBorrow(msg.sender, user, repayAmount);
    }

    /// @notice Allows liquidation of a borrower's collateral,
    ///         Transferring the liquidated collateral to the liquidator
    /// @param borrower The address of the borrower to be liquidated
    /// @param repayAmount The amount of underlying asset the liquidator wishes to repay
    /// @param cTokenCollateral The market in which to seize collateral from the borrower
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) external override nonReentrant {
        // Accrue interest in both locations
        accrueInterest();
        cTokenCollateral.accrueInterest();

        _liquidateBorrow(
            msg.sender,
            borrower,
            repayAmount,
            cTokenCollateral
        );
    }

    /// @notice Sender redeems cTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemTokens The number of cTokens to redeem into underlying
    function redeem(uint256 redeemTokens) external override {
        accrueInterest();

        _redeem(payable(msg.sender), redeemTokens, (exchangeRateStored() * redeemTokens) / expScale, payable(msg.sender));
    }

    /// @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemAmount The amount of underlying to redeem
    function redeemUnderlying(uint256 redeemAmount) external override {
        accrueInterest();

        address payable redeemer = payable(msg.sender);
        uint256 redeemTokens = (redeemAmount * expScale) / exchangeRateStored();

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), redeemer, redeemTokens);

        _redeem(redeemer, redeemTokens, redeemAmount, redeemer);
    }

    /// @notice Helper function for Position Folding contract to redeem underlying tokens
    /// @param user The user address
    /// @param redeemAmount The amount of the underlying asset to redeem
    function redeemUnderlyingForPositionFolding(
        address payable user,
        uint256 redeemAmount,
        bytes calldata params
    ) external {

        if (msg.sender != lendtroller.positionFolding()) {
            revert FailedNotFromPositionFolding();
        }

        accrueInterest();

        _redeem(user, (redeemAmount * expScale) / exchangeRateStored(), redeemAmount, payable(msg.sender));

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            user,
            redeemAmount,
            params
        );

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), user, 0);
    }

    /// @notice Sender supplies assets into the market and receives cTokens in exchange
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param mintAmount The amount of the underlying asset to supply
    /// @return bool true=success
    function mint(uint256 mintAmount) external override nonReentrant returns (bool) {
        accrueInterest();

        _mint(msg.sender, msg.sender, mintAmount);
        return true;
    }

    /// @notice Sender supplies assets into the market and receives cTokens in exchange
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

    /// @notice The sender adds to reserves.
    /// @param addAmount The amount fo underlying token to add as reserves
    function depositReserves(uint256 addAmount) external override nonReentrant onlyElevatedPermissions {
        accrueInterest();

        // We call doTransferIn for the caller and the addAmount
        // On success, the cToken holds an additional addAmount of cash.
        // doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
        // it returns the amount actually transferred, in case of a fee.
        totalReserves += doTransferIn(msg.sender, addAmount);

        // emit ReservesAdded(msg.sender, actualAddAmount, totalReserves); /// changed to emit correct variable
        emit ReservesAdded(msg.sender, addAmount, totalReserves);
    }

    /// @notice Accrues interest and reduces reserves by transferring to admin
    /// @param reduceAmount Amount of reduction to reserves
    function withdrawReserves(
        uint256 reduceAmount
    ) external override nonReentrant onlyElevatedPermissions {
        accrueInterest();

        // Make sure we have enough cash to cover withdrawal
        if (getCash() < reduceAmount) {
            revert ReduceReservesCashNotAvailable();
        }

        // Need underflow check to check if we have sufficient totalReserves
        totalReserves -= reduceAmount;

        // Query current DAO operating address
        address payable daoAddress = payable(centralRegistry.daoAddress());

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(daoAddress, reduceAmount);

        emit ReservesReduced(daoAddress, reduceAmount, totalReserves);
    }

    /// @notice Approve `spender` to transfer up to `amount` from `src`
    /// @dev This will overwrite the approval amount for `spender`
    ///  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
    /// @param spender The address of the account which may transfer tokens
    /// @param amount The number of tokens that are approved (uint256.max means infinite)
    /// @return bool true=success
    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        transferAllowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /// @notice Get the current allowance from `owner` for `spender`
    /// @param owner The address of the account which owns the tokens to be spent
    /// @param spender The address of the account which may transfer tokens
    /// @return uint The number of tokens allowed to be spent (-1 means infinite)
    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return transferAllowances[owner][spender];
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
            require(
                address(this).balance >= amount,
                "CToken: insufficient balance"
            );
            (bool success, ) = payable(daoOperator).call{ value: amount }("");
            require(success, "CToken: !successful");
        } else {
            require(token != underlying, "CToken: cannot withdraw underlying");
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "CToken: insufficient balance"
            );
            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// @notice Sets a new lendtroller for the market
    /// @dev Admin function to set a new lendtroller
    /// @param newLendtroller New lendtroller address.
    function setLendtroller(
        ILendtroller newLendtroller
    ) external override onlyElevatedPermissions {
        ILendtroller oldLendtroller = lendtroller;
        // Ensure invoke lendtroller.isLendtroller() returns true
        if (!newLendtroller.isLendtroller()) {
            revert LendtrollerMismatch();
        }

        // Set market's lendtroller to newLendtroller
        lendtroller = newLendtroller;

        // Emit NewLendtroller(oldLendtroller, newLendtroller)
        emit NewLendtroller(oldLendtroller, newLendtroller);
    }

    /// @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
    /// @dev Admin function to accrue interest and set a new reserve factor
    /// @param newReserveFactorScaled New reserve factor
    function setReserveFactor(
        uint256 newReserveFactorScaled
    ) external override onlyElevatedPermissions {
        accrueInterest();
        
        // Check newReserveFactor ≤ maxReserveFactor
        if (newReserveFactorScaled > reserveFactorMaxScaled) {
            revert ExcessiveValue();
        }

        uint256 oldReserveFactorScaled = reserveFactorScaled;
        reserveFactorScaled = newReserveFactorScaled;

        emit NewReserveFactor(oldReserveFactorScaled, newReserveFactorScaled);
    }

    /// @notice accrues interest and updates the interest rate model
    /// @dev Admin function to accrue interest and update the interest rate model
    /// @param newInterestRateModel the new interest rate model to use
    function setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external override onlyElevatedPermissions {
        accrueInterest();
        
        // Cache the current interest rate model to save gas
        InterestRateModel oldInterestRateModel = interestRateModel;

        // Ensure we are switching to an actual Interest Rate Model
        if (!newInterestRateModel.isInterestRateModel()) {
            revert ValidationFailed();
        }

        // Set the interest rate model to newInterestRateModel
        interestRateModel = newInterestRateModel;

        emit NewMarketInterestRateModel(
            oldInterestRateModel,
            newInterestRateModel
        );
    }

    // Returns the last borrow timestamp for `account`.
    function getBorrowTimestamp(address account) external view returns (uint40) {
        return uint40(_accountData[account] >> _BITPOS_TIMESTAMP);
    }

    /// @notice Get the underlying balance of the `account`
    /// @dev This also accrues interest in a transaction
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlying(
        address account
    ) external override returns (uint256) {
        return ((exchangeRateCurrent() * balanceOf(account)) / expScale);
    }

    /// @notice Get a snapshot of the account's balances, and the cached exchange rate
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks.
    /// @param account Address of the account to snapshot
    /// @return tokenBalance
    /// @return borrowBalance
    /// @return exchangeRate scaled 1e18
    function getAccountSnapshot(
        address account
    ) external view override returns (uint256, uint256, uint256) {
        return (
            balanceOf(account),
            borrowBalanceStored(account),
            exchangeRateStored()
        );
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Will fail unless called by another cToken during the process of liquidation.
    /// @param liquidator The account receiving seized collateral
    /// @param borrower The account having collateral seized
    /// @param seizeTokens The number of cTokens to seize
    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external override nonReentrant {
        _seize(msg.sender, liquidator, borrower, seizeTokens);
    }

    /// @notice Returns the current per-second borrow interest rate for this cToken
    /// @return The borrow interest rate per second, scaled by 1e18
    function borrowRatePerSecond() external view override returns (uint256) {
        return
            interestRateModel.getBorrowRate(
                getCash(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current per-second supply interest rate for this cToken
    /// @return The supply interest rate per second, scaled by 1e18
    function supplyRatePerSecond() external view override returns (uint256) {
        return
            interestRateModel.getSupplyRate(
                getCash(),
                totalBorrows,
                totalReserves,
                reserveFactorScaled
            );
    }

    /// @notice Returns the current total borrows plus accrued interest
    /// @return The total borrows with interest
    function totalBorrowsCurrent()
        external
        override
        nonReentrant
        returns (uint256)
    {
        accrueInterest();
        return totalBorrows;
    }

    /// @notice Accrue interest to updated borrowIndex
    ///  and then calculate account's borrow balance using the updated borrowIndex
    /// @param account The address whose balance should be calculated after updating borrowIndex
    /// @return The calculated balance
    function borrowBalanceCurrent(
        address account
    ) external override nonReentrant returns (uint256) {
        accrueInterest();
        return borrowBalanceStored(account);
    }

    /// @notice Get the token balance of the `account`
    /// @param account The address of the account to query
    /// @return balance The number of tokens owned by `account`
    // @dev Returns the balance of tokens for `account`
    function balanceOf(address account) public view override returns (uint256) {
        return _accountData[account] & _BITMASK_BALANCE_OF_ENTRY;
    }

    /// @notice Return the borrow balance of account based on stored data
    /// @param account The address whose balance should be calculated
    /// @return The calculated balance
    function borrowBalanceStored(
        address account
    ) public view override returns (uint256) {
        // Get borrowBalance and borrowIndex
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        // If borrowBalance = 0 then borrowIndex is likely also 0.
        // Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        // Calculate new borrow balance using the interest index:
        // recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
        uint256 principalTimesIndex = borrowSnapshot.principal * borrowIndex;
        return principalTimesIndex / borrowSnapshot.interestIndex;
    }

    /// @notice Gets balance of this contract in terms of the underlying
    /// @dev This excludes changes in underlying token balance by the current transaction, if any
    /// @return The quantity of underlying tokens owned by this contract
    function getCash() public view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /// @notice Returns gauge pool contract address
    /// @return gaugePool the gauge controller contract address
    function gaugePool() public view returns (address) {
        return lendtroller.gaugePool();
    }

    /// @notice Accrue interest then return the up-to-date exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateCurrent()
        public
        override
        nonReentrant
        returns (uint256)
    {
        accrueInterest();
        return exchangeRateStored();
    }

    /// @notice Calculates the exchange rate from the underlying to the CToken
    /// @dev This function does not accrue interest before calculating the exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateStored() public view override returns (uint256) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            // If there are no tokens minted:
            //  exchangeRate = initialExchangeRate
            return initialExchangeRateScaled;
        } else {
            // Otherwise:
            // exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
            uint256 totalCash = getCash();
            uint256 cashPlusBorrowsMinusReserves = totalCash +
                totalBorrows -
                totalReserves;
            uint256 exchangeRate = (cashPlusBorrowsMinusReserves * expScale) /
                _totalSupply;

            return exchangeRate;
        }
    }

    /// @notice Applies accrued interest to total borrows and reserves
    /// @dev This calculates interest accrued from the last checkpointed second
    ///   up to the current second and writes new checkpoint to storage.
    function accrueInterest() public override {
        // Pull last accrual timestamp from storage
        uint256 accrualBlockTimestampPrior = accrualBlockTimestamp;

        // If we are up to date there is no reason to continue
        if (accrualBlockTimestampPrior == block.timestamp) {
            return;
        }

        // Cache current values to save gas
        uint256 cashPrior = getCash();
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        // Calculate the current borrow interest rate
        uint256 borrowRateScaled = interestRateModel.getBorrowRate(
            cashPrior,
            borrowsPrior,
            reservesPrior
        );
        if (borrowRateMaxScaled < borrowRateScaled) {
            revert ExcessiveValue();
        }

        // Calculate the interest accumulated into borrows and reserves and the new index:
        // simpleInterestFactor = borrowRate * (block.timestamp - accrualBlockTimestampPrior)
        // interestAccumulated = simpleInterestFactor * totalBorrows
        // totalBorrowsNew = interestAccumulated + totalBorrows
        // borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex

        uint256 simpleInterestFactor = borrowRateScaled * (block.timestamp -
            accrualBlockTimestampPrior);
        uint256 interestAccumulated = (simpleInterestFactor * borrowsPrior) /
            expScale;
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 borrowIndexNew = ((simpleInterestFactor * borrowIndexPrior) /
            expScale) + borrowIndexPrior;

        // Update storage data
        accrualBlockTimestamp = block.timestamp;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        // totalReservesNew = interestAccumulated * reserveFactor + totalReserves
        totalReserves = ((reserveFactorScaled *
            interestAccumulated) / expScale) + reservesPrior;

        // We emit an AccrueInterest event
        emit AccrueInterest(
            cashPrior,
            interestAccumulated,
            borrowIndexNew,
            totalBorrowsNew
        );
    }

    /// @notice Transfer `tokens` tokens from `from` to `to` by `spender` internally
    /// @dev Called by both `transfer` and `transferFrom` internally
    /// @param spender The address of the account performing the transfer
    /// @param from The address of the source account
    /// @param to The address of the destination account
    /// @param tokens The number of tokens to transfer
    function transferTokens(
        address spender,
        address from,
        address to,
        uint256 tokens
    ) internal {
        // Fails if transfer not allowed
        lendtroller.transferAllowed(address(this), from, to, tokens);

        // Do not allow self-transfers
        if (from == to) {
            revert TransferNotAllowed();
        }

        // Get the allowance, if the spender is not the `from` address
        if (spender != from) {
            // Validate that spender has enough allowance for the transfer with underflow check
            transferAllowances[from][spender] -= tokens;
        }

        // Update token balances 
        // shift token value by timestamp length bit length so we can check for underflow
        _accountData[from] -= _leftShiftBalance(uint216(tokens));
        /// We know that from balance wont overflow due to totalSupply check in constructor and underflow check above
        unchecked {
            _accountData[to] += tokens;
        }
        
        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), from, tokens);
        GaugePool(gaugePool()).deposit(address(this), to, tokens);

        // We emit a Transfer event
        emit Transfer(from, to, tokens);
    }


    /// @notice Packs balance and timestamp into a single uint256 with bitwise operations and assembly for efficiency.
    /// @dev Shoutout to Vectorized for helping refine these functions
    /// @param bal The user token balance
    /// @param time The timestamp of the users last borrow
    /// @return result The packed balance and timestamp
    function _packAccountData(uint216 bal, uint40 time) internal pure returns (uint256 result) {
        assembly {
            // Use assembly to avoid unnecessary masking when casting to uint256s.
            // This is equivalent to `(uint256(bal) << 40) | uint256(time)`.
            result := or(shl(40, bal), and(0xffffffffff, time))
        }
    }

    /// @notice Shifts a token balance left by 40 bits
    /// @param bal The token balance
    /// @return result The shifted balance
    function _leftShiftBalance(uint216 bal) internal pure returns (uint256 result) {
        assembly {
            // Use assembly to avoid unnecessary masking when casting to uint256s.
            // This is equivalent to `uint256(bal) << 40`.
            result := shl(40, bal)
        }
    }

    /// @notice Replaces the timestamp in the packed user account data, 
    ///         leverages bitwise operations and assembly for efficiency
    /// @param bal The user token balance
    /// @param time The new timestamp for the users last borrow
    /// @return result The packed balance and timestamp
    function _replaceTimestamp(uint256 bal, uint40 time) internal pure returns (uint256 result) {
        assembly {
            // Use assembly to avoid unnecessary masking when casting to uint256s.
            // This is equivalent to `bal ^ (0xffffffffff & (bal ^ time))`.
            result := xor(bal, and(0xffffffffff, xor(bal, time)))
        }
    }

    /// @notice User supplies assets into the market and receives cTokens in exchange
    /// @dev Assumes interest has already been accrued up to the current timestamp
    /// @param user The address of the account which is supplying the assets
    /// @param recipient The address of the account which will receive cToken
    /// @param mintAmount The amount of the underlying asset to supply
    
    function _mint(
        address user,
        address recipient,
        uint256 mintAmount   
    ) internal interestUpdated {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), recipient); //, mintAmount);

        // Exp memory exchangeRate = Exp({mantissa: exchangeRateStored()});
        uint256 exchangeRate = exchangeRateStored();

        // Note: `doTransferIn` reverts if anything goes wrong, since we can't be sure if
        //       side-effects occurred. The function returns the amount actually transferred,
        //       in case of a fee. On success, the cToken holds an additional `actualMintAmount`
        //       of cash.
        uint256 actualMintAmount = doTransferIn(user, mintAmount);

        // We get the current exchange rate and calculate the number of cTokens to be minted:
        //  mintTokens = actualMintAmount / exchangeRate
        uint256 mintTokens = (actualMintAmount * expScale) / exchangeRate;
        totalSupply += mintTokens;

        /// Calculate their new balance
        _accountData[recipient] = _leftShiftBalance(uint216(mintTokens));

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), recipient, mintTokens);

        // We emit a Mint event, and a Transfer event
        emit Mint(user, actualMintAmount, mintTokens, recipient);
        emit Transfer(address(this), recipient, mintTokens);
    }

    /// @notice User redeems cTokens in exchange for the underlying asset
    /// @dev Assumes interest has already been accrued up to the current timestamp
    /// @param redeemer The address of the account which is redeeming the tokens
    /// @param redeemTokens The number of cTokens to redeem into underlying
    /// @param redeemAmount The number of underlying tokens to receive from redeeming cTokens
    /// @param recipient The recipient address
    function _redeem(
        address payable redeemer,
        uint256 redeemTokens,
        uint256 redeemAmount,
        address payable recipient
    ) internal nonReentrant interestUpdated {

        // Check if we have enough cash to support the redeem
        if (getCash() < redeemAmount) {
            revert RedeemTransferOutNotPossible();
        }

        // Need to shift bits by timestamp length to make sure we do a proper underflow check
        // redeemTokens should never be above uint216 and the user can never have more than uint216,
        // So if theyve put in a larger number than type(uint216).max we know it will revert from underflow
        _accountData[redeemer] -= _leftShiftBalance(uint216(redeemTokens));

        // We have user underflow check above so we do not need a redundant check here
        unchecked {
            totalSupply -= redeemTokens;
        }
        
        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), redeemer, redeemTokens);

        // We invoke doTransferOut for the redeemer and the redeemAmount.
        // Note: The cToken must handle variations between ERC-20 and ETH underlying.
        // On success, the cToken has redeemAmount less of cash.
        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(recipient, redeemAmount);

        // We emit a Transfer event, and a Redeem event
        emit Transfer(redeemer, address(this), redeemTokens);
        emit Redeem(redeemer, redeemAmount, redeemTokens);

        // We call the defense hook
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert CannotEqualZero();
        }
    }

    /// @notice Users borrow assets from the protocol to their own address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function _borrow(
        address borrower,
        uint256 borrowAmount,
        address payable recipient
    ) internal nonReentrant interestUpdated {

        // Check if we have enough cash to support the borrow
        if (getCash() < borrowAmount) {
            revert BorrowCashNotAvailable();
        }

        _accountData[borrower] = _replaceTimestamp(balanceOf(borrower), uint40(block.timestamp));

        // We calculate the new borrower and total borrow balances, failing on overflow:
        accountBorrows[borrower].principal = borrowBalanceStored(borrower) + borrowAmount;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows += borrowAmount;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(recipient, borrowAmount);

        // We emit a Borrow event
        emit Borrow(
            borrower,
            borrowAmount
        );
    }

    /// @notice Allows a payer to repay a loan on behalf of the borrower, usually themselves
    /// @dev First validates that the payer is allowed to repay the loan, then repays
    ///      the loan by transferring in the repay amount. Emits a RepayBorrow event on
    ///      successful repayment.
    /// @param payer The address paying off the borrow
    /// @param borrower The account with the debt being paid off
    /// @param repayAmount The amount the payer wishes to repay, or 0 for the full outstanding amount
    /// @return actualRepayAmount The actual amount repaid
    function _repayBorrow(
        address payer,
        address borrower,
        uint256 repayAmount
    ) internal interestUpdated returns (uint256) {
        // Validate that the payer is allowed to repay the loan
        lendtroller.repayBorrowAllowed(address(this), borrower);

        // Cache how much the borrower has to save gas
        uint256 accountBorrowsPrev = borrowBalanceStored(borrower);

        // If repayAmount == uint max, repayAmount = accountBorrows
        uint256 repayAmountFinal = repayAmount == 0
            ? accountBorrowsPrev
            : repayAmount;

        // We call doTransferIn for the payer and the repayAmount
        // Note: On success, the cToken holds an additional repayAmount of cash.
        //       doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
        //       it returns the amount actually transferred, in case of a fee.
        uint256 actualRepayAmount = doTransferIn(payer, repayAmountFinal);

        // We calculate the new borrower and total borrow balances, failing on underflow:
        accountBorrows[borrower].principal = accountBorrowsPrev - actualRepayAmount;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows -= actualRepayAmount;

        // We emit a RepayBorrow event
        emit RepayBorrow(
            payer,
            borrower,
            actualRepayAmount
        );

        return actualRepayAmount;
    }

    /// @notice The liquidator liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @param borrower The borrower of this cToken to be liquidated
    /// @param liquidator The address repaying the borrow and seizing collateral
    /// @param cTokenCollateral The market in which to seize collateral from the borrower
    /// @param repayAmount The amount of the underlying borrowed asset to repay
    function _liquidateBorrow(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) internal interestUpdated {

        // Fail if borrower = liquidator
        if (borrower == liquidator) {
            revert SelfLiquidationNotAllowed();
        }

        // Fail if liquidate not allowed, 
        // trying to pay down too much with excessive repayAmount will revert here
        lendtroller.liquidateBorrowAllowed(
            address(this),
            address(cTokenCollateral),
            borrower,
            repayAmount
        );

        // Verify cTokenCollateral market's interest timestamp is up to date as well
        if (cTokenCollateral.accrualBlockTimestamp() != block.timestamp) {
            revert FailedFreshnessCheck();
        }

        // Fail if repayBorrow fails
        uint256 actualRepayAmount = _repayBorrow(
            liquidator,
            borrower,
            repayAmount
        );

        // We calculate the number of collateral tokens that will be seized
        uint256 seizeTokens = lendtroller.liquidateCalculateSeizeTokens(
            address(this),
            address(cTokenCollateral),
            actualRepayAmount
        );

        // Revert if borrower collateral token balance < seizeTokens
        if (cTokenCollateral.balanceOf(borrower) < seizeTokens) {
            revert ExcessiveValue();
        }

        // If this is also the collateral, run _seize to avoid re-entrancy, otherwise make an external call
        if (address(cTokenCollateral) == address(this)) {
            _seize(address(this), liquidator, borrower, seizeTokens);
        } else {
            cTokenCollateral.seize(liquidator, borrower, seizeTokens);
        }

        // We emit a LiquidateBorrow event
        emit LiquidateBorrow(
            liquidator,
            borrower,
            actualRepayAmount,
            address(cTokenCollateral),
            seizeTokens
        );
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another CToken.
    ///  Its absolutely critical to use msg.sender as the seizer cToken and not a parameter.
    /// @param seizerToken The contract seizing the collateral (i.e. borrowed cToken)
    /// @param liquidator The account receiving seized collateral
    /// @param borrower The account having collateral seized
    /// @param seizeTokens The number of cTokens to seize
    function _seize(
        address seizerToken,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) internal {
        // Fails if seize not allowed
        lendtroller.seizeAllowed(
            address(this),
            seizerToken,
            liquidator,
            borrower
        ); //, seizeTokens);

        // Fails if borrower = liquidator
        if (borrower == liquidator) {
            revert SelfLiquidationNotAllowed();
        }

        uint256 protocolSeizeTokens = (seizeTokens *
            centralRegistry.protocolLiquidationFee()) / expScale;
        uint256 protocolSeizeAmount = (exchangeRateStored() *
            protocolSeizeTokens) / expScale;
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;

        // Document new account balances with underflow check on borrower balance
        _accountData[borrower] -= _leftShiftBalance(uint216(seizeTokens));
        _accountData[liquidator] += liquidatorSeizeTokens;
        totalReserves += protocolSeizeAmount;
        totalSupply -= protocolSeizeTokens;
        
        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), borrower, seizeTokens);
        GaugePool(gaugePool()).deposit(
            address(this),
            liquidator,
            liquidatorSeizeTokens
        );

        // Emit a Transfer event
        emit Transfer(borrower, liquidator, liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), protocolSeizeTokens);
        emit ReservesAdded(
            address(this),
            protocolSeizeAmount,
            totalReserves
        );
    }

    /// @notice Handles incoming token transfers and notifies the amount received
    /// @dev This function uses the SafeTransferLib to safely perform the transfer. It doesn't support tokens with a transfer tax.
    /// @param from Address of the sender of the tokens
    /// @param amount Amount of tokens to transfer in
    /// @return Returns the amount transferred
    function doTransferIn(
        address from,
        uint256 amount
    ) internal returns (uint256) {

        /// SafeTransferLib will handle reversion from insufficient balance or allowance
        /// Note this will not support tokens with a transfer tax, which should not exist on a underlying asset anyway
        SafeTransferLib.safeTransferFrom(
            underlying,
            from,
            address(this),
            amount
        );

        return amount;
    }

    /// @notice Handles outgoing token transfers
    /// @dev This function uses the SafeTransferLib to safely perform the transfer.
    /// @param to Address receiving the token transfer 
    /// @param amount Amount of tokens to transfer out
    function doTransferOut(
        address to,
        uint256 amount
    ) internal {

        /// SafeTransferLib will handle reversion from insufficient cash held
        SafeTransferLib.safeTransfer(
            underlying,
            to,
            amount
        );

    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ICToken).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
