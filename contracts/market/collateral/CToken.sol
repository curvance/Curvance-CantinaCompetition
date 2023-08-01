// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ERC165 } from "contracts/libraries/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { BasePositionVault } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance's Collateral Token Contract
contract CToken is ERC165, ReentrancyGuard {
    /// CONSTANTS ///

    uint256 internal constant expScale = 1e18;

    /// @notice Indicator that this is a CToken contract (for inspection)
    bool public constant isCToken = true;

    /// @notice Underlying asset for this CToken
    address public immutable underlying;

    /// @notice Decimals for this CToken
    uint8 public immutable decimals;

    ICentralRegistry public immutable centralRegistry;

    /// Errors ///

    error FailedNotFromPositionFolding();
    error CannotEqualZero();
    error TransferNotAllowed();
    error RedeemTransferOutNotPossible();
    error SelfLiquidationNotAllowed();
    error LendtrollerMismatch();
    error ValidationFailed();
    error ReduceReservesCashNotAvailable();

    /// EVENTS ///

    /// @notice Event emitted when the vault migrated
    event MigrateVault(address oldVault, address newVault);

    /// @notice Event emitted when tokens are minted
    event Mint(
        address user,
        uint256 mintAmount,
        uint256 mintTokens,
        address minter
    );

    /// @notice Event emitted when tokens are redeemed
    event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    /// @notice Event emitted when a borrow is liquidated
    event Liquidated(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address cTokenCollateral,
        uint256 seizeTokens
    );

    /// @notice Event emitted when lendtroller is changed
    event NewLendtroller(
        ILendtroller oldLendtroller,
        ILendtroller newLendtroller
    );

    /// @notice Event emitted when the reserves are added
    event ReservesAdded(
        address benefactor,
        uint256 addAmount,
        uint256 newTotalReserves
    );

    /// @notice Event emitted when the reserves are reduced
    event ReservesReduced(
        address admin,
        uint256 reduceAmount,
        uint256 newTotalReserves
    );

    /// @notice ERC20 Transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice ERC20 Approval event
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// STORAGE ///
    string public name;
    string public symbol;
    ILendtroller public lendtroller;
    BasePositionVault public vault;
    /// @notice Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
    uint256 internal initialExchangeRateScaled;
    /// @notice Total amount of reserves of the underlying held in this market
    uint256 public totalReserves;
    /// @notice Total number of tokens in circulation
    uint256 public totalSupply;

    // @notice account => token balance
    mapping(address => uint256) internal _accountBalance;

    // @notice account => spender => approved amount
    mapping(address => mapping(address => uint256))
        internal transferAllowances;

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

    /// @param centralRegistry_ The address of Curvances Central Registry
    /// @param underlying_ The address of the underlying asset
    /// @param lendtroller_ The address of the Lendtroller
    /// @param initialExchangeRateScaled_ The initial exchange rate, scaled by 1e18
    /// @param name_ ERC-20 name of this token
    constructor(
        ICentralRegistry centralRegistry_,
        address underlying_,
        address lendtroller_,
        address vault_,
        uint256 initialExchangeRateScaled_,
        string memory name_
    ) {
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

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "CToken: invalid central registry"
        );

        centralRegistry = centralRegistry_;
        underlying = underlying_;
        vault = BasePositionVault(vault_);
        name = name_;
        symbol = IERC20(underlying_).symbol();
        decimals = IERC20(underlying_).decimals();
    }

    function migrateVault(
        address newVault
    ) external onlyDaoPermissions nonReentrant {
        address oldVault = address(vault);
        vault = BasePositionVault(address(0));

        bytes memory params = BasePositionVault(oldVault).migrateStart(
            newVault
        );
        BasePositionVault(newVault).migrateConfirm(oldVault, params);

        vault = BasePositionVault(newVault);
        emit MigrateVault(oldVault, newVault);
    }

    /// @notice Transfer `amount` tokens from `msg.sender` to `to`
    /// @param to The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transfer(
        address to,
        uint256 amount
    ) external nonReentrant returns (bool) {
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
    ) external nonReentrant returns (bool) {
        transferTokens(msg.sender, from, to, amount);
        return true;
    }

    /// @notice Sender supplies assets into the market and receives cTokens in exchange
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param mintAmount The amount of the underlying asset to supply
    /// @return bool true=success
    function mint(uint256 mintAmount) external nonReentrant returns (bool) {
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
        _mint(msg.sender, recipient, mintAmount);
        return true;
    }

    /// @notice Sender redeems cTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemTokens The number of cTokens to redeem into underlying
    function redeem(uint256 redeemTokens) external nonReentrant {
        _redeem(
            payable(msg.sender),
            redeemTokens,
            (exchangeRateStored() * redeemTokens) / expScale,
            payable(msg.sender)
        );
    }

    /// @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemAmount The amount of underlying to redeem
    function redeemUnderlying(uint256 redeemAmount) external nonReentrant {
        address payable redeemer = payable(msg.sender);
        uint256 redeemTokens = (redeemAmount * expScale) /
            exchangeRateStored();

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
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert FailedNotFromPositionFolding();
        }

        _redeem(
            user,
            (redeemAmount * expScale) / exchangeRateStored(),
            redeemAmount,
            payable(msg.sender)
        );

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            user,
            redeemAmount,
            params
        );

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), user, 0);
    }

    /// @notice The sender adds to reserves.
    /// @param addAmount The amount fo underlying token to add as reserves
    function depositReserves(
        uint256 addAmount
    ) external nonReentrant onlyElevatedPermissions {
        // On success, the cToken holds an additional addAmount of cash.
        totalReserves += doTransferIn(msg.sender, addAmount);

        // emit ReservesAdded(msg.sender, actualAddAmount, totalReserves); /// changed to emit correct variable
        emit ReservesAdded(msg.sender, addAmount, totalReserves);
    }

    /// @notice Accrues interest and reduces reserves by transferring to admin
    /// @param reduceAmount Amount of reduction to reserves
    function withdrawReserves(
        uint256 reduceAmount
    ) external nonReentrant onlyElevatedPermissions {
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

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) external returns (bool) {
        transferAllowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return transferAllowances[owner][spender];
    }

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
    ) external onlyElevatedPermissions {
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

    /// @notice Get the underlying balance of the `account`
    /// @dev This also accrues interest in a transaction
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlying(address account) external returns (uint256) {
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
    ) external view returns (uint256, uint256, uint256) {
        return (balanceOf(account), 0, exchangeRateStored());
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
    ) external nonReentrant {
        _seize(msg.sender, liquidator, borrower, seizeTokens);
    }

    /// @notice Get the token balance of the `account`
    /// @param account The address of the account to query
    /// @return balance The number of tokens owned by `account`
    // @dev Returns the balance of tokens for `account`
    function balanceOf(address account) public view returns (uint256) {
        return _accountBalance[account];
    }

    /// @notice Gets balance of this contract in terms of the underlying
    /// @dev This excludes changes in underlying token balance by the current transaction, if any
    /// @return The quantity of underlying tokens owned by this contract
    function getCash() public view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /// @notice Returns the type of Curvance token, 1 = Collateral, 0 = Debt
    function tokenType() public pure returns (uint256) {
        return 1;
    }

    /// @notice Returns gauge pool contract address
    /// @return gaugePool the gauge controller contract address
    function gaugePool() public view returns (address) {
        return lendtroller.gaugePool();
    }

    /// @notice Accrue interest then return the up-to-date exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateCurrent() public nonReentrant returns (uint256) {
        return 1;
    }

    /// @notice Calculates the exchange rate from the underlying to the CToken
    /// @dev This function does not accrue interest before calculating the exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateStored() public pure returns (uint256) {
        return 1;
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
        _accountBalance[from] -= tokens;
        /// We know that from balance wont overflow due to underflow check above
        unchecked {
            _accountBalance[to] += tokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), from, tokens);
        GaugePool(gaugePool()).deposit(address(this), to, tokens);

        // We emit a Transfer event
        emit Transfer(from, to, tokens);
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
    ) internal {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), recipient);

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
        _accountBalance[recipient] += mintTokens;

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
    ) internal {
        // Check if we have enough cash to support the redeem
        if (getCash() < redeemAmount) {
            revert RedeemTransferOutNotPossible();
        }

        // Need to shift bits by timestamp length to make sure we do a proper underflow check
        // redeemTokens should never be above uint216 and the user can never have more than uint216,
        // So if theyve put in a larger number than type(uint216).max we know it will revert from underflow
        _accountBalance[redeemer] -= redeemTokens;

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

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Called byliquidateUser during the liquidation of another CToken.
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
        );

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
        _accountBalance[borrower] -= seizeTokens;
        _accountBalance[liquidator] += liquidatorSeizeTokens;
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
        emit ReservesAdded(address(this), protocolSeizeAmount, totalReserves);
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

        // deposit into the vault
        SafeTransferLib.safeApprove(underlying, address(vault), amount);
        return vault.deposit(amount, address(this));
    }

    /// @notice Handles outgoing token transfers
    /// @dev This function uses the SafeTransferLib to safely perform the transfer.
    /// @param to Address receiving the token transfer
    /// @param amount Amount of tokens to transfer out
    function doTransferOut(address to, uint256 amount) internal {
        // withdraw from the vault
        amount = vault.redeem(amount, address(this), address(this));

        /// SafeTransferLib will handle reversion from insufficient cash held
        SafeTransferLib.safeTransfer(underlying, to, amount);
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IMToken).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
