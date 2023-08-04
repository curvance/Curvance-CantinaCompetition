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

    uint256 internal constant expScale = 1e18;

    /// @notice Indicator that this is a CToken contract (for inspection)
    bool public constant isCToken = true;

    /// @notice Underlying asset for this CToken
    address public immutable underlying;

    /// @notice Decimals for this CToken
    uint8 public immutable decimals;

    ICentralRegistry public immutable centralRegistry;

    /// EVENTS ///

    event MigrateVault(address oldVault, address newVault);
    event Mint(
        address user,
        uint256 mintAmount,
        uint256 mintTokens,
        address minter
    );
    event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);
    event NewLendtroller(
        ILendtroller oldLendtroller,
        ILendtroller newLendtroller
    );
    event ReservesAdded(
        address benefactor,
        uint256 addAmount,
        uint256 newTotalReserves
    );
    event ReservesReduced(
        address admin,
        uint256 reduceAmount,
        uint256 newTotalReserves
    );
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// ERRORS ///

    error FailedNotFromPositionFolding();
    error CannotEqualZero();
    error TransferNotAllowed();
    error RedeemTransferOutNotPossible();
    error SelfLiquidationNotAllowed();
    error LendtrollerMismatch();
    error ReduceReservesCashNotAvailable();

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
        string memory name_,
        string memory symbol_
    ) {
        
        if (initialExchangeRateScaled_ == 0) {
            revert CannotEqualZero();
        }

        // Set initial exchange rate
        initialExchangeRateScaled = initialExchangeRateScaled_;
        
        // Ensure that lendtroller parameter is a lendtroller
        if (!ILendtroller(lendtroller_).isLendtroller()) {
            revert LendtrollerMismatch();
        }

        // Set the lendtroller
        lendtroller = ILendtroller(lendtroller_);
        emit NewLendtroller(ILendtroller(address(0)), ILendtroller(lendtroller_));

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
        name = string(abi.encodePacked("Curvance collateralized ", name_));
        symbol = string(abi.encodePacked("c", symbol_));
        decimals = IERC20(underlying_).decimals();
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
    /// @param tokensToRedeem The number of cTokens to redeem into underlying
    function redeem(uint256 tokensToRedeem) external nonReentrant {
        _redeem(
            payable(msg.sender),
            tokensToRedeem,
            (exchangeRateStored() * tokensToRedeem) / expScale,
            payable(msg.sender)
        );
    }

    /// @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param tokensToRedeem The amount of underlying to redeem
    function redeemUnderlying(uint256 tokensToRedeem) external nonReentrant {
        uint256 redeemTokens = (tokensToRedeem * expScale) /
            exchangeRateStored();

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), msg.sender, redeemTokens);

        _redeem(payable(msg.sender), redeemTokens, tokensToRedeem, payable(msg.sender));
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
            revert FailedNotFromPositionFolding();
        }

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

        // Fail if redeem not allowed
        lendtroller.redeemAllowed(address(this), user, 0);
    }

    /// @notice Adds reserves by transferring from Curvance DAO to the market and depositing to the gauge
    /// @param addAmount The amount fo underlying token to add as reserves
    function depositReserves(
        uint256 addAmount
    ) external nonReentrant onlyElevatedPermissions {
        // On success, the market will deposit `addAmount` to the gauge pool
        totalReserves = totalReserves + doTransferIn(msg.sender, addAmount);

        emit ReservesAdded(msg.sender, addAmount, totalReserves);
    }

    /// @notice Reduces reserves by withdrawing from the gauge and transferring to Curvance DAO
    /// @param reduceAmount Amount of reduction to reserves
    function withdrawReserves(
        uint256 reduceAmount
    ) external nonReentrant onlyElevatedPermissions {
        // Make sure we have enough cash to cover withdrawal
        if (getCash() < reduceAmount) {
            revert ReduceReservesCashNotAvailable();
        }

        // Need underflow check to see if we have sufficient totalReserves
        totalReserves = totalReserves - reduceAmount;

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
    /// @param newLendtroller New lendtroller address
    function setLendtroller(
        ILendtroller newLendtroller
    ) external onlyElevatedPermissions {
        // Ensure we are switching to an actual lendtroller
        if (!newLendtroller.isLendtroller()) {
            revert LendtrollerMismatch();
        }

        // Cache the current lendtroller to save gas
        ILendtroller oldLendtroller = lendtroller;

        // Set new lendtroller
        lendtroller = newLendtroller;

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
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    /// @return tokenBalance
    /// @return borrowBalance
    /// @return exchangeRate scaled 1e18
    function getAccountSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return (balanceOf(account), 0, exchangeRateStored());
    }

    /// @notice Get a snapshot of the cToken and `account` data
    /// @dev This is used by lendtroller to more efficiently perform liquidity checks
    /// @param account Address of the account to snapshot
    function getAccountSnapshotPacked(
        address account
    ) external view returns (accountSnapshot memory) {
        return (accountSnapshot({
            asset: IMToken(address(this)),
            tokenType: 1,
            mTokenBalance: balanceOf(account), 
            borrowBalance: 0, 
            exchangeRateScaled: exchangeRateStored()}));
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

    /// @notice Pull up-to-date exchange rate from the underlying to the CToken with reEntry lock
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateCurrent() public nonReentrant returns (uint256) {
        return exchangeRateStored();
    }

    /// @notice Pull up-to-date exchange rate from the underlying to the CToken
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateStored() public view returns (uint256) {
        return vault.convertToAssets(expScale) / expScale;
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

        // Do not allow self-transfers
        if (from == to) {
            revert TransferNotAllowed();
        }

        // Fails if transfer not allowed
        lendtroller.transferAllowed(address(this), from, to, tokens);

        // Get the allowance, if the spender is not the `from` address
        if (spender != from) {
            // Validate that spender has enough allowance for the transfer with underflow check
            transferAllowances[from][spender] = transferAllowances[from][spender] - tokens;
        }

        // Update token balances
        // shift token value by timestamp length bit length so we can check for underflow
        _accountBalance[from] = _accountBalance[from] - tokens;
        /// We know that from balance wont overflow due to underflow check above
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

        // Note: The function returns the amount actually received from the positionVault. 
        //       On success, the cToken holds an additional `actualMintAmount` of cash.
        uint256 actualMintAmount = doTransferIn(user, mintAmount);

        // We get the current exchange rate and calculate the number of cTokens to be minted:
        //  mintTokens = actualMintAmount / exchangeRate
        uint256 mintTokens = (actualMintAmount * expScale) / exchangeRateStored();
        unchecked {
            totalSupply = totalSupply + mintTokens;
            /// Calculate their new balance
            _accountBalance[recipient] = _accountBalance[recipient] + mintTokens;
        }
        
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
        _accountBalance[redeemer] = _accountBalance[redeemer] - redeemTokens;

        // We have user underflow check above so we do not need a redundant check here
        unchecked {
            totalSupply = totalSupply - redeemTokens;
        }

        // emit events on gauge pool
        GaugePool(gaugePool()).withdraw(address(this), redeemer, redeemTokens);

        // We invoke doTransferOut for the redeemer and the redeemAmount
        // so that we can withdraw tokens from the position vault for the redeemer
        // On success, the cToken has redeemAmount less of cash.
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

        // Fails if borrower = liquidator
        if (borrower == liquidator) {
            revert SelfLiquidationNotAllowed();
        }

        // Fails if seize not allowed
        lendtroller.seizeAllowed(
            address(this),
            seizerToken,
            liquidator,
            borrower
        );

        uint256 protocolSeizeTokens = (seizeTokens *
            centralRegistry.protocolLiquidationFee()) / expScale;
        uint256 protocolSeizeAmount = (exchangeRateStored() *
            protocolSeizeTokens) / expScale;
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;

        // Document new account balances with underflow check on borrower balance
        _accountBalance[borrower] = _accountBalance[borrower] - seizeTokens;
        _accountBalance[liquidator] = _accountBalance[liquidator] + liquidatorSeizeTokens;
        // Reserves should never overflow since totalSupply will always be higher before function than totalReserves after this call
        unchecked {
            totalReserves = totalReserves + protocolSeizeAmount;
            totalSupply = totalSupply - protocolSeizeTokens;
        }
        
        // emit events on gauge pool
        address _gaugePool = gaugePool();
        GaugePool(_gaugePool).withdraw(address(this), borrower, seizeTokens);
        GaugePool(_gaugePool).deposit(
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
        BasePositionVault _vault = vault;
        SafeTransferLib.safeApprove(underlying, address(_vault), amount);
        return _vault.deposit(amount, address(this));
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
