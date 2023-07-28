// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance Lendtroller
/// @notice Manages risk within the lending & collateral markets
contract Lendtroller is ILendtroller {
    /// CONSTANTS ///

    ICentralRegistry public immutable centralRegistry;
    /// @notice Indicator that this is a Lendtroller contract (for introspection)
    bool public constant override isLendtroller = true;
    /// @notice closeFactorScaled must be strictly greater than this value
    uint256 internal constant closeFactorMinScaled = 0.05e18; // 0.05
    /// @notice closeFactorScaled must not exceed this value
    uint256 internal constant closeFactorMaxScaled = 0.9e18; // 0.9
    /// @notice No collateralFactorScaled may exceed this value
    uint256 internal constant collateralFactorMaxScaled = 0.9e18; // 0.9
    /// @notice Scaler for floating point math
    uint256 internal constant expScale = 1e18;
    /// @notice Minimum hold time on CToken to prevent oracle price attacks
    uint256 internal constant minimumHoldPeriod = 15 minutes;

    // GaugePool contract address
    address public immutable override gaugePool;

    /// STORAGE ///

    /// @notice The Pause Guardian can pause certain actions as a safety mechanism.
    ///  Actions which allow users to remove their own assets cannot be paused.
    ///  Liquidation / seizing / transfer can only be paused globally, not by market.
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    /// @notice The borrowCapGuardian can set borrowCaps to any number for any market.
    /// Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    /// @notice Borrow caps enforced by borrowAllowed for each mToken address.
    /// Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint256) public borrowCaps;

    /// @notice Multiplier used to calculate the maximum repayAmount
    ///         when liquidating a borrow
    uint256 public closeFactorScaled;

    /// @notice Multiplier representing the discount on collateral that
    ///         a liquidator receives
    uint256 public liquidationIncentiveScaled;

    /// @notice Max number of assets a single account can participate in
    ///         (borrow or use as collateral)
    uint256 public maxAssets;

    /// @notice Official mapping of mTokens -> Market metadata
    /// @dev Used e.g. to determine if a market is supported
    mapping(address => ILendtroller.Market) public markets;

    /// @notice A list of all markets
    IMToken[] public allMarkets;

    /// @notice Per-account mapping of "assets you are in", capped by maxAssets
    mapping(address => IMToken[]) public accountAssets;

    /// Whether market can be used for collateral or not
    mapping(IMToken => bool) public marketDisableCollateral;
    mapping(address => mapping(IMToken => bool)) public userDisableCollateral;

    // PositionFolding contract address
    address public override positionFolding;

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "lendtroller: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "lendtroller: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address gaugePool_) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "lendtroller: invalid central registry"
        );
        centralRegistry = centralRegistry_;
        gaugePool = gaugePool_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Returns the assets an account has entered
    /// @param account The address of the account to pull assets for
    /// @return A dynamic list with the assets the account has entered
    function getAssetsIn(
        address account
    ) external view returns (IMToken[] memory) {
        IMToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /// @notice Returns whether the given account is entered in the given asset
    /// @param account The address of the account to check
    /// @param mToken The mToken to check
    /// @return True if the account is in the asset, otherwise false.
    function checkMembership(
        address account,
        IMToken mToken
    ) external view returns (bool) {
        return markets[address(mToken)].accountMembership[account];
    }

    /// @notice Removes asset from sender's account liquidity calculation
    /// @dev Sender must not have an outstanding borrow balance in the asset,
    ///  or be providing necessary collateral for an outstanding borrow.
    /// @param mTokenAddress The address of the asset to be removed
    function exitMarket(address mTokenAddress) external override {
        IMToken mToken = IMToken(mTokenAddress);
        // Get sender tokensHeld and amountOwed underlying from the mToken
        (uint256 tokensHeld, uint256 amountOwed, ) = mToken.getAccountSnapshot(
            msg.sender
        );

        // Do not let them leave if they owe a balance
        if (amountOwed != 0) {
            revert NonZeroBorrowBalance();
        }

        // Fail if the sender is not permitted to redeem all of their tokens
        redeemAllowedInternal(mTokenAddress, msg.sender, tokensHeld);

        ILendtroller.Market storage marketToExit = markets[address(mToken)];

        // Return true if the sender is not already ‘in’ the market
        if (!marketToExit.accountMembership[msg.sender]) {
            return;
        }

        // Set mToken account membership to false
        delete marketToExit.accountMembership[msg.sender];

        // Delete mToken from the account’s list of assets
        IMToken[] memory userAssetList = accountAssets[msg.sender];

        // Cache asset list
        uint256 numUserAssets = userAssetList.length;
        uint256 assetIndex = numUserAssets;

        for (uint256 i; i < numUserAssets; ++i) {
            if (userAssetList[i] == mToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant
        // data structure is broken
        assert(assetIndex < numUserAssets);

        // copy last item in list to location of item to be removed,
        // reduce length by 1
        IMToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(mToken, msg.sender);
    }

    /// Policy Hooks

    /// @notice Checks if the account should be allowed to mint tokens
    ///         in the given market
    /// @param mToken The market to verify the mint against
    function mintAllowed(address mToken, address) external view override {
        if (mintGuardianPaused[mToken]) {
            revert Paused();
        }

        if (!markets[mToken].isListed) {
            revert MarketNotListed(mToken);
        }
    }

    /// @notice Checks if the account should be allowed to redeem tokens
    ///         in the given market
    /// @param mToken The market to verify the redeem against
    /// @param redeemer The account which would redeem the tokens
    /// @param redeemTokens The number of mTokens to exchange
    ///                     for the underlying asset in the market
    function redeemAllowed(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) external view override {
        redeemAllowedInternal(mToken, redeemer, redeemTokens);
    }

    /// @notice Checks if the account should be allowed to borrow
    ///         the underlying asset of the given market
    /// @param mToken The market to verify the borrow against
    /// @param borrower The account which would borrow the asset
    /// @param borrowAmount The amount of underlying the account would borrow
    function borrowAllowed(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external override {
        if (borrowGuardianPaused[mToken]) {
            revert Paused();
        }

        if (!markets[mToken].isListed) {
            revert MarketNotListed(mToken);
        }

        if (!markets[mToken].accountMembership[borrower]) {
            // only mTokens may call borrowAllowed if borrower not in market
            if (msg.sender != mToken) {
                revert AddressUnauthorized();
            }

            addToMarketInternal(IMToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert(markets[mToken].accountMembership[borrower]);
        }

        (, uint256 errorCode) = getPriceRouter().getPrice(mToken, true, false);
        if (errorCode > 0) {
            revert PriceError();
        }

        uint256 borrowCap = borrowCaps[mToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint256 totalBorrows = IMToken(mToken).totalBorrows();
            uint256 nextTotalBorrows = totalBorrows + borrowAmount;

            if (nextTotalBorrows >= borrowCap) {
                revert BorrowCapReached();
            }
        }

        (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            borrower,
            IMToken(mToken),
            0,
            borrowAmount
        );

        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    /// @notice Checks if the account should be allowed to repay a borrow
    ///         in the given market
    /// @param mToken The market to verify the repay against
    function repayAllowed(
        address mToken,
        address
    ) external view override {
        if (!markets[mToken].isListed) {
            revert MarketNotListed(mToken);
        }
    }

    /// @notice Checks if the liquidation should be allowed to occur
    /// @param mTokenBorrowed Asset which was borrowed by the borrower
    /// @param mTokenCollateral Asset which was used as collateral and will be seized
    /// @param borrower The address of the borrower
    /// @param repayAmount The amount of underlying being repaid
    function liquidateUserAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external view override {
        if (!markets[mTokenBorrowed].isListed) {
            revert MarketNotListed(mTokenBorrowed);
        }
        if (!markets[mTokenCollateral].isListed) {
            revert MarketNotListed(mTokenCollateral);
        }

        // The borrower must have shortfall in order to be liquidatable
        (, uint256 shortfall) = getAccountLiquidityInternal(borrower);
        if (shortfall == 0) {
            revert InsufficientShortfall();
        }

        // The liquidator may not close out more collateral than
        // what is allowed by the closeFactor
        uint256 borrowBalance = IMToken(mTokenBorrowed).borrowBalanceStored(
            borrower
        );
        uint256 maxClose = (closeFactorScaled * borrowBalance) / expScale;

        if (repayAmount > maxClose) {
            revert TooMuchRepay();
        }
    }

    /// @notice Checks if the seizing of assets should be allowed to occur
    /// @param mTokenCollateral Asset which was used as collateral
    ///                         and will be seized
    /// @param mTokenBorrowed Asset which was borrowed by the borrower
    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address,
        address
    ) external view override {
        if (seizeGuardianPaused) {
            revert Paused();
        }

        if (!markets[mTokenBorrowed].isListed) {
            revert MarketNotListed(mTokenBorrowed);
        }
        if (!markets[mTokenCollateral].isListed) {
            revert MarketNotListed(mTokenCollateral);
        }

        if (
            IMToken(mTokenCollateral).lendtroller() !=
            IMToken(mTokenBorrowed).lendtroller()
        ) {
            revert LendtrollerMismatch();
        }
    }

    /// @notice Checks if the account should be allowed to transfer tokens
    ///         in the given market
    /// @param mToken The market to verify the transfer against
    /// @param src The account which sources the tokens
    /// @param transferTokens The number of mTokens to transfer
    function transferAllowed(
        address mToken,
        address src,
        address,
        uint256 transferTokens
    ) external view override {
        if (transferGuardianPaused) {
            revert Paused();
        }

        redeemAllowedInternal(mToken, src, transferTokens);
    }

    /// @notice Calculate number of tokens of collateral asset to
    ///         seize given an underlying amount
    /// @dev Used in liquidation (called in mToken._liquidateUser)
    /// @param mTokenBorrowed The address of the borrowed mToken
    /// @param mTokenCollateral The address of the collateral mToken
    /// @param actualRepayAmount The amount of mTokenBorrowed underlying to
    ///                          convert into mTokenCollateral tokens
    /// @return uint The number of mTokenCollateral tokens to be seized in a liquidation
    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint256 actualRepayAmount
    ) external view override returns (uint256) {
        /// Read oracle prices for borrowed and collateral markets
        (uint256 highPrice, uint256 highPriceError) = getPriceRouter()
            .getPrice(mTokenBorrowed, true, false);
        (uint256 lowPrice, uint256 lowPriceError) = getPriceRouter().getPrice(
            mTokenCollateral,
            true,
            true
        );

        /// Validate that we were able to securely query prices from the dual oracle
        if (highPriceError == 2 || lowPriceError == 2) {
            revert PriceError();
        }

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        //  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        //  seizeTokens = seizeAmount / exchangeRate
        //   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
        uint256 exchangeRateScaled = IMToken(mTokenCollateral)
            .exchangeRateStored();
        uint256 numerator = liquidationIncentiveScaled * highPrice;
        uint256 denominator = lowPrice * exchangeRateScaled;
        uint256 ratio = (numerator * expScale) / denominator;
        uint256 seizeTokens = (ratio * actualRepayAmount) / expScale;

        return seizeTokens;
    }

    /// User Custom Functions

    /// @notice User set collateral on/off option for market token
    /// @param mTokens The addresses of the markets (tokens) to
    ///                change the collateral on/off option
    /// @param disableCollateral Disable mToken from collateral
    function setUserDisableCollateral(
        IMToken[] calldata mTokens,
        bool disableCollateral
    ) external {
        uint256 numMarkets = mTokens.length;
        if (numMarkets == 0) {
            revert InvalidValue();
        }

        for (uint256 i; i < numMarkets; ++i) {
            userDisableCollateral[msg.sender][mTokens[i]] = disableCollateral;
            emit SetUserDisableCollateral(
                msg.sender,
                mTokens[i],
                disableCollateral
            );
        }

        (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            msg.sender,
            IMToken(address(0)),
            0,
            0
        );

        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    /// Admin Functions

    /// @notice Sets the closeFactor used when liquidating borrows
    /// @dev Admin function to set closeFactor
    /// @param newCloseFactorScaled New close factor, scaled by 1e18
    function _setCloseFactor(
        uint256 newCloseFactorScaled
    ) external onlyElevatedPermissions {
        uint256 oldCloseFactorScaled = closeFactorScaled;
        closeFactorScaled = newCloseFactorScaled;
        emit NewCloseFactor(oldCloseFactorScaled, closeFactorScaled);
    }

    /// @notice Sets the collateralFactor for a market
    /// @dev Admin function to set per-market collateralFactor
    /// @param mToken The market to set the factor on
    /// @param newCollateralFactorScaled The new collateral factor, scaled by 1e18
    function _setCollateralFactor(
        IMToken mToken,
        uint256 newCollateralFactorScaled
    ) external onlyElevatedPermissions {
        // Verify market is listed
        ILendtroller.Market storage market = markets[address(mToken)];
        if (!market.isListed) {
            revert MarketNotListed(address(mToken));
        }

        // Check collateral factor is not above maximum allowed
        if (collateralFactorMaxScaled < newCollateralFactorScaled) {
            revert InvalidValue();
        }

        (, uint256 lowPriceError) = getPriceRouter().getPrice(
            address(mToken),
            true,
            true
        );

        // Validate that we got a price and that collateral factor != 0
        if (lowPriceError == 2 || newCollateralFactorScaled != 0) {
            revert PriceError();
        }

        // Cache the current value for event log
        uint256 oldCollateralFactorScaled = market.collateralFactorScaled;

        // Assign new collateral factor
        market.collateralFactorScaled = newCollateralFactorScaled;

        emit NewCollateralFactor(
            mToken,
            oldCollateralFactorScaled,
            newCollateralFactorScaled
        );
    }

    /// @notice Sets liquidationIncentive
    /// @dev Admin function to set liquidationIncentive
    /// @param newLiquidationIncentiveScaled New liquidationIncentive scaled by 1e18
    function _setLiquidationIncentive(
        uint256 newLiquidationIncentiveScaled
    ) external onlyElevatedPermissions {
        // Cache the current value for event log
        uint256 oldLiquidationIncentiveScaled = liquidationIncentiveScaled;

        // Assign new liquidation incentive
        liquidationIncentiveScaled = newLiquidationIncentiveScaled;

        emit NewLiquidationIncentive(
            oldLiquidationIncentiveScaled,
            newLiquidationIncentiveScaled
        );
    }

    /// @notice Add the market to the markets mapping and set it as listed
    /// @dev Admin function to set isListed and add support for the market
    /// @param mToken The address of the market (token) to list
    function _supportMarket(IMToken mToken) external onlyElevatedPermissions {
        if (markets[address(mToken)].isListed) {
            revert MarketAlreadyListed();
        }

        mToken.tokenType(); // Sanity check to make sure its really a mToken

        ILendtroller.Market storage market = markets[address(mToken)];
        market.isListed = true;
        market.collateralFactorScaled = 0;

        _addMarketInternal(address(mToken));

        emit MarketListed(mToken);
    }

    /// @notice Set the given borrow caps for the given mToken markets.
    ///   Borrowing that brings total borrows to or above borrow cap will revert.
    /// @dev Admin or borrowCapGuardian function to set the borrow caps.
    ///   A borrow cap of 0 corresponds to unlimited borrowing.
    /// @param mTokens The addresses of the markets (tokens) to
    ///                change the borrow caps for
    /// @param newBorrowCaps The new borrow cap values in underlying to be set.
    ///   A value of 0 corresponds to unlimited borrowing.
    function _setMarketBorrowCaps(
        IMToken[] calldata mTokens,
        uint256[] calldata newBorrowCaps
    ) external {
        if (
            !centralRegistry.hasElevatedPermissions(msg.sender) &&
            msg.sender != borrowCapGuardian
        ) {
            revert AddressUnauthorized();
        }
        uint256 numMarkets = mTokens.length;

        if (numMarkets == 0 || numMarkets != newBorrowCaps.length) {
            revert InvalidValue();
        }

        for (uint256 i; i < numMarkets; ++i) {
            borrowCaps[address(mTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(mTokens[i], newBorrowCaps[i]);
        }
    }

    /// @notice Set collateral on/off option for market token
    /// @dev Admin can set the collateral on or off
    /// @param mTokens The addresses of the markets (tokens) to change
    ///                the collateral on/off option
    /// @param disableCollateral Disable mToken from collateral
    function _setDisableCollateral(
        IMToken[] calldata mTokens,
        bool disableCollateral
    ) external onlyElevatedPermissions {
        uint256 numMarkets = mTokens.length;
        if (numMarkets == 0) {
            revert InvalidValue();
        }

        for (uint256 i; i < numMarkets; ++i) {
            marketDisableCollateral[mTokens[i]] = disableCollateral;
            emit SetDisableCollateral(mTokens[i], disableCollateral);
        }
    }

    /// @notice Admin function to change the Borrow Cap Guardian
    /// @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
    function _setBorrowCapGuardian(
        address newBorrowCapGuardian
    ) external onlyElevatedPermissions {
        // Cache the current value for event log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Assign new guardian
        borrowCapGuardian = newBorrowCapGuardian;

        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /// @notice Returns market status
    /// @param mToken market token address
    function getIsMarkets(
        address mToken
    ) external view override returns (bool, uint256) {
        return (
            markets[mToken].isListed,
            markets[mToken].collateralFactorScaled
        );
    }

    /// @notice Returns if user joined market
    /// @param mToken market token address
    /// @param user user address
    function getAccountMembership(
        address mToken,
        address user
    ) external view override returns (bool) {
        return markets[mToken].accountMembership[user];
    }

    /// @notice Returns all markets
    function getAllMarkets()
        external
        view
        override
        returns (IMToken[] memory)
    {
        return allMarkets;
    }

    /// @notice Returns all markets user joined
    /// @param user user address
    function getAccountAssets(
        address user
    ) external view override returns (IMToken[] memory) {
        return accountAssets[user];
    }

    /// PUBLIC FUNCTIONS ///

    function getPriceRouter() public view returns (IPriceRouter) {
        return IPriceRouter(centralRegistry.priceRouter());
    }

    /// @notice Add assets to be included in account liquidity calculation
    /// @param mTokens The list of addresses of the mToken markets to be enabled
    /// @return uint array: 0 = market not entered; 1 = market entered
    function enterMarkets(
        address[] memory mTokens
    ) public override returns (uint256[] memory) {
        uint256 numCTokens = mTokens.length;

        uint256[] memory results = new uint256[](numCTokens);
        for (uint256 i; i < numCTokens; ++i) {
            results[i] = addToMarketInternal(IMToken(mTokens[i]), msg.sender);
        }

        // Return a list of markets joined & not joined (1 = joined, 0 = not joined)
        return results;
    }

    /// Liquidity/Liquidation Calculations

    /// @notice Determine the current account liquidity wrt collateral requirements
    /// @return liquidity of account in excess of collateral requirements
    /// @return shortfall of account below collateral requirements
    function getAccountLiquidity(
        address account
    ) public view returns (uint256, uint256) {
        (
            uint256 liquidity,
            uint256 shortfall
        ) = getHypotheticalAccountLiquidityInternal(
                account,
                IMToken(address(0)),
                0,
                0
            );

        return (liquidity, shortfall);
    }

    /// @notice Determine the current account liquidity wrt collateral requirements
    /// @return uint total collateral amount of user
    /// @return uint max borrow amount of user
    /// @return uint total borrow amount of user
    function getAccountPosition(
        address account
    ) public view override returns (uint256, uint256, uint256) {
        (
            uint256 sumCollateral,
            uint256 maxBorrow,
            uint256 sumBorrow
        ) = getHypotheticalAccountPositionInternal(
                account,
                IMToken(address(0)),
                0,
                0
            );

        return (sumCollateral, maxBorrow, sumBorrow);
    }

    /// @notice Determine what the account liquidity would be if
    ///         the given amounts were redeemed/borrowed
    /// @param mTokenModify The market to hypothetically redeem/borrow in
    /// @param account The account to determine liquidity for
    /// @param redeemTokens The number of tokens to hypothetically redeem
    /// @param borrowAmount The amount of underlying to hypothetically borrow
    /// @return uint hypothetical account liquidity in excess
    ///              of collateral requirements,
    /// @return uint hypothetical account shortfall below collateral requirements)
    function getHypotheticalAccountLiquidity(
        address account,
        address mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) public view returns (uint256, uint256) {
        (
            uint256 liquidity,
            uint256 shortfall
        ) = getHypotheticalAccountLiquidityInternal(
                account,
                IMToken(mTokenModify),
                redeemTokens,
                borrowAmount
            );

        return (liquidity, shortfall);
    }

    /// @notice Admin function to change the Pause Guardian
    /// @param newPauseGuardian The address of the new Pause Guardian
    function _setPauseGuardian(
        address newPauseGuardian
    ) public onlyElevatedPermissions {
        // Cache the current value for event log
        address oldPauseGuardian = pauseGuardian;

        // Assign new guardian
        pauseGuardian = newPauseGuardian;

        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }

    /// @notice Admin function to set market mint paused
    /// @param mToken market token address
    /// @param state pause or unpause
    function _setMintPaused(IMToken mToken, bool state) public returns (bool) {
        if (!markets[address(mToken)].isListed) {
            revert MarketNotListed(address(mToken));
        }

        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert AddressUnauthorized();
        }
        if (!hasDaoPerms && state != true) {
            revert AddressUnauthorized();
        }

        mintGuardianPaused[address(mToken)] = state;
        emit ActionPaused(mToken, "Mint", state);
        return state;
    }

    /// @notice Admin function to set market borrow paused
    /// @param mToken market token address
    /// @param state pause or unpause
    function _setBorrowPaused(
        IMToken mToken,
        bool state
    ) public returns (bool) {
        if (!markets[address(mToken)].isListed) {
            revert MarketNotListed(address(mToken));
        }

        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert AddressUnauthorized();
        }
        if (!hasDaoPerms && state != true) {
            revert AddressUnauthorized();
        }

        borrowGuardianPaused[address(mToken)] = state;
        emit ActionPaused(mToken, "Borrow", state);
        return state;
    }

    /// @notice Admin function to set transfer paused
    /// @param state pause or unpause
    function _setTransferPaused(bool state) public returns (bool) {
        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert AddressUnauthorized();
        }
        if (!hasDaoPerms && state != true) {
            revert AddressUnauthorized();
        }

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    /// @notice Admin function to set seize paused
    /// @param state pause or unpause
    function _setSeizePaused(bool state) public returns (bool) {
        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert AddressUnauthorized();
        }
        if (!hasDaoPerms && state != true) {
            revert AddressUnauthorized();
        }

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    /// @notice Admin function to set position folding contract address
    /// @param _newPositionFolding new position folding contract address
    function _setPositionFolding(
        address _newPositionFolding
    ) public onlyElevatedPermissions {
        // Cache the current value for event log
        address oldPositionFolding = positionFolding;

        // Assign new position folding contract
        positionFolding = _newPositionFolding;

        emit NewPositionFoldingContract(oldPositionFolding, positionFolding);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Add the market to the borrower's "assets in"
    ///         for liquidity calculations
    /// @param mToken The market to enter
    /// @param borrower The address of the account to modify
    /// @return uint 0 = unable to enter market; 1 = market entered
    function addToMarketInternal(
        IMToken mToken,
        address borrower
    ) internal returns (uint256) {
        ILendtroller.Market storage marketToJoin = markets[address(mToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return 0;
        }

        if (marketToJoin.accountMembership[borrower]) {
            // market already joined
            return 0;
        }

        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(mToken);

        emit MarketEntered(mToken, borrower);

        // Indicates that a market was successfully entered
        return 1;
    }

    /// @notice Checks if the account should be allowed to redeem tokens
    ///         in the given market
    /// @param mToken The market to verify the redeem against
    /// @param redeemer The account which would redeem the tokens
    /// @param redeemTokens The number of mTokens to exchange for
    ///                     the underlying asset in the market
    function redeemAllowedInternal(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) internal view {
        if (!markets[mToken].isListed) {
            revert MarketNotListed(mToken);
        }

        if(uint256(IMToken(mToken).getBorrowTimestamp(redeemer)) + minimumHoldPeriod > block.timestamp) {
            revert MinimumHoldPeriod();
        }

        // If the redeemer is not 'in' the market, then we can bypass
        // the liquidity check
        if (!markets[mToken].accountMembership[redeemer]) {
            return;
        }

        // Otherwise, perform a hypothetical liquidity check to guard against
        // shortfall
        (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            redeemer,
            IMToken(mToken),
            redeemTokens,
            0
        );

        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    /// @notice Determine the current account liquidity wrt collateral requirements
    /// @return liquidity of account in excess of collateral requirements
    /// @return shortfall of account below collateral requirements
    function getAccountLiquidityInternal(
        address account
    ) internal view returns (uint256, uint256) {
        return
            getHypotheticalAccountLiquidityInternal(
                account,
                IMToken(address(0)),
                0,
                0
            );
    }

    /// @notice Determine what the account liquidity would be if
    ///         the given amounts were redeemed/borrowed
    /// @param mTokenModify The market to hypothetically redeem/borrow in
    /// @param account The account to determine liquidity for
    /// @param redeemTokens The number of tokens to hypothetically redeem
    /// @param borrowAmount The amount of underlying to hypothetically borrow
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return uint hypothetical account liquidity in excess
    ///              of collateral requirements,
    /// @return uint hypothetical account shortfall below collateral requirements)
    function getHypotheticalAccountLiquidityInternal(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) internal view returns (uint256, uint256) {
        (
            ,
            uint256 maxBorrow,
            uint256 sumBorrowPlusEffects
        ) = getHypotheticalAccountPositionInternal(
                account,
                mTokenModify,
                redeemTokens,
                borrowAmount
            );

        // These will not underflow from unchecked as the underflow condition
        // is checked prior
        if (maxBorrow > sumBorrowPlusEffects) {
            unchecked {
                return (maxBorrow - sumBorrowPlusEffects, 0);
            }
        } else {
            unchecked {
                return (0, sumBorrowPlusEffects - maxBorrow);
            }
        }
    }

    /// @notice Determine what the account liquidity would be if
    ///         the given amounts were redeemed/borrowed
    /// @param mTokenModify The market to hypothetically redeem/borrow in
    /// @param account The account to determine liquidity for
    /// @param redeemTokens The number of tokens to hypothetically redeem
    /// @param borrowAmount The amount of underlying to hypothetically borrow
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return sumCollateral total collateral amount of user
    /// @return maxBorrow max borrow amount of user
    /// @return sumBorrowPlusEffects total borrow amount of user
    function getHypotheticalAccountPositionInternal(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    )
        internal
        view
        returns (
            uint256 sumCollateral,
            uint256 maxBorrow,
            uint256 sumBorrowPlusEffects
        )
    {
        uint256 numAccountAssets = accountAssets[account].length;
        IMToken asset;
        bool collateralEnabled;

        // For each asset the account is in
        for (uint256 i; i < numAccountAssets; ++i) {
            asset = accountAssets[account][i];
            collateralEnabled =
                marketDisableCollateral[asset] == false &&
                userDisableCollateral[account][asset] == false;

            (
                uint256 mTokenBalance,
                uint256 borrowBalance,
                uint256 exchangeRateScaled
            ) = asset.getAccountSnapshot(account);

            if (collateralEnabled) {
                (uint256 lowerPrice, uint256 errorCode) = getPriceRouter()
                    .getPrice(address(asset), true, true);
                if (errorCode == 2) {
                    revert PriceError();
                }

                uint256 assetValue = (((mTokenBalance * exchangeRateScaled) /
                    expScale) * lowerPrice) / expScale;

                sumCollateral += assetValue;
                maxBorrow +=
                    (assetValue *
                        markets[address(asset)].collateralFactorScaled) /
                    expScale;
            }

            {
                (uint256 higherPrice, uint256 errorCode) = getPriceRouter()
                    .getPrice(address(asset), true, false);
                if (errorCode == 2) {
                    revert PriceError();
                }

                sumBorrowPlusEffects += ((higherPrice * borrowBalance) /
                    expScale);

                // Calculate effects of interacting with mTokenModify
                if (asset == mTokenModify) {
                    if (collateralEnabled) {
                        // Pre-compute a conversion factor
                        // from tokens -> ether (normalized price value)
                        uint256 tokensToDenom = (((markets[address(asset)]
                            .collateralFactorScaled * exchangeRateScaled) /
                            expScale) * higherPrice) / expScale;

                        // redeem effect
                        sumBorrowPlusEffects += ((tokensToDenom *
                            redeemTokens) / expScale);
                    }

                    // borrow effect
                    sumBorrowPlusEffects += ((higherPrice * borrowAmount) /
                        expScale);
                }
            }
        }
    }

    /// @notice Add the market to the markets mapping and set it as listed
    /// @param mToken The address of the market (token) to list
    function _addMarketInternal(address mToken) internal {
        uint256 numMarkets = allMarkets.length;

        for (uint256 i; i < numMarkets; ++i) {
            if (allMarkets[i] == IMToken(mToken)) {
                revert MarketAlreadyListed();
            }
        }
        allMarkets.push(IMToken(mToken));
    }
}
