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
import { IMToken, accountSnapshot } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance's Collateral Token Contract
contract CToken is ERC165, ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Scalar for math
    uint256 internal constant EXP_SCALE = 1e18;

    /// @notice For inspection
    bool public constant isCToken = true;

    /// @notice Underlying asset for the CToken
    address public immutable underlying;

    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Token name metadata
    string public name;

    /// @notice Token symbol metadata
    string public symbol;

    /// @notice Current lending market controller
    ILendtroller public lendtroller;

    /// @notice Current position vault
    BasePositionVault public vault;

    /// @notice Total protocol reserves of underlying
    uint256 public totalReserves;

    /// @notice Total number of tokens in circulation
    uint256 public totalSupply;

    /// @notice account => token balance
    mapping(address => uint256) public balanceOf;

    /// @notice account => spender => approved amount
    mapping(address => mapping(address => uint256)) public allowance;

    /// EVENTS ///

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event MigrateVault(address oldVault, address newVault);
    event NewLendtroller(address oldLendtroller, address newLendtroller);
    event ReservesAdded(
        address daoAddress,
        uint256 amount,
        uint256 newTotalReserves
    );
    event ReservesReduced(
        address daoAddress,
        uint256 amount,
        uint256 newTotalReserves
    );

    /// ERRORS ///

    error CToken__UnauthorizedCaller();
    error CToken__CannotEqualZero();
    error CToken__TransferNotAllowed();
    error CToken__CentralRegistryIsInvalid();
    error CToken__LendtrollerIsNotLendingMarket();

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

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of Curvances Central Registry
    /// @param underlying_ The address of the underlying asset
    /// @param lendtroller_ The address of the Lendtroller
    /// @param vault_ The address of the position vault
    constructor(
        ICentralRegistry centralRegistry_,
        address underlying_,
        address lendtroller_,
        address vault_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CToken__CentralRegistryIsInvalid();
        }

        centralRegistry = centralRegistry_;

        // Set the lendtroller after consulting Central Registry
        _setLendtroller(lendtroller_);

        underlying = underlying_;
        vault = BasePositionVault(vault_);
        name = string.concat("Curvance collateralized ", IERC20(underlying_).name());
        symbol = string.concat("c", IERC20(underlying_).symbol());

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate of 1e18
        require(
            IERC20(underlying).totalSupply() < type(uint232).max,
            "CToken: Underlying token assumptions not met"
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Used to start a CToken market, executed via lendtroller
    /// @dev this initial mint is a failsafe against the empty market exploit
    ///      although we protect against it in many ways,
    ///      better safe than sorry
    /// @param initializer the account initializing the market
    function startMarket(
        address initializer
    ) external nonReentrant returns (bool) {
        if (msg.sender != address(lendtroller)) {
            revert CToken__UnauthorizedCaller();
        }

        uint256 mintAmount = 42069;
        uint256 mintTokens = _enterVault(initializer, mintAmount);

        // We do not need to calculate exchange rate here as we will
        // always be the initial depositer.
        // These values should always be zero but we will add them
        // just incase we are re-initiating a market.
        totalSupply = totalSupply + mintTokens;
        balanceOf[initializer] =
            balanceOf[initializer] +
            mintTokens;

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(
            address(this),
            initializer,
            mintTokens
        );

        emit Transfer(address(0), initializer, 42069);
        return true;
    }

    function migrateVault(
        address newVault
    ) external onlyElevatedPermissions nonReentrant {
        // Cache current vault
        address oldVault = address(vault);
        // Zero out current vault
        vault = BasePositionVault(address(0));

        // Begin Migration process
        bytes memory params = BasePositionVault(oldVault).migrateStart(
            newVault
        );

        // Confirm Migration
        BasePositionVault(newVault).migrateConfirm(oldVault, params);

        // Switch to new vault
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

    /// @notice Sender supplies assets into the market and receives cTokens
    ///         in exchange
    /// @dev Accrues interest whether or not the operation succeeds,
    ///      unless reverted
    /// @param mintAmount The amount of the underlying asset to supply
    /// @return bool true=success
    function mint(uint256 mintAmount) external nonReentrant returns (bool) {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), msg.sender);

        _mint(msg.sender, msg.sender, mintAmount);
        return true;
    }

    /// @notice Sender supplies assets into the market and receives cTokens
    ///         in exchange
    /// @dev Accrues interest whether or not the operation succeeds,
    ///      unless reverted
    /// @param recipient The recipient address
    /// @param mintAmount The amount of the underlying asset to supply
    /// @return bool true=success
    function mintFor(
        uint256 mintAmount,
        address recipient
    ) external nonReentrant returns (bool) {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), recipient);

        _mint(msg.sender, recipient, mintAmount);
        return true;
    }

    /// @notice Sender redeems cTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds,
    ///      unless reverted
    /// @param tokensToRedeem The number of cTokens to redeem into underlying
    function redeem(uint256 tokensToRedeem) external nonReentrant {

        lendtroller.redeemAllowed(address(this), msg.sender, tokensToRedeem);

        _redeem(
            msg.sender,
            tokensToRedeem,
            (exchangeRateStored() * tokensToRedeem) / EXP_SCALE,
            msg.sender
        );
    }

    /// @notice Sender redeems cTokens in exchange for a specified amount
    ///         of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds,
    ///      unless reverted
    /// @param tokensToRedeem The amount of underlying to redeem
    function redeemUnderlying(uint256 tokensToRedeem) external nonReentrant {
        uint256 redeemTokens = (tokensToRedeem * EXP_SCALE) /
            exchangeRateStored();

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), msg.sender, redeemTokens);

        _redeem(
            msg.sender,
            redeemTokens,
            tokensToRedeem,
            msg.sender
        );
    }

    /// @notice Helper function for Position Folding contract to
    ///         redeem underlying tokens
    /// @param user The user address
    /// @param tokensToRedeem The amount of the underlying asset to redeem
    function redeemUnderlyingForPositionFolding(
        address user,
        uint256 tokensToRedeem,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert CToken__UnauthorizedCaller();
        }

        _redeem(
            user,
            (tokensToRedeem * EXP_SCALE) / exchangeRateStored(),
            tokensToRedeem,
            msg.sender
        );

        IPositionFolding(msg.sender).onRedeem(
            address(this),
            user,
            tokensToRedeem,
            params
        );

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), user, 0);
    }

    /// @notice Adds reserves by transferring from Curvance DAO to the market
    ///         and depositing to the gauge
    /// @param addAmount The amount of underlying token to add as reserves
    function depositReserves(
        uint256 addAmount
    ) external nonReentrant onlyDaoPermissions {
        // On success, the market will deposit `addAmount` to the position vault
        totalReserves = totalReserves + _enterVault(msg.sender, addAmount);
        // Query current DAO operating address
        address daoAddress = centralRegistry.daoAddress();
        // Deposit new reserves into gauge
        GaugePool(gaugePool()).deposit(address(this), daoAddress, addAmount);

        emit ReservesAdded(daoAddress, addAmount, totalReserves);
    }

    /// @notice Reduces reserves by withdrawing from the gauge
    ///         and transferring to Curvance DAO
    /// @dev If daoAddress is going to be moved all reserves should be
    ///      withdrawn first
    /// @param reduceAmount Amount of reserves to withdraw
    function withdrawReserves(
        uint256 reduceAmount
    ) external nonReentrant onlyDaoPermissions {
        // Need underflow check to see if we have sufficient totalReserves
        totalReserves = totalReserves - reduceAmount;

        // Query current DAO operating address
        address daoAddress = centralRegistry.daoAddress();
        // Withdraw reserves from gauge
        GaugePool(gaugePool()).withdraw(
            address(this),
            daoAddress,
            reduceAmount
        );

        _exitVault(daoAddress, reduceAmount);

        emit ReservesReduced(daoAddress, reduceAmount, totalReserves);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///      Emits a {Approval} event.
    function approve(
        address spender,
        uint256 amount
    ) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
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
            require(token != address(vault), "CToken: cannot withdraw vault tokens");
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "CToken: insufficient balance"
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

    /// @notice Get the underlying balance of the `account`
    /// @dev This also accrues interest in a transaction
    /// @param account The address of the account to query
    /// @return The amount of underlying owned by `account`
    function balanceOfUnderlying(address account) external returns (uint256) {
        return ((exchangeRateCurrent() * balanceOf[account]) / EXP_SCALE);
    }

    /// @notice Get a snapshot of the account's balances,
    ///         and the cached exchange rate
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    /// @return tokenBalance
    /// @return borrowBalance
    /// @return exchangeRate scaled 1e18
    function getAccountSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return (balanceOf[account], 0, exchangeRateStored());
    }

    /// @notice Get a snapshot of the cToken and `account` data
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    function getAccountSnapshotPacked(
        address account
    ) external view returns (accountSnapshot memory) {
        return (
            accountSnapshot({
                asset: IMToken(address(this)),
                tokenType: 1,
                mTokenBalance: balanceOf[account],
                borrowBalance: 0,
                exchangeRateScaled: exchangeRateStored()
            })
        );
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Will fail unless called by another cToken during the process
    ///      of liquidation.
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

    /// PUBLIC FUNCTIONS ///

    /// @notice Returns the decimals of the token
    /// @dev We pull directly from underlying incase its a proxy contract
    ///      and changes decimals on us
    function decimals() public view returns (uint8) {
        return IERC20(underlying).decimals();
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

    /// @notice Pull up-to-date exchange rate from the underlying to
    ///         the CToken with reEntry lock
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateCurrent() public nonReentrant returns (uint256) {
        return exchangeRateStored();
    }

    /// @notice Pull up-to-date exchange rate from the underlying to the CToken
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateStored() public view returns (uint256) {
        // If the vault is empty this will default to 1e18 which is what we want,
        // plus when we list a market we mint a small amount ourselves
        return vault.convertToAssets(EXP_SCALE);
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IMToken).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Sets a new lendtroller for the market
    /// @param newLendtroller New lendtroller address
    function _setLendtroller(address newLendtroller) internal {

        // Ensure that lendtroller parameter is a lendtroller
        if (!centralRegistry.isLendingMarket(newLendtroller)) {
            revert CToken__LendtrollerIsNotLendingMarket();
        }

        // Cache the current lendtroller to save gas
        address oldLendtroller = address(lendtroller);

        // Set new lendtroller
        lendtroller = ILendtroller(newLendtroller);

        emit NewLendtroller(oldLendtroller, newLendtroller);
    }

    /// @notice Transfer `tokens` tokens from `from` to `to` by `spender` internally
    /// @dev Called by both `transfer` and `transferFrom` internally
    /// @param spender The address of the account performing the transfer
    /// @param from The address of the source account
    /// @param to The address of the destination account
    /// @param amount The number of tokens to transfer
    function _transfer(
        address spender,
        address from,
        address to,
        uint256 amount
    ) internal {
        // Do not allow self-transfers
        if (from == to) {
            revert CToken__TransferNotAllowed();
        }

        // Fails if transfer not allowed
        lendtroller.transferAllowed(address(this), from, to, amount);

        // Get the allowance, if the spender is not the `from` address
        if (spender != from) {
            // Validate that spender has enough allowance for the transfer
            // with underflow check
            allowance[from][spender] =
                allowance[from][spender] -
                amount;
        }

        // Update token balances
        balanceOf[from] = balanceOf[from] - amount;
        // We know that from balance wont overflow due to underflow check above
        unchecked {
            balanceOf[to] = balanceOf[to] + amount;
        }

        // emit events on gauge pool
        address _gaugePool = gaugePool();
        GaugePool(_gaugePool).withdraw(address(this), from, amount);
        GaugePool(_gaugePool).deposit(address(this), to, amount);

        emit Transfer(from, to, amount);
    }

    /// @notice User supplies assets into the market and receives cTokens in exchange
    /// @dev Assumes interest has already been accrued up to the current timestamp
    /// @param user The address of the account which is supplying the assets
    /// @param recipient The address of the account which will receive cToken
    /// @param amount The amount of the underlying asset to supply
    function _mint(
        address user,
        address recipient,
        uint256 amount
    ) internal {
        
        // The function returns the amount actually received from the positionVault
        uint256 mintTokens = _enterVault(user, amount);

        unchecked {
            totalSupply = totalSupply + mintTokens;
            /// Calculate their new balance
            balanceOf[recipient] =
                balanceOf[recipient] +
                mintTokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), recipient, mintTokens);

        emit Transfer(address(0), recipient, mintTokens);
    }

    /// @notice User redeems cTokens in exchange for the underlying asset
    /// @dev Assumes interest has already been accrued up to the current timestamp
    /// @param redeemer The address of the account which is redeeming the tokens
    /// @param tokens The number of cTokens to redeem into underlying
    /// @param amount The number of underlying tokens to receive
    ///                     from redeeming cTokens
    /// @param recipient The recipient address
    function _redeem(
        address redeemer,
        uint256 tokens,
        uint256 amount,
        address recipient
    ) internal {
        // Validate redemption parameters
        if (tokens == 0 && amount > 0) {
            revert CToken__CannotEqualZero();
        }

        // we know it will revert from underflow
        balanceOf[redeemer] = balanceOf[redeemer] - tokens;

        // We have user underflow check above so we do not need
        // a redundant check here
        unchecked {
            totalSupply = totalSupply - tokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), redeemer, tokens);

        // We invoke _doTransferOut for the redeemer and the redeemAmount
        // so that we can withdraw tokens from the position vault for the redeemer
        // On success, the cToken has redeemAmount less of cash.
        _exitVault(recipient, amount);

        emit Transfer(redeemer, address(0), tokens);
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Called byliquidateUser during the liquidation of another CToken.
    /// @param token The contract seizing the collateral (i.e. borrowed cToken)
    /// @param liquidator The account receiving seized collateral
    /// @param borrower The account having collateral seized
    /// @param tokens The number of cTokens to seize
    function _seize(
        address token,
        address liquidator,
        address borrower,
        uint256 tokens
    ) internal {
        // Fails if borrower = liquidator
        assembly {
            if eq(borrower, liquidator) {
                // revert with CToken__UnauthorizedCaller()
                mstore(0x00, 0xb856b3fe)
                revert(0x1c, 0x04)
            }
        }

        // Fails if seize not allowed
        lendtroller.seizeAllowed(
            address(this),
            token,
            liquidator,
            borrower
        );

        uint256 protocolSeizeTokens = (tokens *
            centralRegistry.protocolLiquidationFee()) / EXP_SCALE;
        uint256 liquidatorSeizeTokens = tokens - protocolSeizeTokens;

        // Document new account balances with underflow check on borrower balance
        balanceOf[borrower] = balanceOf[borrower] - tokens;
        balanceOf[liquidator] =
            balanceOf[liquidator] +
            liquidatorSeizeTokens;

        // Reserves should never overflow since totalSupply will always be
        // higher before function than totalReserves after this call
        unchecked {
            totalReserves = totalReserves + protocolSeizeTokens;
            totalSupply = totalSupply - protocolSeizeTokens;
        }

        // emit events on gauge pool
        address _gaugePool = gaugePool();
        GaugePool(_gaugePool).withdraw(address(this), borrower, tokens);
        GaugePool(_gaugePool).deposit(
            address(this),
            liquidator,
            liquidatorSeizeTokens
        );
        GaugePool(_gaugePool).deposit(
            address(this),
            centralRegistry.daoAddress(),
            protocolSeizeTokens
        );

        emit Transfer(borrower, liquidator, liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), protocolSeizeTokens);
        emit ReservesAdded(address(this), protocolSeizeTokens, totalReserves);
    }

    /// @notice Handles incoming token transfers and notifies the amount received
    /// @dev This function uses the SafeTransferLib to safely perform the transfer.
    ///      It doesn't support tokens with a transfer tax.
    /// @param from Address of the sender of the tokens
    /// @param amount Amount of tokens to transfer in
    /// @return Returns the amount transferred
    function _enterVault(
        address from,
        uint256 amount
    ) internal returns (uint256) {
        // SafeTransferLib will handle reversion from insufficient balance
        // or allowance.
        // Note this will not support tokens with a transfer tax,
        // which should not exist on a underlying asset anyway.
        SafeTransferLib.safeTransferFrom(
            underlying,
            from,
            address(this),
            amount
        );

        // deposit into the vault
        BasePositionVault _vault = vault;
        SafeTransferLib.safeApprove(underlying, address(_vault), amount);
        return _vault.deposit(amount, address(this));
    }

    /// @notice Handles outgoing token transfers
    /// @dev This function uses the SafeTransferLib to safely perform the transfer.
    /// @param to Address receiving the token transfer
    /// @param amount Amount of tokens to transfer out
    function _exitVault(address to, uint256 amount) internal {
        if (address(vault) != address(0)) {
            // withdraw from the vault
            amount = vault.redeem(amount, address(this), address(this));
        }

        // SafeTransferLib will handle reversion from insufficient cash held
        SafeTransferLib.safeTransfer(underlying, to, amount);
    }
}
