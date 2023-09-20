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
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

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

    /// ERRORS ///

    error CToken__UnauthorizedCaller();
    error CToken__CannotEqualZero();
    error CToken__ExcessiveValue();
    error CToken__TransferNotAllowed();
    error CToken__ValidationFailed();
    error CToken__ConstructorParametersareInvalid();
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
            revert CToken__ConstructorParametersareInvalid();
        }

        centralRegistry = centralRegistry_;

        // Set the lendtroller after consulting Central Registry
        _setLendtroller(lendtroller_);

        underlying = underlying_;
        vault = BasePositionVault(vault_);
        name = string.concat(
            "Curvance collateralized ",
            IERC20(underlying_).name()
        );
        symbol = string.concat("c", IERC20(underlying_).symbol());

        // Sanity check underlying so that we know users will not need to
        // mint anywhere close to exchange rate of 1e18
        if (IERC20(underlying).totalSupply() >= type(uint232).max) {
            revert CToken__ConstructorParametersareInvalid();
        }
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

        uint256 amount = 42069;
        // `tokens` should be equal to `amount` but we use tokens just incase
        uint256 tokens = _enterVault(initializer, amount);

        // These values should always be zero but we will add them
        // just incase
        totalSupply = totalSupply + tokens;
        balanceOf[initializer] = balanceOf[initializer] + tokens;

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), initializer, tokens);

        emit Transfer(address(0), initializer, tokens);
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
    /// @param amount The amount of the underlying asset to supply
    /// @return bool true = success
    function mint(uint256 amount) external nonReentrant returns (bool) {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), msg.sender);

        _mint(msg.sender, msg.sender, amount);
        return true;
    }

    /// @notice Sender supplies assets into the market and receives cTokens
    ///         in exchange
    /// @dev Accrues interest whether or not the operation succeeds,
    ///      unless reverted
    /// @param recipient The recipient address
    /// @param amount The amount of the underlying asset to supply
    /// @return bool true = success
    function mintFor(
        uint256 amount,
        address recipient
    ) external nonReentrant returns (bool) {
        // Fail if mint not allowed
        lendtroller.mintAllowed(address(this), recipient);

        _mint(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Sender redeems cTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds,
    ///      unless reverted
    /// @param amount The number of cTokens to redeem into underlying
    function redeem(uint256 amount) external nonReentrant {
        lendtroller.redeemAllowed(address(this), msg.sender, amount);

        _redeem(
            msg.sender,
            amount,
            (exchangeRateStored() * amount) / EXP_SCALE,
            msg.sender
        );
    }

    /// @notice Sender redeems cTokens in exchange for a specified amount
    ///         of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds,
    ///      unless reverted
    /// @param underlyingAmount The amount of underlying to redeem
    function redeemUnderlying(uint256 underlyingAmount) external nonReentrant {
        uint256 amount = (underlyingAmount * EXP_SCALE) / exchangeRateStored();

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), msg.sender, amount);

        _redeem(msg.sender, amount, underlyingAmount, msg.sender);
    }

    /// @notice Helper function for Position Folding contract to
    ///         redeem underlying tokens
    /// @param user The user address
    /// @param underlyingAmount The amount of the underlying asset to redeem
    function redeemUnderlyingForPositionFolding(
        address user,
        uint256 underlyingAmount,
        bytes calldata params
    ) external nonReentrant {
        if (msg.sender != lendtroller.positionFolding()) {
            revert CToken__UnauthorizedCaller();
        }

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

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), user, 0);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///      Emits a {Approval} event.
    function approve(address spender, uint256 amount) external returns (bool) {
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
            if (address(this).balance < amount) {
                revert CToken__ExcessiveValue();
            }

            (bool success, ) = payable(daoOperator).call{ value: amount }("");

            if (!success) {
                revert CToken__ValidationFailed();
            }
        } else {
            if (token == address(vault)) {
                revert CToken__TransferNotAllowed();
            }

            if (IERC20(token).balanceOf(address(this)) < amount) {
                revert CToken__ExcessiveValue();
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
    ) external view returns (AccountSnapshot memory) {
        return (
            AccountSnapshot({
                asset: address(this),
                tokenType: 1,
                mTokenBalance: balanceOf[account],
                borrowBalance: 0,
                exchangeRate: exchangeRateStored()
            })
        );
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
        _seize(
            msg.sender,
            liquidator,
            borrower,
            liquidatedTokens,
            protocolTokens
        );
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
            allowance[from][spender] = allowance[from][spender] - amount;
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
    function _mint(address user, address recipient, uint256 amount) internal {
        // The function returns the amount actually received from the positionVault
        uint256 tokens = _enterVault(user, amount);

        unchecked {
            totalSupply = totalSupply + tokens;
            /// Calculate their new balance
            balanceOf[recipient] = balanceOf[recipient] + tokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).deposit(address(this), recipient, tokens);

        emit Transfer(address(0), recipient, tokens);
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

        // Exit position vault and transfer underlying to `recipient` in assets
        _exitVault(recipient, tokens);

        emit Transfer(redeemer, address(0), tokens);
    }

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Called byliquidateUser during the liquidation of another CToken.
    /// @param token The contract seizing the collateral (i.e. borrowed cToken)
    /// @param liquidator The account receiving seized collateral
    /// @param borrower The account having collateral seized
    /// @param liquidatedTokens The total number of cTokens to seize
    /// @param protocolTokens The number of cTokens to seize for protocol
    function _seize(
        address token,
        address liquidator,
        address borrower,
        uint256 liquidatedTokens,
        uint256 protocolTokens
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
        lendtroller.seizeAllowed(address(this), token, liquidator, borrower);

        uint256 liquidatorTokens = liquidatedTokens - protocolTokens;

        // Document new account balances with underflow check on borrower balance
        balanceOf[borrower] = balanceOf[borrower] - liquidatedTokens;
        balanceOf[liquidator] = balanceOf[liquidator] + liquidatorTokens;

        // emit events on gauge pool
        address _gaugePool = gaugePool();
        GaugePool(_gaugePool).withdraw(
            address(this),
            borrower,
            liquidatedTokens
        );
        GaugePool(_gaugePool).deposit(
            address(this),
            liquidator,
            liquidatorTokens
        );
        if (protocolTokens > 0) {
            address daoAddress = centralRegistry.daoAddress();
            GaugePool(_gaugePool).deposit(
                address(this),
                daoAddress,
                protocolTokens
            );

            unchecked {
                balanceOf[daoAddress] = balanceOf[daoAddress] + protocolTokens;
            }
            
            emit Transfer(borrower, daoAddress, protocolTokens);
        }

        emit Transfer(borrower, liquidator, liquidatorTokens); 
    }

    /// @notice Handles incoming token transfers and notifies the amount received
    /// @dev  Note this will not support tokens with a transfer tax,
    ///       which should not exist on a underlying asset anyway
    /// @param from Address of the sender of the tokens
    /// @param amount Amount of underlying tokens to deposit into the position vault
    /// @return Returns the CTokens received
    function _enterVault(
        address from,
        uint256 amount
    ) internal returns (uint256) {
        // Reverts on insufficient balance
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
    /// @param to Address receiving the token transfer
    /// @param amount Amount of CTokens to withdraw from position vault
    function _exitVault(address to, uint256 amount) internal {
        if (address(vault) != address(0)) {
            // withdraw from the vault
            amount = vault.redeem(amount, address(this), address(this));
        }

        // SafeTransferLib will handle reversion from insufficient cash held
        SafeTransferLib.safeTransfer(underlying, to, amount);
    }
}
