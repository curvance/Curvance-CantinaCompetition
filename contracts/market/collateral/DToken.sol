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
import { IMToken, accountSnapshot } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance's Debt Token Contract
contract DToken is IERC20, ERC165, ReentrancyGuard {
    /// TYPES ///

    struct BorrowSnapshot {
        /// principal total balance (with accrued interest),
        /// after applying the most recent balance-changing action
        uint256 principal;
        /// Global borrowIndex as of the most recent balance-changing action
        uint256 interestIndex;
    }

    /// CONSTANTS ///

    /// @notice Scalar for math
    uint256 internal constant expScale = 1e18;

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

    /// @notice last accrued interest timestamp
    uint256 public accrualBlockTimestamp;

    /// @notice Multiplier ratio of total interest accrued
    uint256 public borrowIndex;

    /// @notice Total outstanding borrows of underlying
    uint256 public totalBorrows;

    /// @notice Total protocol reserves of underlying
    uint256 public totalReserves;

    /// @notice Total number of tokens in circulation
    uint256 public totalSupply;

    // account => token balance
    mapping(address => uint256) internal _accountBalance;

    // account => spender => approved amount
    mapping(address => mapping(address => uint256))
        internal transferAllowances;

    // account => BorrowSnapshot (Principal Borrowed, User Interest Index)
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /// EVENTS ///

    event AccrueInterest(
        uint256 cashPrior,
        uint256 interestAccumulated,
        uint256 borrowIndex,
        uint256 totalBorrows
    );
    event Mint(
        address user,
        uint256 mintAmount,
        uint256 mintTokens,
        address minter
    );
    event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    event Borrow(address borrower, uint256 borrowAmount);
    event Repay(address payer, address borrower, uint256 repayAmount);
    event Liquidated(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address cTokenCollateral,
        uint256 seizeTokens
    );
    event NewLendtroller(address oldLendtroller, address newLendtroller);
    event NewMarketInterestRateModel(
        address oldInterestRateModel,
        address newInterestRateModel
    );
    event ReservesAdded(
        address daoAddress,
        uint256 addAmount,
        uint256 newTotalReserves
    );
    event ReservesReduced(
        address daoAddress,
        uint256 reduceAmount,
        uint256 newTotalReserves
    );

    /// ERRORS ///

    error DToken__UnauthorizedCaller();
    error DToken__CannotEqualZero();
    error DToken__ExcessiveValue();
    error DToken__TransferNotAllowed();
    error DToken__CashNotAvailable();
    error DToken__ValidationFailed();
    error DToken__CentralRegistryIsInvalid();
    error DToken__LendtrollerIsInvalid();
    error DToken__InterestRateModelIsInvalid();

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
            revert DToken__CentralRegistryIsInvalid();
        }

        centralRegistry = centralRegistry_;

        if (!centralRegistry_.isLendingMarket(lendtroller_)) {
            revert DToken__ValidationFailed();
        }

        _setLendtroller(lendtroller_);

        // Initialize timestamp and borrow index (timestamp mocks depend on lendtroller being set)
        accrualBlockTimestamp = block.timestamp;
        borrowIndex = expScale;

        _setInterestRateModel(interestRateModel_);

        underlying = underlying_;
        name = string.concat(
            "Curvance interest bearing ",
            IERC20(underlying_).name()
        );
        symbol = string.concat("c", IERC20(underlying_).symbol());

        // Sanity check underlying so that we know users will not need to mint anywhere close to exchange rate of 1e18
        require(
            IERC20(underlying).totalSupply() < type(uint232).max,
            "DToken: Underlying token assumptions not met"
        );
    }

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

        uint256 mintAmount = 42069;
        uint256 actualMintAmount = _doTransferIn(initializer, mintAmount);
        // We do not need to calculate exchange rate here as we will always be the initial depositer
        // These values should always be zero but we will add them just incase we are re-initiating a market
        totalSupply = totalSupply + actualMintAmount;
        _accountBalance[initializer] =
            _accountBalance[initializer] +
            actualMintAmount;

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(
            address(this),
            initializer,
            actualMintAmount
        );

        // We emit a Mint event, and a Transfer event
        emit Mint(
            initializer,
            actualMintAmount,
            actualMintAmount,
            initializer
        );
        emit Transfer(address(this), initializer, 6942069);
        return true;
    }

    /// @notice Transfer `amount` tokens from `msg.sender` to `to`
    /// @param to The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transfer(
        address to,
        uint256 amount
    ) external override nonReentrant returns (bool) {
        _transferTokens(msg.sender, msg.sender, to, amount);
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
        _transferTokens(msg.sender, from, to, amount);
        return true;
    }

    /// @notice Sender borrows assets from the protocol to their own address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrow(uint256 borrowAmount) external nonReentrant {
        accrueInterest();

        // Reverts if borrow not allowed
        lendtroller.borrowAllowedWithNotify(
            address(this),
            msg.sender,
            borrowAmount
        );

        _borrow(payable(msg.sender), borrowAmount, payable(msg.sender));
    }

    /// @notice Position folding contract will call this function
    /// @param user The user address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrowForPositionFolding(
        address payable user,
        uint256 borrowAmount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert DToken__UnauthorizedCaller();
        }

        accrueInterest();
        // Record that the user borrowed before everything else is updated
        lendtroller.notifyAccountBorrow(user);

        _borrow(user, borrowAmount, payable(msg.sender));

        IPositionFolding(msg.sender).onBorrow(
            address(this),
            user,
            borrowAmount,
            params
        );

        // Fail if position is not allowed, after position folding has re-invested
        lendtroller.borrowAllowed(address(this), user, 0);
    }

    /// @notice Sender repays their own borrow
    /// @param repayAmount The amount to repay, or 0 for the full outstanding amount
    function repay(uint256 repayAmount) external nonReentrant {
        accrueInterest();

        _repay(msg.sender, msg.sender, repayAmount);
    }

    function repayForPositionFolding(
        address user,
        uint256 repayAmount
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert DToken__UnauthorizedCaller();
        }

        accrueInterest();

        _repay(msg.sender, user, repayAmount);
    }

    /// @notice Allows liquidation of a borrower's collateral,
    ///         Transferring the liquidated collateral to the liquidator
    /// @param borrower The address of the borrower to be liquidated
    /// @param repayAmount The amount of underlying asset the liquidator wishes to repay
    /// @param mTokenCollateral The market in which to seize collateral from the borrower
    function liquidateUser(
        address borrower,
        uint256 repayAmount,
        IMToken mTokenCollateral
    ) external nonReentrant {
        accrueInterest();

        _liquidateUser(msg.sender, borrower, repayAmount, mTokenCollateral);
    }

    /// @notice Sender redeems dTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param tokensToRedeem The number of dTokens to redeem into underlying
    function redeem(uint256 tokensToRedeem) external nonReentrant {
        accrueInterest();

        _redeem(
            payable(msg.sender),
            tokensToRedeem,
            (exchangeRateStored() * tokensToRedeem) / expScale,
            payable(msg.sender)
        );
    }

    /// @notice Sender redeems dTokens in exchange for a specified amount of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemAmount The amount of underlying to redeem
    function redeemUnderlying(uint256 redeemAmount) external nonReentrant {
        accrueInterest();

        uint256 tokensToRedeem = (redeemAmount * expScale) /
            exchangeRateStored();

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), msg.sender, tokensToRedeem);

        _redeem(
            payable(msg.sender),
            tokensToRedeem,
            redeemAmount,
            payable(msg.sender)
        );
    }

    /// @notice Helper function for Position Folding contract to redeem underlying tokens
    /// @param user The user address
    /// @param tokensToRedeem The amount of the underlying asset to redeem
    function redeemUnderlyingForPositionFolding(
        address payable user,
        uint256 tokensToRedeem,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert DToken__UnauthorizedCaller();
        }

        accrueInterest();

        _redeem(
            user,
            (tokensToRedeem * expScale) / exchangeRateStored(),
            tokensToRedeem,
            payable(msg.sender)
        );

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            user,
            tokensToRedeem,
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
    /// @param addAmount The amount of underlying token to add as reserves
    function depositReserves(
        uint256 addAmount
    ) external nonReentrant onlyDaoPermissions {
        accrueInterest();

        // On success, the market will deposit `addAmount` to the market adding more cash
        totalReserves = totalReserves + _doTransferIn(msg.sender, addAmount);
        // Query current DAO operating address
        address daoAddress = centralRegistry.daoAddress();
        // Deposit new reserves into gauge
        GaugePool(gaugePool()).deposit(address(this), daoAddress, addAmount);

        emit ReservesAdded(daoAddress, addAmount, totalReserves);
    }

    /// @notice Reduces reserves by withdrawing from the gauge and transferring to Curvance DAO
    /// @dev If daoAddress is going to be moved all reserves should be withdrawn first
    /// @param reduceAmount Amount of reserves to withdraw
    function withdrawReserves(
        uint256 reduceAmount
    ) external nonReentrant onlyDaoPermissions {
        accrueInterest();

        // Make sure we have enough cash to cover withdrawal
        if (getCash() < reduceAmount) {
            revert DToken__CashNotAvailable();
        }

        // Need underflow check to check if we have sufficient totalReserves
        totalReserves = totalReserves - reduceAmount;

        // Query current DAO operating address
        address daoAddress = centralRegistry.daoAddress();
        // Withdraw reserves from gauge
        GaugePool(gaugePool()).withdraw(
            address(this),
            daoAddress,
            reduceAmount
        );

        // _doTransferOut reverts if anything goes wrong
        _doTransferOut(daoAddress, reduceAmount);

        emit ReservesReduced(daoAddress, reduceAmount, totalReserves);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        transferAllowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return transferAllowances[owner][spender];
    }

    /// @notice Reserve fee is in basis point form
    /// @dev Returns the protocols current interest rate fee to fill reserves
    function reserveFee() public view returns (uint256) {
        return centralRegistry.protocolInterestRateFee();
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
                "DToken: insufficient balance"
            );
            (bool success, ) = payable(daoOperator).call{ value: amount }("");
            require(success, "DToken: !successful");
        } else {
            require(token != underlying, "DToken: cannot withdraw underlying");
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "DToken: insufficient balance"
            );
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
    /// @dev Admin function to accrue interest and update the interest rate model
    /// @param newInterestRateModel the new interest rate model to use
    function setInterestRateModel(
        address newInterestRateModel
    ) external onlyElevatedPermissions {
        accrueInterest();

        _setInterestRateModel(newInterestRateModel);
    }

    /// @notice Get the underlying balance of the `account`
    /// @dev This also accrues interest in a transaction
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlying(address account) external returns (uint256) {
        return ((exchangeRateCurrent() * balanceOf(account)) / expScale);
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
            balanceOf(account),
            borrowBalanceStored(account),
            exchangeRateStored()
        );
    }

    /// @notice Get a snapshot of the dToken and `account` data
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    function getAccountSnapshotPacked(
        address account
    ) external view returns (accountSnapshot memory) {
        return (
            accountSnapshot({
                asset: IMToken(address(this)),
                tokenType: 0,
                mTokenBalance: balanceOf(account),
                borrowBalance: borrowBalanceStored(account),
                exchangeRateScaled: exchangeRateStored()
            })
        );
    }

    /// @notice Returns the current per-second borrow interest rate for this dToken
    /// @return The borrow interest rate per second, scaled by 1e18
    function borrowRatePerSecond() external view returns (uint256) {
        return
            interestRateModel.getBorrowRate(
                getCash(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current per-second supply interest rate for this dToken
    /// @return The supply interest rate per second, scaled by 1e18
    function supplyRatePerSecond() external view returns (uint256) {
        return
            interestRateModel.getSupplyRate(
                getCash(),
                totalBorrows,
                totalReserves,
                reserveFee()
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

    /// PUBLIC FUNCTINOS ///

    /// @notice Get the token balance of the `account`
    /// @param account The address of the account to query
    /// @return balance The number of tokens owned by `account`
    // @dev Returns the balance of tokens for `account`
    function balanceOf(
        address account
    ) public view override returns (uint256) {
        return _accountBalance[account];
    }

    /// @notice Return the borrow balance of account based on stored data
    /// @param account The address whose balance should be calculated
    /// @return The calculated balance
    function borrowBalanceStored(
        address account
    ) public view returns (uint256) {
        // Cache borrow data to save gas
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        // If borrowBalance = 0 then borrowIndex is likely also 0
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        // Calculate new borrow balance using the interest index:
        // borrowBalanceStored = borrower.principal * DToken.borrowIndex / borrower.interestIndex
        return
            (borrowSnapshot.principal * borrowIndex) /
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
            ((getCash() + totalBorrows - totalReserves) * expScale) /
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
    /// @dev This calculates interest accrued from the last checkpointed second
    ///   up to the current second and writes new checkpoint to storage.
    function accrueInterest() public {
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

        // Calculate the interest accumulated into borrows and reserves and the new index:
        // simpleInterestFactor = borrowRate * (block.timestamp - accrualBlockTimestampPrior)
        // interestAccumulated = simpleInterestFactor * totalBorrows
        // totalBorrowsNew = interestAccumulated + totalBorrows
        // borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex

        uint256 simpleInterestFactor = borrowRateScaled *
            (block.timestamp - accrualBlockTimestampPrior);
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
        totalReserves =
            ((reserveFee() * interestAccumulated) / expScale) +
            reservesPrior;

        // We emit an AccrueInterest event
        emit AccrueInterest(
            cashPrior,
            interestAccumulated,
            borrowIndexNew,
            totalBorrowsNew
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Sets a new lendtroller for the market
    /// @dev Admin function to set a new lendtroller
    /// @param newLendtroller New lendtroller address
    function _setLendtroller(address newLendtroller) internal {
        // Ensure that lendtroller parameter is a lendtroller
        if (
            !ERC165Checker.supportsInterface(
                newLendtroller,
                type(ILendtroller).interfaceId
            )
        ) {
            revert DToken__LendtrollerIsInvalid();
        }

        // Cache the current lendtroller to save gas
        address oldLendtroller = address(lendtroller);

        // Set new lendtroller
        lendtroller = ILendtroller(newLendtroller);

        emit NewLendtroller(oldLendtroller, newLendtroller);
    }

    /// @notice accrues interest and updates the interest rate model
    /// @dev Admin function to accrue interest and update the interest rate model
    /// @param newInterestRateModel the new interest rate model to use
    function _setInterestRateModel(address newInterestRateModel) internal {
        // Ensure we are switching to an actual Interest Rate Model
        if (!InterestRateModel(newInterestRateModel).isInterestRateModel()) {
            revert DToken__InterestRateModelIsInvalid();
        }

        // Cache the current interest rate model to save gas
        address oldInterestRateModel = address(interestRateModel);

        // Set new interest rate model
        interestRateModel = InterestRateModel(newInterestRateModel);

        emit NewMarketInterestRateModel(
            oldInterestRateModel,
            newInterestRateModel
        );
    }

    /// @notice Transfer `tokens` tokens from `from` to `to` by `spender` internally
    /// @dev Called by both `transfer` and `transferFrom` internally
    /// @param spender The address of the account performing the transfer
    /// @param from The address of the source account
    /// @param to The address of the destination account
    /// @param tokens The number of tokens to transfer
    function _transferTokens(
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
            transferAllowances[from][spender] =
                transferAllowances[from][spender] -
                tokens;
        }

        // Update token balances
        _accountBalance[from] = _accountBalance[from] - tokens;
        /// We know that from balance wont overflow due to totalSupply check in constructor and underflow check above
        unchecked {
            _accountBalance[to] = _accountBalance[to] + tokens;
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
    /// @param mintAmount The amount of the underlying asset to supply
    function _mint(
        address user,
        address recipient,
        uint256 mintAmount
    ) internal {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), recipient);

        uint256 exchangeRate = exchangeRateStored();
        // The function returns the amount actually transferred, in case of a fee
        // On success, the dToken holds an additional `actualMintAmount` of cash
        uint256 actualMintAmount = _doTransferIn(user, mintAmount);

        // We get the current exchange rate and calculate the number of dTokens to be minted:
        //  mintTokens = actualMintAmount / exchangeRate
        uint256 mintTokens = (actualMintAmount * expScale) / exchangeRate;

        unchecked {
            totalSupply = totalSupply + mintTokens;
            /// Calculate their new balance
            _accountBalance[recipient] =
                _accountBalance[recipient] +
                mintTokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), recipient, mintTokens);

        // We emit a Mint event, and a Transfer event
        emit Mint(user, actualMintAmount, mintTokens, recipient);
        emit Transfer(address(this), recipient, mintTokens);
    }

    /// @notice User redeems dTokens in exchange for the underlying asset
    /// @dev Assumes interest has already been accrued up to the current timestamp
    /// @param redeemer The address of the account which is redeeming the tokens
    /// @param redeemTokens The number of dTokens to redeem into underlying
    /// @param redeemAmount The number of underlying tokens to receive from redeeming dTokens
    /// @param recipient The recipient address
    function _redeem(
        address payable redeemer,
        uint256 redeemTokens,
        uint256 redeemAmount,
        address payable recipient
    ) internal {
        // Check if we have enough cash to support the redeem
        if (getCash() < redeemAmount) {
            revert DToken__CashNotAvailable();
        }

        // Validate redemption parameters
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert DToken__CannotEqualZero();
        }

        _accountBalance[redeemer] = _accountBalance[redeemer] - redeemTokens;
        // We have user underflow check above so we do not need a redundant check here
        unchecked {
            totalSupply = totalSupply - redeemTokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), redeemer, redeemTokens);

        // We invoke _doTransferOut for the redeemer and the redeemAmount.
        // On success, the dToken has redeemAmount less of cash.
        _doTransferOut(recipient, redeemAmount);

        // We emit a Transfer event, and a Redeem event
        emit Transfer(redeemer, address(this), redeemTokens);
        emit Redeem(redeemer, redeemAmount, redeemTokens);
    }

    /// @notice Users borrow assets from the protocol to their own address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function _borrow(
        address borrower,
        uint256 borrowAmount,
        address payable recipient
    ) internal {
        // Check if we have enough cash to support the borrow
        if (getCash() < borrowAmount) {
            revert DToken__CashNotAvailable();
        }

        // We calculate the new borrower and total borrow balances, failing on overflow:
        accountBorrows[borrower].principal =
            borrowBalanceStored(borrower) +
            borrowAmount;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrows + borrowAmount;

        // _doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        _doTransferOut(recipient, borrowAmount);

        // We emit a Borrow event
        emit Borrow(borrower, borrowAmount);
    }

    /// @notice Allows a payer to repay a loan on behalf of the borrower, usually themselves
    /// @dev First validates that the payer is allowed to repay the loan, then repays
    ///      the loan by transferring in the repay amount. Emits a repay event on
    ///      successful repayment.
    /// @param payer The address paying off the borrow
    /// @param borrower The account with the debt being paid off
    /// @param repayAmount The amount the payer wishes to repay, or 0 for the full outstanding amount
    /// @return actualRepayAmount The actual amount repaid
    function _repay(
        address payer,
        address borrower,
        uint256 repayAmount
    ) internal returns (uint256) {
        // Validate that the payer is allowed to repay the loan
        lendtroller.repayAllowed(address(this), borrower);

        // Cache how much the borrower has to save gas
        uint256 accountBorrowsPrev = borrowBalanceStored(borrower);

        // If repayAmount == uint max, repayAmount = accountBorrows
        uint256 repayAmountFinal = repayAmount == 0
            ? accountBorrowsPrev
            : repayAmount;

        // We call _doTransferIn for the payer and the repayAmount
        // Note: On success, the dToken holds an additional repayAmount of cash.
        //       it returns the amount actually transferred, in case of a fee.
        uint256 actualRepayAmount = _doTransferIn(payer, repayAmountFinal);

        // We calculate the new borrower and total borrow balances, failing on underflow:
        accountBorrows[borrower].principal =
            accountBorrowsPrev -
            actualRepayAmount;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows -= actualRepayAmount;

        // We emit a Repay event
        emit Repay(payer, borrower, actualRepayAmount);

        return actualRepayAmount;
    }

    /// @notice The liquidator liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @param borrower The borrower of this dToken to be liquidated
    /// @param liquidator The address repaying the borrow and seizing collateral
    /// @param mTokenCollateral The market in which to seize collateral from the borrower
    /// @param repayAmount The amount of the underlying borrowed asset to repay
    function _liquidateUser(
        address liquidator,
        address borrower,
        uint256 repayAmount,
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
        lendtroller.liquidateUserAllowed(
            address(this),
            address(mTokenCollateral),
            borrower,
            repayAmount
        );

        // Fail if repay fails
        uint256 actualRepayAmount = _repay(liquidator, borrower, repayAmount);

        // We calculate the number of collateral tokens that will be seized
        uint256 seizeTokens = lendtroller.liquidateCalculateSeizeTokens(
            address(this),
            address(mTokenCollateral),
            actualRepayAmount
        );

        // Revert if borrower collateral token balance < seizeTokens
        if (mTokenCollateral.balanceOf(borrower) < seizeTokens) {
            revert DToken__ExcessiveValue();
        }

        // We check above that the mToken must be a collateral token,
        // so we cant be seizing this mToken as it is a debt token,
        // so there is no reEntry risk
        mTokenCollateral.seize(liquidator, borrower, seizeTokens);

        // We emit a Liquidated event
        emit Liquidated(
            liquidator,
            borrower,
            actualRepayAmount,
            address(mTokenCollateral),
            seizeTokens
        );
    }

    /// @notice Handles incoming token transfers and notifies the amount received
    /// @dev This function uses the SafeTransferLib to safely perform the transfer. It doesn't support tokens with a transfer tax.
    /// @param from Address of the sender of the tokens
    /// @param amount Amount of tokens to transfer in
    /// @return Returns the amount transferred
    function _doTransferIn(
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
    function _doTransferOut(address to, uint256 amount) internal {
        /// SafeTransferLib will handle reversion from insufficient cash held
        SafeTransferLib.safeTransfer(underlying, to, amount);
    }
}
