// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { LiquidityManager, IOracleRouter, IMToken } from "contracts/market/LiquidityManager.sol";

import { WAD, WAD_SQUARED } from "contracts/libraries/Constants.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

/// @title Curvance DAO Market Manager.
/// @notice Manages risk within the Curvance DAO markets.
contract MarketManager is LiquidityManager, ERC165 {
    /// CONSTANTS ///

    /// @notice The address of the linked Gauge Pool.
    IGaugePool public immutable gaugePool;

    /// @notice Maximum collateral requirement to avoid liquidation. 
    ///         2.34e18 = 234%. Resulting in 1 / (WAD + 2.34 WAD),
    ///         or ~30% maximum LTV soft liquidation level.
    uint256 public constant MAX_COLLATERAL_REQUIREMENT = 2.34e18;
    /// @notice Minimum excess collateral requirement 
    ///         on top of liquidation incentive.
    ///         .015e18 = 1.5%.
    uint256 public constant MIN_EXCESS_COLLATERAL_REQUIREMENT = .015e18;
    /// @notice Maximum collateralization ratio.
    ///         .91e18 = 91%.
    uint256 public constant MAX_COLLATERALIZATION_RATIO = .91e18;
    /// @notice The maximum liquidation incentive.
    ///         .3e18 = 30%.
    uint256 public constant MAX_LIQUIDATION_INCENTIVE = .3e18;
    /// @notice The minimum liquidation incentive.
    ///         .01e18 = 1%.
    uint256 public constant MIN_LIQUIDATION_INCENTIVE = .01e18;
    /// @notice The maximum liquidation fee distributed to Curvance DAO.
    ///         .05e18 = 5%.
    uint256 public constant MAX_LIQUIDATION_FEE = .05e18;
    /// @notice The maximum base cFactor.
    ///         .5e18 = 50%.
    uint256 public constant MAX_BASE_CFACTOR = .5e18;
    /// @notice The minimum base cFactor.
    ///         .1e18 = 10%.
    uint256 public constant MIN_BASE_CFACTOR = .1e18;
    /// @notice Minimum hold time to minimize external risks, in seconds.
    ///         20 minutes = 1,200 seconds.
    uint256 public constant MIN_HOLD_PERIOD = 20 minutes;
    
    /// @dev `bytes4(keccak256(bytes("MarketManager__InvalidParameter()")))`
    uint256 internal constant _INVALID_PARAMETER_SELECTOR = 0x65513fc1;
    /// @dev `bytes4(keccak256(bytes("MarketManager__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x37cf6ad5;
    /// @dev `bytes4(keccak256(bytes("MarketManager__TokenNotListed()")))`
    uint256 internal constant _TOKEN_NOT_LISTED_SELECTOR = 0x4f3013c5;
    /// @dev `bytes4(keccak256(bytes("MarketManager__Paused()")))`
    uint256 internal constant _PAUSED_SELECTOR = 0xf47323f4;

    /// STORAGE ///

    /// @notice A list of all tokens inside this market for
    ///         offchain querying.
    address[] public tokensListed;

    /// @notice PositionFolding contract address.
    address public positionFolding;

    /// MARKET STATE
    /// @notice 1 = unpaused; 2 = paused.
    uint256 public transferPaused = 1;
    /// @notice 1 = unpaused; 2 = paused.
    uint256 public seizePaused = 1;
    /// @notice 1 = unpaused; 2 = paused.
    uint256 public redeemPaused = 1;
    /// @notice Token => 0 or 1 = unpaused; 2 = paused.
    mapping(address => uint256) public mintPaused;
    /// @notice Token => 0 or 1 = unpaused; 2 = paused.
    mapping(address => uint256) public borrowPaused;

    /// COLLATERAL CONSTRAINTS
    /// @notice Token => Collateral Posted.
    mapping(address => uint256) public collateralPosted;
    /// @notice Token => Collateral Cap.
    mapping(address => uint256) public collateralCaps;

    /// EVENTS ///

    event TokenListed(address mToken);
    event CollateralPosted(address account, address cToken, uint256 amount);
    event CollateralRemoved(address account, address cToken, uint256 amount);
    event TokenPositionCreated(address mToken, address account);
    event TokenPositionClosed(address mToken, address account);
    event CollateralTokenUpdated(
        IMToken mToken,
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor
    );
    event ActionPaused(string action, bool pauseState);
    event TokenActionPaused(address mToken, string action, bool pauseState);
    event NewCollateralCap(address mToken, uint256 newCollateralCap);
    event NewPositionFoldingContract(address oldPF, address newPF);

    /// ERRORS ///

    error MarketManager__Unauthorized();
    error MarketManager__TokenNotListed();
    error MarketManager__TokenAlreadyListed();
    error MarketManager__Paused();
    error MarketManager__InsufficientCollateral();
    error MarketManager__NoLiquidationAvailable();
    error MarketManager__PriceError();
    error MarketManager__CollateralCapReached();
    error MarketManager__MarketManagerMismatch();
    error MarketManager__InvalidParameter();
    error MarketManager__MinimumHoldPeriod();
    error MarketManager__InvariantError();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address gaugePool_
    ) LiquidityManager(centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(gaugePool_),
                type(IGaugePool).interfaceId
            )
        ) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        gaugePool = IGaugePool(gaugePool_);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Returns whether `mToken` is listed in the lending market.
    /// @param mToken market token address.
    function isListed(address mToken) external view returns (bool) {
        return (tokenData[mToken].isListed);
    }

    /// ACCOUNT SPECIFIC FUNCTIONS ///

    /// @notice Returns the assets an account has entered.
    /// @param account The address of the account to pull assets for.
    /// @return A dynamic list with the assets the account has entered.
    function assetsOf(
        address account
    ) external view returns (IMToken[] memory) {
        return accountAssets[account].assets;
    }

    /// @notice Returns if an account has an active position in `mToken`.
    /// @param account The address of the account to check a position of.
    /// @param mToken The address of the market token.
    function tokenDataOf(
        address account,
        address mToken
    ) external view returns (
        bool hasPosition, 
        uint256 balanceOf, 
        uint256 collateralPostedOf
    ) {
        AccountMetadata memory accountData = tokenData[mToken].accountData[account];
        hasPosition = accountData.activePosition == 2;
        balanceOf = IMToken(mToken).balanceOf(account);
        collateralPostedOf = accountData.collateralPosted;
    }

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity.
    /// @param account The account to determine liquidity for.
    /// @return accountCollateral total collateral amount of account.
    /// @return maxDebt max borrow amount of account.
    /// @return accountDebt total borrow amount of account.
    function statusOf(
        address account
    ) external view returns (uint256, uint256, uint256) {
        return _statusOf(account);
    }

    /// @notice Determine `account`'s current collateral and debt values
    ///         in the market.
    /// @param account The account to check bad debt status for.
    /// @return The total market value of `account`'s collateral.
    /// @return The total outstanding debt value of `account`.
    function solvencyOf(
        address account
    ) external view returns (uint256, uint256) {
        return _solvencyOf(account);
    }

    /// @notice Determine whether `account` can currently be liquidated
    ///         in this market.
    /// @param account The account to check for liquidation flag.
    /// @dev Note: Liquidation flag uses cached exchange rates for each mToken.
    ///            Thus, accumulated but unrecognized interest is not included.
    /// @return Whether `account` can be liquidated currently.
    function flaggedForLiquidation(
        address account
    ) external view returns (bool) {
        LiqData memory data = _LiquidationStatusOf(
            account,
            address(0),
            address(0)
        );
        return data.lFactor > 0;
    }

    /// @notice Determine what the account liquidity would be if
    ///         the given amounts were redeemed/borrowed.
    /// @param account The account to determine liquidity for.
    /// @param mTokenModified The market to hypothetically redeem/borrow in.
    /// @param redeemTokens The number of tokens to hypothetically redeem.
    /// @param borrowAmount The amount of underlying to hypothetically borrow.
    /// @return Hypothetical account liquidity in excess of collateral
    ///         requirements.
    /// @return Hypothetical account liquidity deficit below collateral
    ///         requirements.
    function hypotheticalLiquidityOf(
        address account,
        address mTokenModified,
        uint256 redeemTokens, // in shares
        uint256 borrowAmount // in assets
    ) external view returns (uint256, uint256) {
        return
            _hypotheticalLiquidityOf(
                account,
                mTokenModified,
                redeemTokens,
                borrowAmount,
                2
            );
    }

    /// @notice Post collateral for `mToken` inside this market.
    /// @param mToken The address of the mToken to post collateral for.
    function postCollateral(
        address account,
        address mToken,
        uint256 tokens
    ) external {
        if (!tokenData[mToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        if (!IMToken(mToken).isCToken()) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // If you are trying to post collateral for someone else,
        // make sure it is done via the mToken contract itself.
        if (msg.sender != account) {
            _checkIsToken(mToken);
        }

        AccountMetadata storage accountData = tokenData[mToken].accountData[
            account
        ];

        // Precondition invariant check.
        if (
            accountData.collateralPosted + tokens >
            IMToken(mToken).balanceOf(account)
        ) {
            revert MarketManager__InsufficientCollateral();
        }

        _postCollateral(account, accountData, mToken, tokens);
    }

    /// @notice Remove collateral posted for `cToken` inside this market.
    /// @param cToken The address of the cToken to post collateral for.
    /// @param tokens The number of tokens that are posted of collateral
    ///               that should be removed.
    /// @param closePositionIfPossible Whether the user's position should be
    ///                                forceably closed. Only possible if
    ///                                postedCollateral in `cToken` becomes
    ///                                0 after this action.
    function removeCollateral(
        address cToken,
        uint256 tokens,
        bool closePositionIfPossible
    ) external {
        AccountMetadata storage accountData = tokenData[cToken].accountData[
            msg.sender
        ];

        // We can check this instead of .isListed because any unlisted token
        // will always have activePosition == 0,
        // and this lets us check for any invariant errors.
        if (accountData.activePosition != 2) {
            revert MarketManager__InvariantError();
        }

        if (!IMToken(cToken).isCToken()) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        if (accountData.collateralPosted < tokens) {
            revert MarketManager__InsufficientCollateral();
        }

        // Fail if the sender is not permitted to redeem `tokens`.
        // Note: `tokens` is in shares.
        _canRedeem(cToken, msg.sender, tokens);
        _removeCollateral(
            msg.sender,
            accountData,
            cToken,
            tokens,
            closePositionIfPossible
        );
    }

    /// @notice Reduces `accounts`'s posted collateral if necessary for their
    ///         desired action.
    /// @param account The account to potential reduce posted collateral for.
    /// @param cToken The cToken address to potentially reduce collateral for.
    /// @param balance The cToken share balance of `account`.
    /// @param amount The maximum amount of shares that could be removed as
    ///               collateral.
    function reduceCollateralIfNecessary(
        address account,
        address cToken,
        uint256 balance,
        uint256 amount
    ) external {
        _checkIsToken(cToken);
        _reduceCollateralIfNecessary(account, cToken, balance, amount, false);
    }

    /// @notice Removes an asset from an account's liquidity calculation.
    /// @dev Sender must not have an outstanding borrow balance in the asset,
    ///      or be providing necessary collateral for an outstanding borrow.
    /// @param mToken The address of the asset to be removed.
    function closePosition(address mToken) external {
        IMToken token = IMToken(mToken);
        AccountMetadata storage accountData = tokenData[mToken].accountData[
            msg.sender
        ];

        // We do not need to update any values if the account is not 
        // "in" the market.
        if (accountData.activePosition < 2) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        if (!token.isCToken()) {
            // Get sender tokens and debt underlying from the mToken.
            (, uint256 debt, ) = token.getSnapshot(msg.sender);

            // Caller is unauthorized to close their dToken position
            // if they owe a balance.
            if (debt != 0) {
                _revert(_UNAUTHORIZED_SELECTOR);
            }

            _closePosition(msg.sender, accountData, token);
            return;
        }

        if (accountData.collateralPosted != 0) {
            // Fail if the sender is not permitted to redeem all of their tokens.
            _canRedeem(mToken, msg.sender, accountData.collateralPosted);
            // We use collateral posted here instead of their snapshot,
            // since its possible they have not posted all their tokens as 
            // collateral inside the market.
            _removeCollateral(
                msg.sender,
                accountData,
                mToken,
                accountData.collateralPosted,
                true
            );
            return;
        }

        // Its possible they have a position without collateral posted if:
        // 1. They were liquidated.
        // 2. They removed all their collateral but did not use 
        //    `closePositionIfPossible`.
        // 3. So we need to still close their position here.
        _closePosition(msg.sender, accountData, token);
    }

    /// @notice Checks if the account should be allowed to mint tokens
    ///         in the given market.
    /// @param mToken The token to verify mints against.
    function canMint(address mToken) external view {
        if (mintPaused[mToken] == 2) {
            _revert(_PAUSED_SELECTOR);
        }

        if (!tokenData[mToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }
    }

    /// @notice Checks if the account should be allowed to redeem tokens
    ///         in the given market.
    /// @param mToken The market to verify the redeem against.
    /// @param account The account which would redeem the tokens.
    /// @param amount The number of mTokens to exchange
    ///               for the underlying asset in the market.
    function canRedeem(
        address mToken,
        address account,
        uint256 amount
    ) external view {
        _canRedeem(mToken, account, amount);
    }

    /// @notice Checks if the account should be allowed to redeem tokens
    ///         in the given market, and then redeems.
    /// @dev    This can only be called by the mToken itself 
    ///         (specifically cTokens, because dTokens are never collateral).
    /// @param mToken The market to verify the redeem against.
    /// @param account The account which would redeem the tokens.
    /// @param balance The current mTokens balance of `account`.
    /// @param amount The number of mTokens to exchange
    ///               for the underlying asset in the market.
    /// @param forceRedeemCollateral Whether the collateral should be always
    ///                              reduced.
    function canRedeemWithCollateralRemoval(
        address mToken,
        address account,
        uint256 balance,
        uint256 amount,
        bool forceRedeemCollateral
    ) external {
        _checkIsToken(mToken);
        _canRedeem(mToken, account, amount);

        _reduceCollateralIfNecessary(
            account,
            mToken,
            balance,
            amount,
            forceRedeemCollateral
        );
    }

    /// @notice Checks if the account should be allowed to borrow
    ///         the underlying asset of the given market,
    ///         and notifies the market of the borrow.
    /// @dev    This can only be called by the market itself.
    /// @param mToken The market to verify the borrow against.
    /// @param account The account which would borrow the asset.
    /// @param amount The amount of underlying the account would borrow.
    function canBorrowWithNotify(
        address mToken,
        address account,
        uint256 amount
    ) external {
        _checkIsToken(mToken);
        accountAssets[account].cooldownTimestamp = block.timestamp;
        canBorrow(mToken, account, amount);
    }

    /// @notice Updates `account` cooldownTimestamp to the current block timestamp.
    /// @dev The caller must be a listed MToken in the `markets` mapping.
    /// @param mToken   The address of the dToken that the account is borrowing.
    /// @param account The address of the account that has just borrowed.
    function notifyBorrow(address mToken, address account) external {
        _checkIsToken(mToken);
        accountAssets[account].cooldownTimestamp = block.timestamp;
    }

    /// @notice Checks if the account should be allowed to repay a borrow
    ///         in the given market.
    /// @param mToken The market to verify the repay against.
    /// @param account The account who will have their loan repaid.
    function canRepay(address mToken, address account) external view {
        if (!tokenData[mToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        // We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        // as well as short term price manipulations if the dynamic dual oracle
        // fails to protect the market somehow.
        if (
            accountAssets[account].cooldownTimestamp + MIN_HOLD_PERIOD >
            block.timestamp
        ) {
            revert MarketManager__MinimumHoldPeriod();
        }
    }

    /// @notice Checks if the liquidation should be allowed to occur,
    ///         and returns how many collateral tokens should be seized
    ///         on liquidation.
    /// @param dToken Debt token to repay which is borrowed by `account`.
    /// @param cToken Collateral token collateralized by `account` and will
    ///               be seized.
    /// @param account The address of the account to be liquidated.
    /// @param amount The amount of `debtToken` underlying being repaid.
    /// @param liquidateExact Whether the liquidator desires a specific
    ///                       liquidation amount.
    /// @return The amount of `debtToken` underlying to be repaid on liquidation.
    /// @return The number of `collateralToken` tokens to be seized in a liquidation.
    /// @return The number of `collateralToken` tokens to be seized for the protocol.
    function canLiquidate(
        address dToken,
        address cToken,
        address account,
        uint256 amount,
        bool liquidateExact
    ) external view returns (uint256, uint256, uint256) {
        return _canLiquidate(dToken, cToken, account, amount, liquidateExact);
    }

    /// @notice Checks if the liquidation should be allowed to occur,
    ///         and returns how many collateral tokens should be seized
    ///         on liquidation.
    /// @param dToken Debt token to repay which is borrowed by `account`.
    /// @param cToken Collateral token which was used as collateral and will
    ///        be seized.
    /// @param account The address of the account to be liquidated.
    /// @param amount The amount of `debtToken` underlying being repaid.
    /// @param liquidateExact Whether the liquidator desires a specific
    ///                       liquidation amount.
    /// @return The amount of `debtToken` underlying to be repaid on liquidation.
    /// @return The number of `collateralToken` tokens to be seized in a liquidation.
    /// @return The number of `collateralToken` tokens to be seized for the protocol.
    function canLiquidateWithExecution(
        address dToken,
        address cToken,
        address account,
        uint256 amount,
        bool liquidateExact
    ) external returns (uint256, uint256, uint256) {
        _checkIsToken(dToken);

        (
            uint256 dTokenRepaid,
            uint256 cTokenLiquidated,
            uint256 protocolTokens
        ) = _canLiquidate(dToken, cToken, account, amount, liquidateExact);

        // We can pass balance = 0 here since we are forcing collateral closure
        // and balance will never be lower than collateral posted.
        _reduceCollateralIfNecessary(
            account,
            cToken,
            0,
            cTokenLiquidated,
            true
        );
        return (dTokenRepaid, cTokenLiquidated, protocolTokens);
    }

    /// @notice Checks if the seizing of assets should be allowed to occur.
    /// @param collateralToken Asset which was used as collateral
    ///                        and will be seized.
    /// @param debtToken Asset which was borrowed by the account.
    function canSeize(
        address collateralToken,
        address debtToken
    ) external view {
        if (seizePaused == 2) {
            _revert(_PAUSED_SELECTOR);
        }

        if (!tokenData[collateralToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        if (!tokenData[debtToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        if (
            IMToken(collateralToken).marketManager() !=
            IMToken(debtToken).marketManager()
        ) {
            revert MarketManager__MarketManagerMismatch();
        }
    }

    /// @notice Checks if the account should be allowed to transfer tokens
    ///         in the given market.
    /// @param mToken The market to verify the transfer against.
    /// @param from The account which sources the tokens.
    /// @param amount The number of mTokens to transfer.
    function canTransfer(
        address mToken,
        address from,
        uint256 amount
    ) external view {
        if (transferPaused == 2) {
            _revert(_PAUSED_SELECTOR);
        }

        _canRedeem(mToken, from, amount);
    }

    /// @notice Liquidates an entire account by partially paying down debts,
    ///         distributing all `account` collateral and recognize remaining
    ///         debt as bad debt.
    /// @dev    Updates `account` DToken interest before solvency is checked.
    /// @param account The address to liquidate completely.
    function liquidateAccount(address account) external {
        // Make sure `account` is not trying to liquidate themselves.
        if (msg.sender == account) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Make sure liquidations are not paused.
        if (seizePaused == 2) {
            _revert(_PAUSED_SELECTOR);
        }

        IMToken[] memory accountAssets = accountAssets[account].assets;
        uint256 numAssets = accountAssets.length;
        IMToken mToken;

        // Update pending interest in markets.
        for (uint256 i = 0; i < numAssets; ) {
            // Cache `account` mToken then increment i.
            mToken = accountAssets[i++];
            if (!mToken.isCToken()) {
                // Update DToken interest if necessary.
                mToken.accrueInterest();
            }
        }

        (
            uint256 totalCollateral,
            uint256 debtToPay,
            uint256 totalDebt
        ) = _BadDebtTermsOf(account);

        // If an account has no positions or debt this will revert.
        if (totalCollateral >= totalDebt) {
            revert MarketManager__NoLiquidationAvailable();
        }

        uint256 repayRatio = (debtToPay * WAD) / totalDebt;
        
        // Repay `account`'s debt and recognize bad debt.
        for (uint256 i = 0; i < numAssets; ) {
            // Cache `account` mToken then increment i.
            mToken = accountAssets[i++];
            if (!mToken.isCToken()) {
                // Repay `account`'s debt where:
                // debtToPay = totalCollateral / (1 - liquidationPenalty)
                // badDebt = totalDebt - debtToPay
                // Thus:
                // totalDebt = debtToPay + badDebt
                // where debtToPay is what caller repays to receive collateral
                // badDebt is loss to lenders by offsetting
                // totalBorrows (total estimated outstanding debt)
                mToken.repayWithBadDebt(msg.sender, account, repayRatio);
            }
        }

        uint256 collateral;

        // Seize `account`'s collateral and remove posted collateral.
        for (uint256 i = 0; i < numAssets; ) {
            // Cache `account` mToken then increment i.
            mToken = accountAssets[i++];
            if (mToken.isCToken()) {
                AccountMetadata storage data = tokenData[address(mToken)]
                    .accountData[account];
                // Cache `account` collateral posted.
                collateral = data.collateralPosted;

                // Remove `account` posted collateral,
                // as their account is completely closed out.
                delete data.collateralPosted;
                // Update collateralPosted invariant.
                collateralPosted[address(mToken)] =
                    collateralPosted[address(mToken)] -
                    collateral;
                emit CollateralRemoved(account, address(mToken), collateral);
                // Seize `account`'s collateral and give to caller.
                mToken.seizeAccountLiquidation(
                    msg.sender,
                    account,
                    collateral
                );
            }
        }
    }

    /// PERMISSIONED EXTERNAL FUNCTIONS ///

    /// @notice Add the market token to the market and set it as listed.
    /// @dev Admin function to set isListed and add support for the market.
    /// @param mToken The address of the market (token) to list.
    function listToken(address mToken) external {
        _checkElevatedPermissions();

        if (tokenData[mToken].isListed) {
            revert MarketManager__TokenAlreadyListed();
        }

        // Sanity check to make sure its really a mToken.
        IMToken(mToken).isCToken();

        // Immediately deposit into the market to prevent any rounding
        // exploits.
        if (!IMToken(mToken).startMarket(msg.sender)) {
            revert MarketManager__InvariantError();
        }

        MarketToken storage token = tokenData[mToken];
        token.isListed = true;
        token.collRatio = 0;

        uint256 numTokens = tokensListed.length;

        for (uint256 i; i < numTokens; ) {
            unchecked {
                if (tokensListed[i++] == mToken) {
                    revert MarketManager__TokenAlreadyListed();
                }
            }
        }

        tokensListed.push(mToken);
        emit TokenListed(mToken);
    }

    /// @notice Sets the collRatio for a market token.
    /// @param mToken The market to set the collateralization ratio on.
    /// @param collRatio The ratio at which $1 of collateral can be borrowed
    ///                  against, for `mToken`, in basis points.
    /// @param collReqSoft The premium of excess collateral required to 
    ///                    avoid soft liquidation, in basis points.
    /// @param collReqHard The premium of excess collateral required to 
    ///                    avoid hard liquidation, in basis points.
    /// @param liqIncSoft The soft liquidation incentive for `mToken`, 
    ///                   in basis points.
    /// @param liqIncHard The hard liquidation incentive for `mToken`, 
    ///                   in basis points.
    /// @param liqFee The protocol liquidation fee for `mToken`, 
    ///               in basis points.
    function updateCollateralToken(
        IMToken mToken,
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor
    ) external {
        _checkElevatedPermissions();

        if (!IMToken(mToken).isCToken()) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Verify mToken is listed.
        MarketToken storage marketToken = tokenData[address(mToken)];
        if (!marketToken.isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        // Convert the parameters from basis points to `WAD` format.
        // While inefficient, we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config.
        collRatio = _bpToWad(collRatio);
        collReqSoft = _bpToWad(collReqSoft);
        collReqHard = _bpToWad(collReqHard);
        liqIncSoft = _bpToWad(liqIncSoft);
        liqIncHard = _bpToWad(liqIncHard);
        liqFee = _bpToWad(liqFee);
        baseCFactor = _bpToWad(baseCFactor);

        // Validate collateralization ratio is not above the maximum allowed.
        if (collRatio > MAX_COLLATERALIZATION_RATIO) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate soft liquidation collateral requirement is
        // not above the maximum allowed.
        if (collReqSoft > MAX_COLLATERAL_REQUIREMENT) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate hard liquidation incentive is 
        // not above the maximum allowed.
        if (liqIncHard > MAX_LIQUIDATION_INCENTIVE) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate hard liquidation collateral requirement is not above
        // the soft liquidation requirement. Liquidations occur when 
        // collateral dries up so hard liquidation should be less collateral
        // than soft liquidation.
        if (collReqHard >= collReqSoft) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate hard liquidation incentive is 
        // higher than the soft liquidation incentive. Give heavier incentives
        // when collateral is running out to reduce delta exposure.
        if (liqIncSoft >= liqIncHard) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate hard liquidation collateral requirement is larger
        // than the hard liquidation incentive. We cannot give more incentives
        // than are available. We do not need to check soft liquidation as the
        // restrictions are thinner than this case.
        if (liqIncHard + MIN_EXCESS_COLLATERAL_REQUIREMENT > collReqHard) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate protocol liquidation fee is not above the maximum allowed.
        if (liqFee > MAX_LIQUIDATION_FEE) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // We need to make sure that the liquidation incentive is sufficient
        // for both the protocol and the users.
        if ((liqIncSoft - liqFee) < MIN_LIQUIDATION_INCENTIVE) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate that soft liquidation is within acceptable bounds.
        if (baseCFactor > MAX_BASE_CFACTOR || baseCFactor < MIN_BASE_CFACTOR) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate the soft liquidation collateral premium
        // is not more strict than the asset's CR.
        if (collRatio > (WAD_SQUARED / (WAD + collReqSoft))) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        (, uint256 errorCode) = IOracleRouter(centralRegistry.oracleRouter())
            .getPrice(address(mToken), true, true);

        // Validate that we get a usable price.
        if (errorCode == 2) {
            revert MarketManager__PriceError();
        }

        // Assign new collateralization ratio.
        // Note that a collateralization ratio of 0 corresponds to
        // no collateralization of the mToken.
        marketToken.collRatio = collRatio;

        // Store the collateral requirement as a premium above `WAD`,
        // that way we can calculate solvency via division
        // efficiently in _liquidationStatusOf.
        marketToken.collReqSoft = collReqSoft + WAD;
        marketToken.collReqHard = collReqHard + WAD;

        // Store the distance between liquidation incentive A & B,
        // so we can quickly scale between [base, 100%] based on lFactor.
        marketToken.liqCurve = liqIncHard - liqIncSoft;
        // We use the liquidation incentive values as a premium in
        // `calculateLiquidatedTokens`, so it needs to be 1 + incentive.
        marketToken.liqBaseIncentive = WAD + liqIncSoft;

        // Assign the base cFactor
        marketToken.baseCFactor = baseCFactor;
        // Store the distance between base cFactor and 100%,
        // that way we can quickly scale between [base, 100%] based on lFactor.
        marketToken.cFactorCurve = WAD - baseCFactor;

        // We store protocol liquidation fee divided by the soft liquidation
        // incentive offset, that way we can directly multiply later instead
        // of needing extra calculations, we do not want the liquidation fee
        // to increase with the liquidation engine, as we want to offload
        // risk as quickly as possible by increasing the incentives.
        marketToken.liqFee = (WAD * liqFee) / (WAD + liqIncSoft);

        emit CollateralTokenUpdated(
            mToken,
            collRatio,
            collReqSoft,
            collReqHard,
            liqIncSoft,
            liqIncHard,
            liqFee,
            baseCFactor
        );
    }

    /// @notice Set `newCollateralizationCaps` for the given `mTokens`.
    /// @param mTokens The addresses of the markets (tokens) to
    ///                change the borrow caps for.
    /// @param newCollateralCaps The new collateral cap values in underlying
    ///                          to be set, in  shares.
    function setCTokenCollateralCaps(
        address[] calldata mTokens,
        uint256[] calldata newCollateralCaps
    ) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 numTokens = mTokens.length;

        assembly {
            if iszero(numTokens) {
                // store the error selector to location 0x0.
                mstore(0x0, _INVALID_PARAMETER_SELECTOR)
                // return bytes 29-32 for the selector.
                revert(0x1c, 0x04)
            }
        }

        if (numTokens != newCollateralCaps.length) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        for (uint256 i; i < numTokens; ++i) {
            // Make sure the mToken is a cToken.
            if (!IMToken(mTokens[i]).isCToken()) {
                _revert(_INVALID_PARAMETER_SELECTOR);
            }

            // Do not let people collateralize assets
            // with collateralization ratio of 0.
            if (tokenData[mTokens[i]].collRatio == 0) {
                _revert(_INVALID_PARAMETER_SELECTOR);
            }

            collateralCaps[mTokens[i]] = newCollateralCaps[i];
            emit NewCollateralCap(mTokens[i], newCollateralCaps[i]);
        }
    }

    /// @notice Admin function to set market mint paused.
    /// @dev requires timelock authority if unpausing.
    /// @param mToken market token address.
    /// @param state pause or unpause.
    function setMintPaused(address mToken, bool state) external {
        _checkAuthorizedPermissions(state);

        if (!tokenData[mToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        mintPaused[mToken] = state ? 2 : 1;
        emit TokenActionPaused(mToken, "Mint Paused", state);
    }

    /// @notice Admin function to set market borrow paused.
    /// @dev requires timelock authority if unpausing.
    /// @param mToken market token address.
    /// @param state pause or unpause.
    function setBorrowPaused(address mToken, bool state) external {
        _checkAuthorizedPermissions(state);

        if (!tokenData[mToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        borrowPaused[mToken] = state ? 2 : 1;
        emit TokenActionPaused(mToken, "Borrow Paused", state);
    }

    /// @notice Admin function to set redemption paused.
    /// @dev requires timelock authority if unpausing.
    /// @param state pause or unpause.
    function setRedeemPaused(bool state) external {
        _checkAuthorizedPermissions(state);

        redeemPaused = state ? 2 : 1;
        emit ActionPaused("Redeem Paused", state);
    }

    /// @notice Admin function to set transfer paused.
    /// @dev requires timelock authority if unpausing.
    /// @param state pause or unpause.
    function setTransferPaused(bool state) external {
        _checkAuthorizedPermissions(state);

        transferPaused = state ? 2 : 1;
        emit ActionPaused("Transfer Paused", state);
    }

    /// @notice Admin function to set seize paused.
    /// @dev requires timelock authority if unpausing.
    /// @param state pause or unpause.
    function setSeizePaused(bool state) external {
        _checkAuthorizedPermissions(state);

        seizePaused = state ? 2 : 1;
        emit ActionPaused("Seize Paused", state);
    }

    /// @notice Admin function to set position folding address.
    /// @param newPositionFolding new position folding address.
    function setPositionFolding(address newPositionFolding) external {
        _checkElevatedPermissions();

        if (
            !ERC165Checker.supportsInterface(
                newPositionFolding,
                type(IPositionFolding).interfaceId
            )
        ) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Cache the current value for event log.
        address oldPositionFolding = positionFolding;

        // Assign new position folding contract.
        positionFolding = newPositionFolding;

        emit NewPositionFoldingContract(
            oldPositionFolding,
            newPositionFolding
        );
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Checks if the account should be allowed to borrow
    ///         the underlying asset of the given market.
    /// @param mToken The market to verify the borrow against.
    /// @param account The account which would borrow the asset.
    /// @param amount The amount of underlying the account would borrow.
    function canBorrow(
        address mToken,
        address account,
        uint256 amount
    ) public {
        if (borrowPaused[mToken] == 2) {
            _revert(_PAUSED_SELECTOR);
        }

        if (!tokenData[mToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        if (tokenData[mToken].accountData[account].activePosition < 2) {
            // only mTokens may call borrowAllowed if account not in market
            _checkIsToken(mToken);
            
            // The account is not in the market yet, so make them enter
            tokenData[mToken].accountData[account].activePosition = 2;
            accountAssets[account].assets.push(IMToken(mToken));

            emit TokenPositionCreated(mToken, account);
        }

        // Check if the user has sufficient liquidity to borrow,
        // with heavier error code scrutiny
        (, uint256 liquidityDeficit) = _hypotheticalLiquidityOf(
            account,
            mToken,
            0,
            amount,
            1
        );

        if (liquidityDeficit > 0) {
            revert MarketManager__InsufficientCollateral();
        }
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IMarketManager).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    function _postCollateral(
        address account,
        AccountMetadata storage accountData,
        address mToken,
        uint256 amount
    ) internal {
        if (collateralPosted[mToken] + amount > collateralCaps[mToken]) {
            revert MarketManager__CollateralCapReached();
        }

        // On collateral posting:
        // We need to flip their cooldown flag to prevent flashloan attacks.
        accountAssets[account].cooldownTimestamp = block.timestamp;
        collateralPosted[mToken] = collateralPosted[mToken] + amount;
        accountData.collateralPosted = accountData.collateralPosted + amount;
        emit CollateralPosted(account, mToken, amount);

        // If `account` does not have a position in `mToken`, open one.
        if (accountData.activePosition != 2) {
            accountData.activePosition = 2;
            accountAssets[account].assets.push(IMToken(mToken));

            emit TokenPositionCreated(mToken, account);
        }
    }

    function _removeCollateral(
        address account,
        AccountMetadata storage accountData,
        address mToken,
        uint256 amount,
        bool closePositionIfPossible
    ) internal {
        accountData.collateralPosted = accountData.collateralPosted - amount;
        collateralPosted[mToken] = collateralPosted[mToken] - amount;
        emit CollateralRemoved(account, mToken, amount);

        if (closePositionIfPossible && accountData.collateralPosted == 0) {
            _closePosition(account, accountData, IMToken(mToken));
        }
    }

    function _closePosition(
        address account,
        AccountMetadata storage accountData,
        IMToken token
    ) internal {
        // Remove `token` account position flag.
        accountData.activePosition = 1;

        // Delete token from the account’s list of assets.
        IMToken[] memory userAssetList = accountAssets[account].assets;

        // Cache asset list.
        uint256 numUserAssets = userAssetList.length;
        uint256 assetIndex = numUserAssets;

        for (uint256 i; i < numUserAssets; ++i) {
            if (userAssetList[i] == token) {
                assetIndex = i;
                break;
            }
        }

        // Validate we found the asset and remove 1 from numUserAssets
        // so it corresponds to last element index now starting at index 0.
        // This is an additional runtime invariant check for extra security.
        if (assetIndex >= numUserAssets--) {
            revert MarketManager__InvariantError();
        }

        // Copy last item in list to location of item to be removed.
        IMToken[] storage storedList = accountAssets[account].assets;
        // Copy the last market index slot to assetIndex.
        storedList[assetIndex] = storedList[numUserAssets];
        // Remove the last element to remove `token` from account asset list.
        storedList.pop();

        emit TokenPositionClosed(address(token), account);
    }

    /// @notice Checks if the account should be allowed to redeem tokens
    ///         in the given market.
    /// @param mToken The market to verify the redeem against.
    /// @param account The account which would redeem the tokens.
    /// @param amount The number of `mToken` to redeem for
    ///               the underlying asset in the market.
    function _canRedeem(
        address mToken,
        address account,
        uint256 amount
    ) internal view {
        if (redeemPaused == 2) {
            _revert(_PAUSED_SELECTOR);
        }

        if (!tokenData[mToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        // We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        // as well as short term price manipulations if the dynamic dual oracle
        // fails to protect the market somehow.
        if (
            accountAssets[account].cooldownTimestamp + MIN_HOLD_PERIOD >
            block.timestamp
        ) {
            revert MarketManager__MinimumHoldPeriod();
        }

        // If the account does not have an active position in the token,
        // then we can bypass the liquidity check.
        if (tokenData[mToken].accountData[account].activePosition < 2) {
            return;
        }

        // Check account liquidity with hypothetical redemption.
        (, uint256 liquidityDeficit) = _hypotheticalLiquidityOf(
            account,
            mToken,
            amount,
            0,
            2
        );

        if (liquidityDeficit > 0) {
            revert MarketManager__InsufficientCollateral();
        }
    }

    /// @notice Checks if the liquidation should be allowed to occur.
    /// @param debtToken Asset which was borrowed by the borrower.
    /// @param collateralToken Asset which was used as collateral and will be seized.
    /// @param account The address of the account to be liquidated.
    /// @param debtAmount The amount of `debtToken` desired to liquidate,
    ///                   0 means maximum liquidation allowed will be executed.
    /// @param liquidateExact Whether the liquidator wants to liquidate a specific amount of debt,
    ///                       used in conjunction with `debtAmount`.
    /// @return The maximum amount of `debtToken` that can be repaid during liquidation.
    /// @return Current price for `debtToken`.
    /// @return Current price for `collateralToken`.
    function _canLiquidate(
        address debtToken,
        address collateralToken,
        address account,
        uint256 debtAmount,
        bool liquidateExact
    ) internal view returns (uint256, uint256, uint256) {
        if (!tokenData[debtToken].isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        MarketToken storage cToken = tokenData[collateralToken];

        if (!cToken.isListed) {
            _revert(_TOKEN_NOT_LISTED_SELECTOR);
        }

        // Do not let people liquidate 0 collateralization ratio assets.
        if (cToken.collRatio == 0) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Calculate the users lFactor.
        LiqData memory data = _LiquidationStatusOf(
            account,
            debtToken,
            collateralToken
        );

        if (data.lFactor == 0) {
            revert MarketManager__NoLiquidationAvailable();
        }

        uint256 maxAmount;
        uint256 debtToCollateralRatio;
        {
            uint256 cFactor = cToken.baseCFactor +
                ((cToken.cFactorCurve * data.lFactor) / WAD);
            uint256 incentive = cToken.liqBaseIncentive +
                ((cToken.liqCurve * data.lFactor) / WAD);
            maxAmount =
                (cFactor * IMToken(debtToken).debtBalanceCached(account)) /
                WAD;

            // Get the exchange rate, and calculate the number of 
            // collateral tokens to seize.
            debtToCollateralRatio =
                (incentive * data.debtTokenPrice * WAD) /
                (data.collateralTokenPrice *
                    IMToken(collateralToken).exchangeRateCached());
        }

        if (!liquidateExact) {
            debtAmount = maxAmount;
        }

        uint256 amountAdjusted = (debtAmount *
            (10 ** IERC20(collateralToken).decimals())) /
            (10 ** IERC20(debtToken).decimals());
        uint256 liquidatedTokens = (amountAdjusted * debtToCollateralRatio) /
            WAD;

        uint256 collateralAvailable = cToken
            .accountData[account]
            .collateralPosted;
        if (liquidateExact) {
            if (
                debtAmount > maxAmount ||
                liquidatedTokens > collateralAvailable
            ) {
                // Make sure that the liquidation limit,
                // and collateral posted >= amount.
                _revert(_INVALID_PARAMETER_SELECTOR);
            }
        } else {
            if (liquidatedTokens > collateralAvailable) {
                debtAmount =
                    (debtAmount * collateralAvailable) /
                    liquidatedTokens;
                liquidatedTokens = collateralAvailable;
            }
        }

        // Calculate the maximum amount of debt that can be liquidated
        // and what collateral will be received.
        return (
            debtAmount,
            liquidatedTokens,
            (liquidatedTokens * cToken.liqFee) / WAD
        );
    }

    /// @notice Reduces `accounts`'s posted collateral if necessary for their
    ///         desired action.
    /// @param account The account to potential reduce posted collateral for.
    /// @param mToken The address of the mToken to potentially reduce 
    ///               collateral for.
    /// @param balance The cToken share balance of `account`.
    /// @param amount The maximum amount of shares that could be removed as 
    ///               collateral.
    /// @param forceReduce Whether to force reduce `account`'s collateral
    ///                    for not.
    function _reduceCollateralIfNecessary(
        address account,
        address mToken,
        uint256 balance,
        uint256 amount,
        bool forceReduce
    ) internal {
        AccountMetadata storage accountData = tokenData[mToken].accountData[
            account
        ];
        if (forceReduce) {
            _removeCollateral(account, accountData, mToken, amount, false);
            return;
        }

        uint256 balanceRequired = accountData.collateralPosted + amount;

        if (balance < balanceRequired) {
            _removeCollateral(
                account,
                accountData,
                mToken,
                balanceRequired - balance,
                false
            );
        }
    }

    /// @notice Multiplies `value` by 1e14 to convert it from `basis points`
    ///         to WAD.
    /// @dev Internal helper function for easily converting between scalars.
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        return value * 1e14;
    }

    /// @dev Checks whether the caller has sufficient permissions.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller has sufficient permissions based on `state`,
    /// turning something off is less "risky" than enabling something,
    /// so `state` = true has reduced permissioning compared to `state` = false.
    function _checkAuthorizedPermissions(bool state) internal view {
        if (state) {
            if (!centralRegistry.hasDaoPermissions(msg.sender)) {
                _revert(_UNAUTHORIZED_SELECTOR);
            }
        } else {
            if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
                _revert(_UNAUTHORIZED_SELECTOR);
            }
        }
    }

    /// @dev Checks whether the caller is the desired mToken contract.
    function _checkIsToken(address mToken) internal view {
        /// @solidity memory-safe-assembly
        assembly {
            // Equal to if (msg.sender != mToken)
            if iszero(eq(caller(), mToken)) {
                mstore(0x00, _UNAUTHORIZED_SELECTOR)
                // Return bytes 29-32 for the selector.
                revert(0x1c, 0x04)
            }
        }
    }
}
