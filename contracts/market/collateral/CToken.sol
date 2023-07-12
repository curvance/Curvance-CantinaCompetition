// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { InterestRateModel } from "contracts/market/interestRates/InterestRateModel.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IEIP20 } from "contracts/interfaces/market/IEIP20.sol";
import { ICToken } from "contracts/interfaces/market/ICToken.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

/// @title Curvance's CToken Contract
/// @notice Abstract base for CTokens
/// @author Curvance
abstract contract CToken is ReentrancyGuard, ICToken {
    ////////// States //////////

    // Scaler for preserving floating point math precision
    uint256 internal constant expScale = 1e18;

    /// @notice Indicator that this is a CToken contract (for inspection)
    bool public constant override isCToken = true;

    /// @notice EIP-20 token name for this token
    string public name;

    /// @notice EIP-20 token symbol for this token
    string public override symbol;

    /// @notice EIP-20 token decimals for this token
    uint8 public decimals;

    // Maximum borrow rate that can ever be applied (.0005% / block)
    uint256 internal constant borrowRateMaxScaled = 0.0005e16;

    // Maximum fraction of interest that can be set aside for reserves
    uint256 internal constant reserveFactorMaxScaled = 1e18;

    /// @notice Administrator for this contract
    address payable public admin;

    /// @notice Pending administrator for this contract
    address payable public pendingAdmin;

    /// @notice Contract which oversees inter-cToken operations
    ILendtroller public override lendtroller;

    /// @notice Model which tells what the current interest rate should be
    InterestRateModel public interestRateModel;

    // Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
    uint256 internal initialExchangeRateScaled;

    /// @notice Fraction of interest currently set aside for reserves
    uint256 public reserveFactorScaled;

    /// @notice Block number that interest was last accrued at
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
    mapping(address => uint256) internal accountTokens;

    // Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint256))
        internal transferAllowances;

    /// @notice Container for borrow balance information
    /// @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
    /// @member interestIndex Global borrowIndex as of the most recent balance-changing action
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    // Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /// @notice Share of seized collateral that is added to reserves
    uint256 public constant protocolSeizeShareScaled = 2.8e16; // 2.8%

    ////////// INITIALIZATION //////////
    /// @notice Initialize the money market
    /// @param lendtroller_ The address of the Lendtroller
    /// @param interestRateModel_ The address of the interest rate model
    /// @param initialExchangeRateScaled_ The initial exchange rate, scaled by 1e18
    /// @param name_ EIP-20 name of this token
    /// @param symbol_ EIP-20 symbol of this token
    /// @param decimals_ EIP-20 decimal precision of this token
    function initialize(
        address lendtroller_,
        InterestRateModel interestRateModel_,
        uint256 initialExchangeRateScaled_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }
        if (accrualBlockTimestamp != 0 && borrowIndex != 0) {
            revert PreviouslyInitialized();
        }

        // Set initial exchange rate
        initialExchangeRateScaled = initialExchangeRateScaled_;
        if (initialExchangeRateScaled == 0) {
            revert CannotEqualZero();
        }

        // Set the lendtroller
        _setLendtroller(ILendtroller(lendtroller_));

        // Initialize block number and borrow index (block number mocks depend on lendtroller being set)
        accrualBlockTimestamp = getBlockTimestamp();
        borrowIndex = expScale;

        // Set the interest rate model (depends on block number / borrow index)
        _setInterestRateModelFresh(interestRateModel_);

        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /// @notice Returns gauge pool contract address
    /// @return gaugePool the gauge controller contract address
    function gaugePool() public view returns (address) {
        return lendtroller.gaugePool();
    }

    /// @notice Transfer `tokens` tokens from `src` to `dst` by `spender` internally
    /// @dev Called by both `transfer` and `transferFrom` internally
    /// @param spender The address of the account performing the transfer
    /// @param src The address of the source account
    /// @param dst The address of the destination account
    /// @param tokens The number of tokens to transfer
    function transferTokens(
        address spender,
        address src,
        address dst,
        uint256 tokens
    ) internal {
        // Fails if transfer not allowed
        lendtroller.transferAllowed(address(this), src, dst, tokens);

        // Do not allow self-transfers
        if (src == dst) {
            revert TransferNotAllowed();
        }

        // Get the allowance, infinite for the account owner
        uint256 startingAllowance = 0;
        if (spender == src) {
            startingAllowance = type(uint256).max;
        } else {
            startingAllowance = transferAllowances[src][spender];
        }

        // Do the calculations, checking for {under,over}flow
        uint256 allowanceNew = startingAllowance - tokens;
        uint256 srcTokensNew = accountTokens[src] - tokens;
        uint256 dstTokensNew = accountTokens[dst] + tokens;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        accountTokens[src] = srcTokensNew;
        accountTokens[dst] = dstTokensNew;

        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), src, tokens);
        GaugePool(gaugePool()).deposit(address(this), dst, tokens);

        // Eat some of the allowance (if necessary)
        if (startingAllowance != type(uint256).max) {
            transferAllowances[src][spender] = allowanceNew;
        }

        // We emit a Transfer event
        emit Transfer(src, dst, tokens);
    }

    /// @notice Transfer `amount` tokens from `msg.sender` to `dst`
    /// @param dst The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transfer(
        address dst,
        uint256 amount
    ) external override nonReentrant returns (bool) {
        transferTokens(msg.sender, msg.sender, dst, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `src` to `dst`
    /// @param src The address of the source account
    /// @param dst The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return bool true=success
    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external override nonReentrant returns (bool) {
        transferTokens(msg.sender, src, dst, amount);
        return true;
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
        address src = msg.sender;
        transferAllowances[src][spender] = amount;

        emit Approval(src, spender, amount);

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

    /// @notice Get the token balance of the `owner`
    /// @param owner The address of the account to query
    /// @return uint The number of tokens owned by `owner`
    function balanceOf(
        address owner
    ) external view override returns (uint256) {
        return accountTokens[owner];
    }

    /// @notice Get the underlying balance of the `owner`
    /// @dev This also accrues interest in a transaction
    /// @param owner The address of the account to query
    /// @return The amount of underlying owned by `owner`
    function balanceOfUnderlying(
        address owner
    ) external override returns (uint256) {
        return ((exchangeRateCurrent() * accountTokens[owner]) / expScale);
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
            accountTokens[account],
            borrowBalanceStoredInternal(account),
            exchangeRateStoredInternal()
        );
    }

    /// @dev Function to simply retrieve block number
    ///  This exists mainly for inheriting test contracts to stub this result.
    /// @return The current block number
    function getBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /// @notice Returns the current per-block borrow interest rate for this cToken
    /// @return The borrow interest rate per block, scaled by 1e18
    function borrowRatePerBlock() external view override returns (uint256) {
        return
            interestRateModel.getBorrowRate(
                getCashPrior(),
                totalBorrows,
                totalReserves
            );
    }

    /// @notice Returns the current per-block supply interest rate for this cToken
    /// @return The supply interest rate per block, scaled by 1e18
    function supplyRatePerBlock() external view override returns (uint256) {
        return
            interestRateModel.getSupplyRate(
                getCashPrior(),
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

    /// @notice Return the borrow balance of account based on stored data
    /// @param account The address whose balance should be calculated
    /// @return The calculated balance
    function borrowBalanceStored(
        address account
    ) public view override returns (uint256) {
        return borrowBalanceStoredInternal(account);
    }

    /// @notice Return the borrow balance of account based on stored data
    /// @param account The address whose balance should be calculated
    /// @return the calculated balance or 0 if no borrow balances exist
    function borrowBalanceStoredInternal(
        address account
    ) internal view returns (uint256) {
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
        return exchangeRateStoredInternal();
    }

    /// @notice Calculates the exchange rate from the underlying to the CToken
    /// @dev This function does not accrue interest before calculating the exchange rate
    /// @return exchangeRate The calculated exchange rate scaled by 1e18
    function exchangeRateStoredInternal()
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            // If there are no tokens minted:
            //  exchangeRate = initialExchangeRate
            return initialExchangeRateScaled;
        } else {
            // Otherwise:
            // exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
            uint256 totalCash = getCashPrior();
            uint256 cashPlusBorrowsMinusReserves = totalCash +
                totalBorrows -
                totalReserves;
            uint256 exchangeRate = (cashPlusBorrowsMinusReserves * expScale) /
                _totalSupply;

            return exchangeRate;
        }
    }

    /// @notice Get cash balance of this cToken in the underlying asset
    /// @return The quantity of underlying asset owned by this contract
    function getCash() external view override returns (uint256) {
        return getCashPrior();
    }

    /// @notice Applies accrued interest to total borrows and reserves
    /// @dev This calculates interest accrued from the last checkpointed block
    ///   up to the current block and writes new checkpoint to storage.
    function accrueInterest() public virtual override {
        // Remember the initial block number
        uint256 currentBlockTimestamp = getBlockTimestamp();
        uint256 accrualBlockTimestampPrior = accrualBlockTimestamp;

        // Short-circuit accumulating 0 interest
        if (accrualBlockTimestampPrior == currentBlockTimestamp) {
            return;
        }

        // Read the previous values out of storage
        uint256 cashPrior = getCashPrior();
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

        // Calculate the number of blocks elapsed since the last accrual
        uint256 blockDelta = currentBlockTimestamp -
            accrualBlockTimestampPrior;

        // Calculate the interest accumulated into borrows and reserves and the new index:
        // simpleInterestFactor = borrowRate * blockDelta
        // interestAccumulated = simpleInterestFactor * totalBorrows
        // totalBorrowsNew = interestAccumulated + totalBorrows
        // totalReservesNew = interestAccumulated * reserveFactor + totalReserves
        // borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex

        uint256 simpleInterestFactor = borrowRateScaled * blockDelta;
        uint256 interestAccumulated = (simpleInterestFactor * borrowsPrior) /
            expScale;
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 totalReservesNew = ((reserveFactorScaled *
            interestAccumulated) / expScale) + reservesPrior;
        uint256 borrowIndexNew = ((simpleInterestFactor * borrowIndexPrior) /
            expScale) + borrowIndexPrior;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We write the previously calculated values into storage
        accrualBlockTimestamp = currentBlockTimestamp;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        // We emit an AccrueInterest event
        emit AccrueInterest(
            cashPrior,
            interestAccumulated,
            borrowIndexNew,
            totalBorrowsNew
        );
    }

    /// @notice Sender supplies assets into the market and receives cTokens in exchange
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param mintAmount The amount of the underlying asset to supply
    function mintInternal(
        uint256 mintAmount,
        address recipient
    ) internal nonReentrant {
        accrueInterest();
        // mintFresh emits the actual Mint event if successful and logs on errors, so we don't need to
        mintFresh(msg.sender, mintAmount, recipient);
    }

    /// @notice User supplies assets into the market and receives cTokens in exchange
    /// @dev Assumes interest has already been accrued up to the current block
    /// @param user The address of the account which is supplying the assets
    /// @param mintAmount The amount of the underlying asset to supply
    /// @param minter The address of the account which will receive cToken
    function mintFresh(
        address user,
        uint256 mintAmount,
        address minter
    ) internal {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), minter); //, mintAmount);

        // Verify market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Exp memory exchangeRate = Exp({mantissa: exchangeRateStoredInternal()});
        uint256 exchangeRate = exchangeRateStoredInternal();

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We call `doTransferIn` for the minter and the mintAmount.
        // Note: The cToken must handle variations between ERC-20 and ETH underlying.
        // `doTransferIn` reverts if anything goes wrong, since we can't be sure if
        // side-effects occurred. The function returns the amount actually transferred,
        // in case of a fee. On success, the cToken holds an additional `actualMintAmount`
        // of cash.
        uint256 actualMintAmount = doTransferIn(user, mintAmount);

        // We get the current exchange rate and calculate the number of cTokens to be minted:
        //  mintTokens = actualMintAmount / exchangeRate

        uint256 mintTokens = (actualMintAmount * expScale) / exchangeRate;

        // We calculate the new total supply of cTokens and minter token balance, checking for overflow:
        //  totalSupplyNew = totalSupply + mintTokens
        //  accountTokensNew = accountTokens[minter] + mintTokens
        // And write them into storage
        totalSupply = totalSupply + mintTokens;
        accountTokens[minter] = accountTokens[minter] + mintTokens;

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), minter, mintTokens);

        // We emit a Mint event, and a Transfer event
        emit Mint(user, actualMintAmount, mintTokens, minter);
        emit Transfer(address(this), minter, mintTokens);
    }

    /// @notice Sender redeems cTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemTokens The number of cTokens to redeem into underlying
    function redeemInternal(uint256 redeemTokens) internal {
        accrueInterest();

        address payable redeemer = payable(msg.sender);

        uint256 exchangeRate = exchangeRateStoredInternal();
        uint256 redeemAmount = (exchangeRate * redeemTokens) / expScale;

        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        redeemFresh(redeemer, redeemTokens, redeemAmount, redeemer);
    }

    /// @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemAmount The amount of underlying to receive from redeeming cTokens
    function redeemUnderlyingInternal(uint256 redeemAmount) internal {
        accrueInterest();

        address payable redeemer = payable(msg.sender);

        // exchangeRate = invoke Exchange Rate Stored()
        uint256 exchangeRate = exchangeRateStoredInternal();
        uint256 redeemTokens = (redeemAmount * expScale) / exchangeRate;

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), redeemer, redeemTokens);

        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        redeemFresh(redeemer, redeemTokens, redeemAmount, redeemer);
    }

    function redeemUnderlyingForPositionFoldingInternal(
        address payable redeemer,
        uint256 redeemAmount,
        bytes memory params
    ) internal {
        if (msg.sender != lendtroller.positionFolding()) {
            revert FailedNotFromPositionFolding();
        }

        accrueInterest();

        // exchangeRate = invoke Exchange Rate Stored()
        uint256 exchangeRate = exchangeRateStoredInternal();
        uint256 redeemTokens = (redeemAmount * expScale) / exchangeRate;

        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        redeemFresh(redeemer, redeemTokens, redeemAmount, payable(msg.sender));

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            redeemer,
            redeemAmount,
            params
        );

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), redeemer, 0);
    }

    /// @notice User redeems cTokens in exchange for the underlying asset
    /// @dev Assumes interest has already been accrued up to the current block
    /// @param redeemer The address of the account which is redeeming the tokens
    /// @param redeemTokens The number of cTokens to redeem into underlying
    /// @param redeemAmount The number of underlying tokens to receive from redeeming cTokens
    /// @param recipient The recipient address
    function redeemFresh(
        address payable redeemer,
        uint256 redeemTokens,
        uint256 redeemAmount,
        address payable recipient
    ) internal nonReentrant {
        // Verify market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Fail gracefully if protocol has insufficient cash
        if (getCashPrior() < redeemAmount) {
            revert RedeemTransferOutNotPossible();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We write the previously calculated values into storage.
        // Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
        totalSupply = totalSupply - redeemTokens;
        accountTokens[redeemer] = accountTokens[redeemer] - redeemTokens;

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

    /// @notice Sender borrows assets from the protocol to their own address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrowInternal(uint256 borrowAmount) internal nonReentrant {
        accrueInterest();

        // Fail if borrow not allowed
        lendtroller.borrowAllowed(address(this), msg.sender, borrowAmount);

        borrowFresh(payable(msg.sender), borrowAmount, payable(msg.sender));
    }

    function borrowForPositionFoldingInternal(
        address payable borrower,
        uint256 borrowAmount,
        bytes memory params
    ) internal {
        if (msg.sender != lendtroller.positionFolding()) {
            revert FailedNotFromPositionFolding();
        }

        accrueInterest();

        borrowFresh(payable(borrower), borrowAmount, payable(msg.sender));

        IPositionFolding(msg.sender).onBorrow(
            address(this),
            borrower,
            borrowAmount,
            params
        );

        // Fail if position is not allowed
        lendtroller.borrowAllowed(address(this), borrower, 0);
    }

    /// @notice Users borrow assets from the protocol to their own address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrowFresh(
        address borrower,
        uint256 borrowAmount,
        address payable recipient
    ) internal {
        // Verify market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Fail gracefully if protocol has insufficient underlying cash
        if (getCashPrior() < borrowAmount) {
            revert BorrowCashNotAvailable();
        }

        // We calculate the new borrower and total borrow balances, failing on overflow:
        // accountBorrowNew = accountBorrow + borrowAmount
        // totalBorrowsNew = totalBorrows + borrowAmount
        uint256 accountBorrowsPrev = borrowBalanceStoredInternal(borrower);
        uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint256 totalBorrowsNew = totalBorrows + borrowAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We write the previously calculated values into storage.
        // Note: Avoid token reentrancy attacks by writing increased borrow before external transfer.
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        // We invoke doTransferOut for the borrower and the borrowAmount.
        // Note: The cToken must handle variations between ERC-20 and ETH underlying.
        // On success, the cToken borrowAmount less of cash.
        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(recipient, borrowAmount);

        // We emit a Borrow event
        emit Borrow(
            borrower,
            borrowAmount,
            accountBorrowsNew,
            totalBorrowsNew
        );
    }

    /// @notice Sender repays their own borrow
    /// @param repayAmount The amount to repay, or -1 for the full outstanding amount
    function repayBorrowInternal(uint256 repayAmount) internal nonReentrant {
        accrueInterest();
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /// @notice Sender repays a borrow belonging to borrower
    /// @param borrower the account with the debt being payed off
    /// @param repayAmount The amount to repay, or -1 for the full outstanding amount
    function repayBorrowBehalfInternal(
        address borrower,
        uint256 repayAmount
    ) internal nonReentrant {
        accrueInterest();
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    /// @notice Borrows are repaid by another user (possibly the borrower).
    /// @param payer the account paying off the borrow
    /// @param borrower the account with the debt being payed off
    /// @param repayAmount the amount of underlying tokens being returned, or -1 for the full outstanding amount
    /// @return (uint) the actual repayment amount.
    function repayBorrowFresh(
        address payer,
        address borrower,
        uint256 repayAmount
    ) internal returns (uint256) {
        // Fail if repayBorrow not allowed
        lendtroller.repayBorrowAllowed(address(this), borrower); //, payer, repayAmount);

        // Verify market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // We fetch the amount the borrower owes, with accumulated interest
        uint256 accountBorrowsPrev = borrowBalanceStoredInternal(borrower);

        // If repayAmount == -1, repayAmount = accountBorrows
        uint256 repayAmountFinal = repayAmount == type(uint256).max
            ? accountBorrowsPrev
            : repayAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We call doTransferIn for the payer and the repayAmount
        // Note: The cToken must handle variations between ERC-20 and ETH underlying.
        // On success, the cToken holds an additional repayAmount of cash.
        // doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
        //  it returns the amount actually transferred, in case of a fee.
        uint256 actualRepayAmount = doTransferIn(payer, repayAmountFinal);

        // We calculate the new borrower and total borrow balances, failing on underflow:
        // accountBorrowsNew = accountBorrows - actualRepayAmount
        // totalBorrowsNew = totalBorrows - actualRepayAmount
        uint256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
        uint256 totalBorrowsNew = totalBorrows - actualRepayAmount;

        // We write the previously calculated values into storage
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        // We emit a RepayBorrow event
        emit RepayBorrow(
            payer,
            borrower,
            actualRepayAmount,
            accountBorrowsNew,
            totalBorrowsNew
        );

        return actualRepayAmount;
    }

    /// @notice The sender liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @param borrower The borrower of this cToken to be liquidated
    /// @param cTokenCollateral The market in which to seize collateral from the borrower
    /// @param repayAmount The amount of the underlying borrowed asset to repay
    function liquidateBorrowInternal(
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) internal nonReentrant {
        // Accrue interest in both locations
        accrueInterest();

        cTokenCollateral.accrueInterest();

        liquidateBorrowFresh(
            msg.sender,
            borrower,
            repayAmount,
            cTokenCollateral
        );
    }

    /// @notice The liquidator liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @param borrower The borrower of this cToken to be liquidated
    /// @param liquidator The address repaying the borrow and seizing collateral
    /// @param cTokenCollateral The market in which to seize collateral from the borrower
    /// @param repayAmount The amount of the underlying borrowed asset to repay
    function liquidateBorrowFresh(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) internal {
        // Fail if liquidate not allowed
        lendtroller.liquidateBorrowAllowed(
            address(this),
            address(cTokenCollateral),
            borrower,
            repayAmount
        );

        // Verify market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Verify cTokenCollateral market's block number equals current block number
        if (cTokenCollateral.accrualBlockTimestamp() != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Fail if borrower = liquidator
        if (borrower == liquidator) {
            revert SelfLiquidationNotAllowed();
        }

        // Fail if repayAmount = 0
        if (repayAmount == 0) {
            revert CannotEqualZero();
        }

        // Fail if repayAmount = -1
        if (repayAmount == type(uint256).max) {
            revert ExcessiveValue();
        }

        // Fail if repayBorrow fails
        uint256 actualRepayAmount = repayBorrowFresh(
            liquidator,
            borrower,
            repayAmount
        );

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

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

        // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
        if (address(cTokenCollateral) == address(this)) {
            seizeInternal(address(this), liquidator, borrower, seizeTokens);
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
    /// @dev Will fail unless called by another cToken during the process of liquidation.
    ///  Its absolutely critical to use msg.sender as the borrowed cToken and not a parameter.
    /// @param liquidator The account receiving seized collateral
    /// @param borrower The account having collateral seized
    /// @param seizeTokens The number of cTokens to seize
    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external override nonReentrant {
        seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another CToken.
    ///  Its absolutely critical to use msg.sender as the seizer cToken and not a parameter.
    /// @param seizerToken The contract seizing the collateral (i.e. borrowed cToken)
    /// @param liquidator The account receiving seized collateral
    /// @param borrower The account having collateral seized
    /// @param seizeTokens The number of cTokens to seize
    function seizeInternal(
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

        // We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
        // borrowerTokensNew = accountTokens[borrower] - seizeTokens
        // liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
        uint256 protocolSeizeTokens = (seizeTokens *
            protocolSeizeShareScaled) / expScale;
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;
        uint256 protocolSeizeAmount = (exchangeRateStoredInternal() *
            protocolSeizeTokens) / expScale;
        uint256 totalReservesNew = totalReserves + protocolSeizeAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We write the calculated values into storage
        totalReserves = totalReservesNew;
        totalSupply = totalSupply - protocolSeizeTokens;
        accountTokens[borrower] = accountTokens[borrower] - seizeTokens;
        accountTokens[liquidator] =
            accountTokens[liquidator] +
            liquidatorSeizeTokens;

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
            totalReservesNew
        );
    }

    /// Admin Functions

    /// @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
    /// @dev Admin function to begin change of admin.
    ///  The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
    /// @param newPendingAdmin New pending admin.
    function _setPendingAdmin(
        address payable newPendingAdmin
    ) external override {
        // Check caller = admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /// @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
    /// @dev Admin function for pending admin to accept role and update admin
    function _acceptAdmin() external override {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        if (msg.sender != pendingAdmin || msg.sender == address(0)) {
            revert AddressUnauthorized();
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = payable(address(0));

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    /// @notice Sets a new lendtroller for the market
    /// @dev Admin function to set a new lendtroller
    /// @param newLendtroller New lendtroller address.
    function _setLendtroller(ILendtroller newLendtroller) public override {
        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

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
    function _setReserveFactor(
        uint256 newReserveFactorScaled
    ) external override nonReentrant {
        accrueInterest();
        // _setReserveFactorFresh emits reserve-factor-specific logs & reverts, so we don't need to.
        _setReserveFactorFresh(newReserveFactorScaled);
    }

    /// @notice Sets a new reserve factor for the protocol (*requires fresh interest accrual)
    /// @dev Admin function to set a new reserve factor
    /// @param newReserveFactorScaled The new reserve factore * 1e18 (ie, 0.8 == 800000000000000000)
    function _setReserveFactorFresh(uint256 newReserveFactorScaled) internal {
        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Verify market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Check newReserveFactor ≤ maxReserveFactor
        if (newReserveFactorScaled > reserveFactorMaxScaled) {
            revert ExcessiveValue();
        }

        uint256 oldReserveFactorScaled = reserveFactorScaled;
        reserveFactorScaled = newReserveFactorScaled;

        emit NewReserveFactor(oldReserveFactorScaled, newReserveFactorScaled);
    }

    /// @notice Accrues interest and reduces reserves by transferring from msg.sender
    /// @param addAmount Amount of addition to reserves
    function _addReservesInternal(uint256 addAmount) internal nonReentrant {
        accrueInterest();

        // _addReservesFresh emits reserve-addition-specific logs & reverts, so we don't need to.
        _addReservesFresh(addAmount);
    }

    /// @notice Add reserves by transferring from caller
    /// @dev Requires fresh interest accrual
    /// @param addAmount Amount of addition to reserves
    /// return uint the actual amount added, net token fees
    function _addReservesFresh(uint256 addAmount) internal {
        // We fail gracefully unless market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We call doTransferIn for the caller and the addAmount
        // Note: The cToken must handle variations between ERC-20 and ETH underlying.
        // On success, the cToken holds an additional addAmount of cash.
        // doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
        // it returns the amount actually transferred, in case of a fee.
        totalReserves += doTransferIn(msg.sender, addAmount);

        // Emit NewReserves(admin, actualAddAmount, reserves[n+1])
        // emit ReservesAdded(msg.sender, actualAddAmount, totalReserves); /// changed to emit correct variable
        emit ReservesAdded(msg.sender, addAmount, totalReserves);
    }

    /// @notice Accrues interest and reduces reserves by transferring to admin
    /// @param reduceAmount Amount of reduction to reserves
    function _reduceReserves(
        uint256 reduceAmount
    ) external override nonReentrant {
        accrueInterest();
        // _reduceReservesFresh emits reserve-reduction-specific logs on errors, so we don't need to.
        _reduceReservesFresh(reduceAmount);
    }

    /// @notice Reduces reserves by transferring to admin
    /// @dev Requires fresh interest accrual
    /// @param reduceAmount Amount of reduction to reserves
    function _reduceReservesFresh(uint256 reduceAmount) internal {
        // totalReserves - reduceAmount
        uint256 totalReservesNew;

        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // We fail gracefully unless market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Fail gracefully if protocol has insufficient underlying cash
        if (getCashPrior() < reduceAmount) {
            revert ReduceReservesCashNotAvailable();
        }

        // Check reduceAmount ≤ reserves[n] (totalReserves)
        if (reduceAmount > totalReserves) {
            revert ReduceReservesCashValidation();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        totalReservesNew = totalReserves - reduceAmount;

        // Store reserves[n+1] = reserves[n] - reduceAmount
        totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(admin, reduceAmount);

        emit ReservesReduced(admin, reduceAmount, totalReservesNew);
    }

    /// @notice accrues interest and updates the interest rate model using _setInterestRateModelFresh
    /// @dev Admin function to accrue interest and update the interest rate model
    /// @param newInterestRateModel the new interest rate model to use
    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) public override {
        accrueInterest();
        // _setInterestRateModelFresh emits interest-rate-model-update-specific logs & reverts, so we don't need to.
        _setInterestRateModelFresh(newInterestRateModel);
    }

    /// @notice updates the interest rate model (*requires fresh interest accrual)
    /// @dev Admin function to update the interest rate model
    /// @param newInterestRateModel the new interest rate model to use
    function _setInterestRateModelFresh(
        InterestRateModel newInterestRateModel
    ) internal {
        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // We fail gracefully unless market's block number equals current block number
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            revert FailedFreshnessCheck();
        }

        // Track the market's current interest rate model
        InterestRateModel oldInterestRateModel = interestRateModel;

        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        if (!newInterestRateModel.isInterestRateModel()) {
            revert ValidationFailed();
        }

        // Set the interest rate model to newInterestRateModel
        interestRateModel = newInterestRateModel;

        // Emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel)
        emit NewMarketInterestRateModel(
            oldInterestRateModel,
            newInterestRateModel
        );
    }

    /// Safe Token

    /// @notice Gets balance of this contract in terms of the underlying
    /// @dev This excludes the value of the current message, if any
    /// @return The quantity of underlying owned by this contract
    function getCashPrior() internal view virtual returns (uint256);

    /// @dev Performs a transfer in, reverting upon failure.
    ///  Returns the amount actually transferred to the protocol, in case of a fee.
    ///  This may revert due to insufficient balance or insufficient allowance.
    function doTransferIn(
        address from,
        uint256 amount
    ) internal virtual returns (uint256);

    /// @dev Performs a transfer out, ideally returning an explanatory error code upon failure rather than reverting.
    ///  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
    ///  If caller has checked protocol's balance, and verified it is >= amount,
    ///      this should not revert in normal conditions.
    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal virtual;
}
