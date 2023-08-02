// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IMToken, accountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { ICToken } from "contracts/interfaces/market/ICToken.sol";
import { BasePositionVault } from "contracts/deposits/adaptors/BasePositionVault.sol";

/// @title Curvance Lendtroller
/// @notice Manages risk within the lending markets
contract Lendtroller is ILendtroller {
    /// TYPES ///

    struct UserData {
        mapping(IMToken => bool) collateralDisabled;
        uint256 lastBorrowTimestamp;
    }

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
    // @notice GaugePool contract address
    address public immutable override gaugePool;

    // @dev `bytes4(keccak256(bytes("Lendtroller_InvalidValue()")))`
    uint256 internal constant _INVALID_VALUE_SELECTOR = 0x74ebdb4f;

    // @dev `bytes4(keccak256(bytes("Lendtroller_InsufficientShortfall()")))`
    uint256 internal constant _INSUFFICIENT_SHORTFALL_SELECTOR = 0xa160c28b;

    /// STORAGE ///

    /// @notice The Pause Guardian can pause certain actions as a safety mechanism.
    ///  Actions which allow users to remove their own assets cannot be paused.
    ///  Liquidation / seizing / transfer can only be paused globally, not by market.
    address public pauseGuardian;
    uint256 public transferPaused = 1;
    uint256 public seizePaused = 1;
    mapping(address => bool) public mintPaused; // Token => Mint Paused
    mapping(address => bool) public borrowPaused; // Token => Borrow Paused
    mapping(address => uint256) public borrowCaps; // Token => Borrow Cap; 0 = unlimited

    /// @notice The borrowCapGuardian can set borrowCaps to any number for any market.
    /// Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    /// @notice Multiplier used to calculate the maximum repayAmount
    ///         when liquidating a borrow
    uint256 public closeFactorScaled;

    /// @notice Multiplier representing the discount on collateral that
    ///         a liquidator receives
    uint256 public liquidationIncentiveScaled;

    /// @notice Official mapping of mTokens -> Market metadata
    /// @dev Used e.g. to determine if a market is supported
    mapping(address => ILendtroller.Market) public markets;

    /// @notice A list of all markets
    IMToken[] public allMarkets;

    /// @notice Per-account mapping of "assets you are in", capped by maxAssets
    mapping(address => IMToken[]) public accountAssets;

    /// @notice user => UserData (IMToken => Collateralizable, lastBorrowTimestamp)
    mapping(address => UserData) public userData;

    // PositionFolding contract address
    address public override positionFolding;

    /// Errors ///

    error Lendtroller_MarketNotListed();
    error Lendtroller_MarketAlreadyListed();
    error Lendtroller_AddressAlreadyJoined();
    error Lendtroller_Paused();
    error Lendtroller_InsufficientLiquidity();
    error Lendtroller_PriceError();
    error Lendtroller_HasActiveLoan();
    error Lendtroller_BorrowCapReached();
    error Lendtroller_InsufficientShortfall();
    error Lendtroller_TooMuchRepay();
    error Lendtroller_LendtrollerMismatch();
    error Lendtroller_InvalidValue();
    error Lendtroller_AddressUnauthorized();
    error Lendtroller_MinimumHoldPeriod();

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
        return accountAssets[account];
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
            revert Lendtroller_HasActiveLoan();
        }

        // Fail if the sender is not permitted to redeem all of their tokens
        _redeemAllowed(mTokenAddress, msg.sender, tokensHeld);

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
        require(assetIndex < numUserAssets, "lendtroller: asset list misconfigured");

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
        if (mintPaused[mToken]) {
            revert Lendtroller_Paused();
        }

        if (!markets[mToken].isListed) {
            revert Lendtroller_MarketNotListed();
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
        _redeemAllowed(mToken, redeemer, redeemTokens);
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
        if (borrowPaused[mToken]) {
            revert Lendtroller_Paused();
        }

        if (!markets[mToken].isListed) {
            revert Lendtroller_MarketNotListed();
        }

        if (!markets[mToken].accountMembership[borrower]) {
            // only mTokens may call borrowAllowed if borrower not in market
            if (msg.sender != mToken) {
                revert Lendtroller_AddressUnauthorized();
            }

            _addToMarket(IMToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            require(markets[mToken].accountMembership[borrower], "lendtroller: invariant error");
        }

        (, uint256 errorCode) = getPriceRouter().getPrice(mToken, true, false);
        if (errorCode > 0) {
            revert Lendtroller_PriceError();
        }

        uint256 borrowCap = borrowCaps[mToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            // Validate that if there is a borrow cap, 
            // we will not be over the cap with this new borrow
            if ((IMToken(mToken).totalBorrows() + borrowAmount) > borrowCap) {
                revert Lendtroller_BorrowCapReached();
            }
        }

        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(
            borrower,
            IMToken(mToken),
            0,
            borrowAmount
        );

        if (shortfall > 0) {
            revert Lendtroller_InsufficientLiquidity();
        }
    }

    /// @notice Checks if the account should be allowed to repay a borrow
    ///         in the given market
    /// @param mToken The market to verify the repay against
    /// @param account The account who will have their loan repaid
    function repayAllowed(address mToken, address account) external view override {

        if (!markets[mToken].isListed) {
            revert Lendtroller_MarketNotListed();
        }

        /// We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        /// as well as short term price manipulations if the dynamic dual oracle 
        /// fails to protect the market somehow
        if (
            userData[account].lastBorrowTimestamp +
                minimumHoldPeriod >
            block.timestamp
        ) {
            revert Lendtroller_MinimumHoldPeriod();
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
            revert Lendtroller_MarketNotListed();
        }
        if (!markets[mTokenCollateral].isListed) {
            revert Lendtroller_MarketNotListed();
        }

        // The borrower must have shortfall in order to be liquidatable
        (, uint256 shortfall) = _getAccountLiquidity(borrower);
        // assembly {
        //     if iszero(shortfall) {
        //         // store the error selector to location 0x0
        //         mstore(0x0,_INSUFFICIENT_SHORTFALL_SELECTOR)
        //         // return bytes 29-32 for the selector
        //         revert(0x1c,0x04)
        //     }
        //  }

        // The liquidator may not close out more collateral than
        // what is allowed by the closeFactor
        uint256 borrowBalance = IMToken(mTokenBorrowed).borrowBalanceStored(
            borrower
        );
        uint256 maxClose = (closeFactorScaled * borrowBalance) / expScale;

        if (repayAmount > maxClose) {
            revert Lendtroller_TooMuchRepay();
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
        if (seizePaused > 1) {
            revert Lendtroller_Paused();
        }

        if (!markets[mTokenBorrowed].isListed) {
            revert Lendtroller_MarketNotListed();
        }
        if (!markets[mTokenCollateral].isListed) {
            revert Lendtroller_MarketNotListed();
        }

        if (
            IMToken(mTokenCollateral).lendtroller() !=
            IMToken(mTokenBorrowed).lendtroller()
        ) {
            revert Lendtroller_LendtrollerMismatch();
        }
    }

    /// @notice Checks if the account should be allowed to transfer tokens
    ///         in the given market
    /// @param mToken The market to verify the transfer against
    /// @param from The account which sources the tokens
    /// @param transferTokens The number of mTokens to transfer
    function transferAllowed(
        address mToken,
        address from,
        address,
        uint256 transferTokens
    ) external view override {
        if (transferPaused > 1) {
            revert Lendtroller_Paused();
        }

        _redeemAllowed(mToken, from, transferTokens);
    }

    /// @notice Calculate number of tokens of collateral asset to
    ///         seize given an underlying amount
    /// @dev Used in liquidation (called in mToken._liquidateUser)
    /// @param mTokenBorrowed The address of the borrowed mToken
    /// @param mTokenCollateral The address of the collateral mToken
    /// @param actualRepayAmount The amount of mTokenBorrowed underlying to
    ///                          convert into mTokenCollateral tokens
    /// @return uint256 The number of mTokenCollateral tokens to be seized in a liquidation
    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint256 actualRepayAmount
    ) external view override returns (uint256) {
        /// Read oracle prices for borrowed and collateral markets
        IPriceRouter router = getPriceRouter();
        (uint256 debtTokenPrice, uint256 highPriceError) = router.getPrice(
            mTokenBorrowed, 
            true, 
            false
        );
        (uint256 collateralTokenPrice, uint256 lowPriceError) = router.getPrice(
            mTokenCollateral,
            true,
            true
        );

        /// Validate that we were able to securely query prices from the dual oracle
        if (highPriceError == 2 || lowPriceError == 2) {
            revert Lendtroller_PriceError();
        }

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        //  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        //  seizeTokens = seizeAmount / exchangeRate
        //   = actualRepayAmount * (liquidationIncentive * priceBorrowedDebt) / (priceCollateral * exchangeRate)
        uint256 ratio = (liquidationIncentiveScaled * debtTokenPrice * expScale) / 
        (collateralTokenPrice * IMToken(mTokenCollateral).exchangeRateStored());

        return (ratio * actualRepayAmount) / expScale;
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
        // assembly {
        //     if iszero(numMarkets) {
        //         // store the error selector to location 0x0
        //         mstore(0x0,_INVALID_VALUE_SELECTOR)
        //         // return bytes 29-32 for the selector
        //         revert(0x1c,0x04)
        //     }
        //  }

        for (uint256 i; i < numMarkets; ++i) {
            /// Make sure the mToken is a collateral token
            if (mTokens[i].tokenType() > 0) {
                userData[msg.sender].collateralDisabled[mTokens[i]] = disableCollateral;
                emit SetUserDisableCollateral(
                    msg.sender,
                    mTokens[i],
                    disableCollateral
                );
            }
        }

        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(
            msg.sender,
            IMToken(address(0)),
            0,
            0
        );

        if (shortfall > 0) {
            revert Lendtroller_InsufficientLiquidity();
        }
    }

    /// Admin Functions

    /// @notice Sets the closeFactor used when liquidating borrows
    /// @dev Admin function to set closeFactor
    /// @param newCloseFactorScaled New close factor, scaled by 1e18
    function setCloseFactor(
        uint256 newCloseFactorScaled
    ) external onlyElevatedPermissions {
        uint256 oldCloseFactorScaled = closeFactorScaled;
        closeFactorScaled = newCloseFactorScaled;
        emit NewCloseFactor(oldCloseFactorScaled, newCloseFactorScaled);
    }

    /// @notice Sets the collateralFactor for a market
    /// @dev Admin function to set per-market collateralFactor
    /// @param mToken The market to set the factor on
    /// @param newCollateralFactorScaled The new collateral factor, scaled by 1e18
    function setCollateralFactor(
        IMToken mToken,
        uint256 newCollateralFactorScaled
    ) external onlyElevatedPermissions {
        // Verify market is listed
        ILendtroller.Market storage market = markets[address(mToken)];
        if (!market.isListed) {
            revert Lendtroller_MarketNotListed();
        }

        // Check collateral factor is not above maximum allowed
        if (collateralFactorMaxScaled < newCollateralFactorScaled) {
            revert Lendtroller_InvalidValue();
        }

        (, uint256 lowPriceError) = getPriceRouter().getPrice(
            address(mToken),
            true,
            true
        );

        // Validate that we got a price and that collateral factor != 0
        if (lowPriceError == 2 || newCollateralFactorScaled != 0) {
            revert Lendtroller_PriceError();
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
    function setLiquidationIncentive(
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
    function supportMarket(IMToken mToken) external onlyElevatedPermissions {
        if (markets[address(mToken)].isListed) {
            revert Lendtroller_MarketAlreadyListed();
        }

        mToken.tokenType(); // Sanity check to make sure its really a mToken

        ILendtroller.Market storage market = markets[address(mToken)];
        market.isListed = true;
        market.collateralFactorScaled = 0;

        _addMarket(address(mToken));

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
    function setMarketBorrowCaps(
        IMToken[] calldata mTokens,
        uint256[] calldata newBorrowCaps
    ) external {
        if (
            !centralRegistry.hasElevatedPermissions(msg.sender) &&
            msg.sender != borrowCapGuardian
        ) {
            revert Lendtroller_AddressUnauthorized();
        }
        uint256 numMarkets = mTokens.length;

        // assembly {
        //     if iszero(numMarkets) {
        //         // store the error selector to location 0x0
        //         mstore(0x0,_INVALID_VALUE_SELECTOR)
        //         // return bytes 29-32 for the selector
        //         revert(0x1c,0x04)
        //     }
        // }

        // if (numMarkets != newBorrowCaps.length) {
        //     assembly {
        //         // store the error selector to location 0x0
        //         mstore(0x0,_INVALID_VALUE_SELECTOR)
        //         // return bytes 29-32 for the selector
        //         revert(0x1c,0x04)
        //     }
        // }

        for (uint256 i; i < numMarkets; ++i) {
            borrowCaps[address(mTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(mTokens[i], newBorrowCaps[i]);
        }
    }

    /// @notice Admin function to change the Borrow Cap Guardian
    /// @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
    function setBorrowCapGuardian(
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

    /// @notice Fetches the current price router from the central registry
    /// @return Current PriceRouter interface address
    function getPriceRouter() public view returns (IPriceRouter) {
        return IPriceRouter(centralRegistry.priceRouter());
    }

    /// @notice Updates `accounts` lastBorrowTimestamp to the current block timestamp
    /// @dev The caller must be a listed MToken in the `markets` mapping
    /// @param account The address of the account that has just borrowed
    function notifyAccountBorrow(address account) external {
        require(markets[msg.sender].isListed, "Lendtroller: Caller not MToken");
        userData[account].lastBorrowTimestamp = block.timestamp;
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
            results[i] = _addToMarket(IMToken(mTokens[i]), msg.sender);
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
        ) = _getHypotheticalAccountLiquidity(
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
        ) = _getHypotheticalAccountPosition(
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
        ) = _getHypotheticalAccountLiquidity(
                account,
                IMToken(mTokenModify),
                redeemTokens,
                borrowAmount
            );

        return (liquidity, shortfall);
    }

    /// @notice Admin function to change the Pause Guardian
    /// @param newPauseGuardian The address of the new Pause Guardian
    function setPauseGuardian(
        address newPauseGuardian
    ) public onlyElevatedPermissions {
        // Cache the current value for event log
        address oldPauseGuardian = pauseGuardian;

        // Assign new guardian
        pauseGuardian = newPauseGuardian;

        emit NewPauseGuardian(oldPauseGuardian, newPauseGuardian);
    }

    /// @notice Admin function to set market mint paused
    /// @param mToken market token address
    /// @param state pause or unpause
    function setMintPaused(IMToken mToken, bool state) public returns (bool) {
        if (!markets[address(mToken)].isListed) {
            revert Lendtroller_MarketNotListed();
        }

        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert Lendtroller_AddressUnauthorized();
        }
        // Only the timelock or Emergency Council can turn minting back on
        if (!hasDaoPerms && state != true) {
            revert Lendtroller_AddressUnauthorized();
        }

        mintPaused[address(mToken)] = state;
        emit ActionPaused(mToken, "lendtroller: Mint Paused", state);
        return state;
    }

    /// @notice Admin function to set market borrow paused
    /// @param mToken market token address
    /// @param state pause or unpause
    function setBorrowPaused(
        IMToken mToken,
        bool state
    ) public returns (bool) {
        if (!markets[address(mToken)].isListed) {
            revert Lendtroller_MarketNotListed();
        }

        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert Lendtroller_AddressUnauthorized();
        }
        // Only the timelock or Emergency Council can turn borrows back on
        if (!hasDaoPerms && state != true) {
            revert Lendtroller_AddressUnauthorized();
        }

        borrowPaused[address(mToken)] = state;
        emit ActionPaused(mToken, "lendtroller: Borrow Paused", state);
        return state;
    }

    /// @notice Admin function to set transfer paused
    /// @param state pause or unpause
    function setTransferPaused(bool state) public returns (bool) {
        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert Lendtroller_AddressUnauthorized();
        }
        // Only the timelock or Emergency Council can turn transfers back on
        if (!hasDaoPerms && state != true) {
            revert Lendtroller_AddressUnauthorized();
        }
        transferPaused = state ? 2: 1;
        emit ActionPaused("lendtroller: Transfer Paused", state);
        return state;
    }

    /// @notice Admin function to set seize paused
    /// @param state pause or unpause
    function setSeizePaused(bool state) public returns (bool) {
        bool hasDaoPerms = centralRegistry.hasElevatedPermissions(msg.sender);

        if (msg.sender != pauseGuardian && !hasDaoPerms) {
            revert Lendtroller_AddressUnauthorized();
        }
        // Only the timelock or Emergency Council can turn seizing assets back on
        if (!hasDaoPerms && state != true) {
            revert Lendtroller_AddressUnauthorized();
        }

        seizePaused = state ? 2: 1;
        emit ActionPaused("lendtroller: Seize Paused", state);
        return state;
    }

    /// @notice Admin function to set position folding contract address
    /// @param newPositionFolding new position folding contract address
    function setPositionFolding(
        address newPositionFolding
    ) public onlyElevatedPermissions {
        // Cache the current value for event log
        address oldPositionFolding = positionFolding;

        // Assign new position folding contract
        positionFolding = newPositionFolding;

        emit NewPositionFoldingContract(oldPositionFolding, newPositionFolding);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Add the market to the borrower's "assets in"
    ///         for liquidity calculations
    /// @param mToken The market to enter
    /// @param borrower The address of the account to modify
    /// @return uint 0 = unable to enter market; 1 = market entered
    function _addToMarket(
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
    function _redeemAllowed(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) internal view {
        if (!markets[mToken].isListed) {
            revert Lendtroller_MarketNotListed();
        }

        // If the redeemer is not 'in' the market, then we can bypass
        // the liquidity check
        if (!markets[mToken].accountMembership[redeemer]) {
            return;
        }

        /// We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        /// as well as short term price manipulations if the dynamic dual oracle 
        /// fails to protect the market somehow
        if (
            userData[redeemer].lastBorrowTimestamp +
                minimumHoldPeriod >
            block.timestamp
        ) {
            revert Lendtroller_MinimumHoldPeriod();
        }

        // Otherwise, perform a hypothetical liquidity check to guard against
        // shortfall
        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(
            redeemer,
            IMToken(mToken),
            redeemTokens,
            0
        );

        if (shortfall > 0) {
            revert Lendtroller_InsufficientLiquidity();
        }
    }

    /// @notice Determine the current account liquidity wrt collateral requirements
    /// @return liquidity of account in excess of collateral requirements
    /// @return shortfall of account below collateral requirements
    function _getAccountLiquidity(
        address account
    ) internal view returns (uint256, uint256) {
        return
            _getHypotheticalAccountLiquidity(
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
    /// @return uint256 hypothetical account liquidity in excess
    ///              of collateral requirements,
    /// @return uint256 hypothetical account shortfall below collateral requirements)
    function _getHypotheticalAccountLiquidity(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) internal view returns (uint256, uint256) {
        (
            ,
            uint256 maxBorrow,
            uint256 sumBorrowPlusEffects
        ) = _getHypotheticalAccountPosition(
                account,
                mTokenModify,
                redeemTokens,
                borrowAmount
            );

        // These will not underflow/overflow as condition is checked prior
        if (maxBorrow > sumBorrowPlusEffects) {
            unchecked {
                return (maxBorrow - sumBorrowPlusEffects, 0);
            }
        }

        unchecked {
            return (0, sumBorrowPlusEffects - maxBorrow);
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
    function _getHypotheticalAccountPosition(
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
        bool isCToken;
        IPriceRouter router = getPriceRouter();
        accountSnapshot memory assetSnapshot;

        // For each asset the account is in
        for (uint256 i; i < numAccountAssets; ) {
            // Pull user token snapshot data for the asset and then increment i
            unchecked {
                assetSnapshot = accountAssets[account][i++].getAccountSnapshotPacked(account);
            }
            isCToken = assetSnapshot.asset.tokenType() > 0;

            // Collateralized assets (CTokens) use the lower price, Debt assets (DTokens) use the higher price
            (uint256 price, uint256 errorCode) = router.getPrice(address(assetSnapshot.asset), true, isCToken);
            if (errorCode > 1) {
                revert Lendtroller_PriceError();
            }

            if (isCToken) {
                // If they do not have this collateral asset disabled increment their collateral and max borrow value
                if (!userData[account].collateralDisabled[assetSnapshot.asset]) {
                    uint256 assetValue = (assetSnapshot.mTokenBalance * price * assetSnapshot.exchangeRateScaled) /
                    expScale;

                    sumCollateral += assetValue;
                    maxBorrow +=
                        (assetValue *
                            markets[address(assetSnapshot.asset)].collateralFactorScaled) /
                        expScale;
                }

            } else {
                // If they have a borrow balance we need to document it
                if (assetSnapshot.borrowBalance > 0) {
                    sumBorrowPlusEffects += ((price * assetSnapshot.borrowBalance) /
                    expScale);
                }
            }

            // Calculate effects of interacting with mTokenModify
            if (assetSnapshot.asset == mTokenModify) {
                // If its a CToken our only option is to redeem it since it cant be borrowed
                // If its a DToken we can redeem it but it will not have any effect on borrow amount 
                // since DToken have a collateral value of 0
                if (isCToken) {
                    if (!userData[account].collateralDisabled[assetSnapshot.asset]) {
                        // Pre-compute a conversion factor
                        // from tokens -> $ (normalized price value)
                        uint256 tokensToDenom = (((markets[address(assetSnapshot.asset)]
                            .collateralFactorScaled * assetSnapshot.exchangeRateScaled) /
                            expScale) * price) / expScale;

                        // redeem effect
                        sumBorrowPlusEffects += ((tokensToDenom *
                            redeemTokens) / expScale);
                    }
                    
                } else {
                    // borrow effect
                    sumBorrowPlusEffects += ((price * borrowAmount) /
                        expScale);
                }
 
            }
        }
    }

    /// @notice Add the market to the markets mapping and set it as listed
    /// @param mToken The address of the market (token) to list
    function _addMarket(address mToken) internal {
        uint256 numMarkets = allMarkets.length;

        for (uint256 i; i < numMarkets; ++i) {
            if (allMarkets[i] == IMToken(mToken)) {
                revert Lendtroller_MarketAlreadyListed();
            }
        }
        allMarkets.push(IMToken(mToken));
    }

    
}
