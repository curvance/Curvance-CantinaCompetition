// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Token/CToken.sol";
import "./PriceOracle.sol";
import "./ComptrollerInterface.sol";
import "./interfaces/IRewards.sol";
//import { ComptrollerStorage } from "./Storage.sol";
import "./Unitroller.sol";
//import "./Governance/Comp.sol";

/**
 * @title Curvance Comptroller
 * @author Curvance - Based on Compound Finance
 * @notice Manages risk within the lending & collateral markets
 */
contract Comptroller is ComptrollerInterface { //ComptrollerStorage, 

    ////////// Errors //////////

    error MarketNotListed(address);
    error AddressAlreadyJoined();
    error NonZeroBorrowBalance(); /// Take a look here, could soften the landing
    error Paused();
    error InsufficientLiquidity();
    error PriceError();
    error BorrowCapReached();
    error InsufficientShortfall();
    error TooMuchRepay();
    error ComptrollerMismatch();
    error MarketAlreadyListed();
    error InvalidValue();
    error AddressUnauthorized();


    ////////// Events //////////

    /// @notice Emitted when an admin supports a market
    event MarketListed(CToken cToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(CToken cToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(CToken cToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorScaled, uint newCloseFactorScaled);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(CToken cToken, uint oldCollateralFactorScaled, uint newCollateralFactorScaled);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveScaled, uint newLiquidationIncentiveScaled);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(CToken cToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a cToken is changed
    event NewBorrowCap(CToken indexed cToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when rewards contract address is changed
    event NewRewardContract(IReward oldRewarder, IReward newRewarder);


    ////////// Constants //////////

    // closeFactorScaled must be strictly greater than this value
    uint internal constant closeFactorMinScaled = 0.05e18; // 0.05

    // closeFactorScaled must not exceed this value
    uint internal constant closeFactorMaxScaled = 0.9e18; // 0.9

    // No collateralFactorScaled may exceed this value
    uint internal constant collateralFactorMaxScaled = 0.9e18; // 0.9

    // Scaler for floating point math
    uint constant expScale = 1e18;

    constructor(IReward _rewarder) {
        admin = msg.sender;
        rewarder = _rewarder;
    }
    
    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (CToken[] memory) {
        CToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param cToken The cToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, CToken cToken) external view returns (bool) {
        return markets[address(cToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param cTokens The list of addresses of the cToken markets to be enabled
     * @return uint array: 0 = market not entered; 1 = market entered 
     */
    function enterMarkets(address[] memory cTokens) override public returns (uint[] memory) {
        uint len = cTokens.length;

        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            CToken cToken = CToken(cTokens[i]);
            results[i] = addToMarketInternal(cToken, msg.sender);
        }

        // Return a list of markets joined & not joined (1 = joined, 0 = not joined)
        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param cToken The market to enter
     * @param borrower The address of the account to modify
     * @return uint 0 = unable to enter market; 1 = market entered
     */
    function addToMarketInternal(CToken cToken, address borrower) internal returns (uint) {
        Market storage marketToJoin = markets[address(cToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return 0;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return 0;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(cToken);

        emit MarketEntered(cToken, borrower);
        
        // Indicates that a market was successfully entered
        return 1;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param cTokenAddress The address of the asset to be removed
     */
    function exitMarket(address cTokenAddress) override external {

        CToken cToken = CToken(cTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the cToken */
        (uint tokensHeld, uint amountOwed, ) = cToken.getAccountSnapshot(msg.sender); /// removed first value: uint oErr, 

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            /// TODO Should the whole transaction revert? Could just calculate max safe withdrawal?
            // like:
            // userMaxSafeWithdrawal = maxborrow * 0.8 - outstandingDebt
            revert NonZeroBorrowBalance(); 
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        redeemAllowedInternal(cTokenAddress, msg.sender, tokensHeld);

        Market storage marketToExit = markets[address(cToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return;
        }

        /* Set cToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete cToken from the account’s list of assets */
        // load into memory for faster iteration
        CToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == cToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        CToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(cToken, msg.sender);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     */
    function mintAllowed(address cToken, address minter) override external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (mintGuardianPaused[cToken]) {
            revert Paused();
        }

        if (!markets[cToken].isListed) {
            revert MarketNotListed(cToken);
        }

        // Keep the flywheel moving
        rewarder.updateCveSupplyIndexExternal(cToken);
        rewarder.distributeSupplierCveExternal(cToken, minter);
    }

    // /**
    //  * @notice Validates mint and reverts on rejection. May emit logs.
    //  * @param cToken Asset being minted
    //  * @param minter The address minting the tokens
    //  * @param actualMintAmount The amount of the underlying asset being minted
    //  * @param mintTokens The number of tokens being minted
    //  */
    // function mintVerify(address cToken, address minter, uint actualMintAmount, uint mintTokens) override external {
    //     // Shh - currently unused
    //     cToken;
    //     minter;
    //     actualMintAmount;
    //     mintTokens;

    //     // Shh - we don't ever want this hook to be marked pure
    //     if (false) {
    //         maxAssets = maxAssets;
    //     }
    // }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of cTokens to exchange for the underlying asset in the market
     */
    function redeemAllowed(address cToken, address redeemer, uint redeemTokens) override external {

        redeemAllowedInternal(cToken, redeemer, redeemTokens);

        // Keep the flywheel moving        
        /// TODO Should this be removed or should it call these functions on the CompRewards.sol?
        rewarder.updateCveSupplyIndexExternal(cToken);
        rewarder.distributeSupplierCveExternal(cToken, redeemer);
    }

    function redeemAllowedInternal(address cToken, address redeemer, uint redeemTokens) internal view {
        if (!markets[cToken].isListed) {
            revert MarketNotListed(cToken);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[cToken].accountMembership[redeemer]) {
            return;
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, CToken(cToken), redeemTokens, 0);

        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    // /** @dev Is called by CToken.sol when redeeming as a final check hook
    //  *      - migrated the logic to the CToken function to save gas
    //  * @notice Validates redeem and reverts on rejection. May emit logs.
    //  * param cToken Asset being redeemed
    //  * param redeemer The address redeeming the tokens
    //  * @param redeemAmount The amount of the underlying asset being redeemed
    //  * @param redeemTokens The number of tokens being redeemed
    //  */
    // function redeemVerify(uint redeemAmount, uint redeemTokens) override pure external {
    //     // Require tokens is zero or amount is also zero
    //     if (redeemTokens == 0 && redeemAmount > 0) {
    //         revert CannotEqualZero();
    //     }
    // }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param cToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     */
    function borrowAllowed(address cToken, address borrower, uint borrowAmount) override external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (borrowGuardianPaused[cToken]) {
            revert Paused(); 
        }

        if (!markets[cToken].isListed) {
            revert MarketNotListed(cToken);
        }

        if (!markets[cToken].accountMembership[borrower]) {
            // only cTokens may call borrowAllowed if borrower not in market
            if (msg.sender != cToken) { 
                revert AddressUnauthorized(); 
            }

            addToMarketInternal(CToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert(markets[cToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPrice(CToken(cToken)) == 0) {
            revert PriceError();
        }

        uint borrowCap = borrowCaps[cToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = CToken(cToken).totalBorrows();
            uint nextTotalBorrows = totalBorrows + borrowAmount;

            if (nextTotalBorrows >= borrowCap) {
                revert BorrowCapReached();
            }
        }

        getHypotheticalAccountLiquidityInternal(borrower, CToken(cToken), 0, borrowAmount);

        // Keep the flywheel moving
        // uint borrowIndex = CToken(cToken).borrowIndex(); - Unused input param, removed from the functions below
        rewarder.updateCveSupplyIndexExternal(cToken); //, borrowIndex);
        rewarder.distributeSupplierCveExternal(cToken, borrower); //, borrowIndex);
    }

    // /**
    //  * @notice Validates borrow and reverts on rejection. May emit logs.
    //  * @param cToken Asset whose underlying is being borrowed
    //  * @param borrower The address borrowing the underlying
    //  * @param borrowAmount The amount of the underlying asset requested to borrow
    //  */
    // function borrowVerify(address cToken, address borrower, uint borrowAmount) override external {
    //     // Shh - currently unused
    //     cToken;
    //     borrower;
    //     borrowAmount;

    //     // Shh - we don't ever want this hook to be marked pure
    //     if (false) {
    //         maxAssets = maxAssets;
    //     }
    // }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param cToken The market to verify the repay against
     * @param borrower The account which would borrowed the asset
     */
    function repayBorrowAllowed(
        address cToken,
        address borrower
    ) override external {

        if (!markets[cToken].isListed) {
            revert MarketNotListed(cToken);
        }

        // Keep the flywheel moving
        // uint borrowIndex = CToken(cToken).borrowIndex();- removed from the functions below
        rewarder.updateCveSupplyIndexExternal(cToken); // , borrowIndex);
        rewarder.distributeSupplierCveExternal(cToken, borrower); //, borrowIndex);
    }

    // /**
    //  * @notice Validates repayBorrow and reverts on rejection. May emit logs.
    //  * @param cToken Asset being repaid
    //  * @param payer The address repaying the borrow
    //  * @param borrower The address of the borrower
    //  * @param actualRepayAmount The amount of underlying being repaid
    //  */
    // function repayBorrowVerify(
    //     address cToken,
    //     address payer,
    //     address borrower,
    //     uint actualRepayAmount,
    //     uint borrowerIndex) override external {
    //     // Shh - currently unused
    //     cToken;
    //     payer;
    //     borrower;
    //     actualRepayAmount;
    //     borrowerIndex;

    //     // Shh - we don't ever want this hook to be marked pure
    //     if (false) {
    //         maxAssets = maxAssets;
    //     }
    // }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint repayAmount) override view external {

        if (!markets[cTokenBorrowed].isListed) { 
            revert MarketNotListed(cTokenBorrowed);
        }
        if (!markets[cTokenCollateral].isListed) {
            revert MarketNotListed(cTokenCollateral);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (, uint shortfall) = getAccountLiquidityInternal(borrower);
        if (shortfall == 0) {
            revert InsufficientShortfall();
        }
        
        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);
        uint maxClose = (closeFactorScaled * borrowBalance) / expScale;

        if (repayAmount > maxClose) {
            /// TODO Should this just reduce the repayAmount to the maxClose amount instead? Like this:
            // repayAmount = maxClose;
            revert TooMuchRepay();
        }
    }

    // /**
    //  * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
    //  * @param cTokenBorrowed Asset which was borrowed by the borrower
    //  * @param cTokenCollateral Asset which was used as collateral and will be seized
    //  * @param liquidator The address repaying the borrow and seizing the collateral
    //  * @param borrower The address of the borrower
    //  * @param actualRepayAmount The amount of underlying being repaid
    //  */
    // function liquidateBorrowVerify(
    //     address cTokenBorrowed,
    //     address cTokenCollateral,
    //     address liquidator,
    //     address borrower,
    //     uint actualRepayAmount,
    //     uint seizeTokens) override external {
    //     // Shh - currently unused
    //     cTokenBorrowed;
    //     cTokenCollateral;
    //     liquidator;
    //     borrower;
    //     actualRepayAmount;
    //     seizeTokens;

    //     // Shh - we don't ever want this hook to be marked pure
    //     if (false) {
    //         maxAssets = maxAssets;
    //     }
    // }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower//,
        // uint seizeTokens
    ) override external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (seizeGuardianPaused) { 
            revert Paused();
        }

        // Shh - currently unused
        // seizeTokens;

        if (!markets[cTokenBorrowed].isListed) { 
            revert MarketNotListed(cTokenBorrowed);
        }
        if (!markets[cTokenCollateral].isListed) {
            revert MarketNotListed(cTokenCollateral);
        }

        if (CToken(cTokenCollateral).comptroller() != CToken(cTokenBorrowed).comptroller()) {
            revert ComptrollerMismatch();
        }

        // Keep the flywheel moving        
        /// TODO Should this be removed or should it call these functions on the CompRewards.sol?
        rewarder.updateCveSupplyIndexExternal(cTokenCollateral);
        rewarder.distributeSupplierCveExternal(cTokenCollateral, borrower);
        rewarder.distributeSupplierCveExternal(cTokenCollateral, liquidator);
    }

    // /**
    //  * @notice Validates seize and reverts on rejection. May emit logs.
    //  * @param cTokenCollateral Asset which was used as collateral and will be seized
    //  * @param cTokenBorrowed Asset which was borrowed by the borrower
    //  * @param liquidator The address repaying the borrow and seizing the collateral
    //  * @param borrower The address of the borrower
    //  * @param seizeTokens The number of collateral tokens to seize
    //  */
    // function seizeVerify(
    //     address cTokenCollateral,
    //     address cTokenBorrowed,
    //     address liquidator,
    //     address borrower,
    //     uint seizeTokens
    // ) override external {
    //     // Shh - currently unused
    //     cTokenCollateral;
    //     cTokenBorrowed;
    //     liquidator;
    //     borrower;
    //     seizeTokens;

    //     // Shh - we don't ever want this hook to be marked pure
    //     if (false) {
    //         maxAssets = maxAssets;
    //     }
    // }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param cToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     */
    function transferAllowed(
        address cToken, 
        address src, 
        address dst, 
        uint transferTokens
    ) override external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (transferGuardianPaused) {
            revert Paused();
        }

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        redeemAllowedInternal(cToken, src, transferTokens);

        // Keep the flywheel moving
        /// TODO Should this be removed or should it call these functions on the CompRewards.sol?
        rewarder.updateCveSupplyIndexExternal(cToken);
        rewarder.distributeSupplierCveExternal(cToken, src);
        rewarder.distributeSupplierCveExternal(cToken, dst);
    }

    // /**
    //  * @notice Validates transfer and reverts on rejection. May emit logs.
    //  * @param cToken Asset being transferred
    //  * @param src The account which sources the tokens
    //  * @param dst The account which receives the tokens
    //  * @param transferTokens The number of cTokens to transfer
    //  */
    // function transferVerify(address cToken, address src, address dst, uint transferTokens) override external {
    //     // Shh - currently unused
    //     cToken;
    //     src;
    //     dst;
    //     transferTokens;

    //     // Shh - we don't ever want this hook to be marked pure
    //     if (false) {
    //         maxAssets = maxAssets;
    //     }
    // }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `cTokenBalance` is the number of cTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    // struct AccountLiquidityLocalVars {
    //     uint sumCollateral;
    //     uint sumBorrowPlusEffects;
    //     uint cTokenBalance;
    //     uint borrowBalance;
    //     uint exchangeRateMantissa;
    //     uint oraclePriceMantissa;
    //     // Exp collateralFactor;
    //     // Exp exchangeRate;
    //     // Exp oraclePrice;
    //     // Exp tokensToDenom;
    //     uint collateralFactor;
    //     uint exchangeRate;
    //     uint oraclePrice;
    //     uint tokensToDenom;
    // }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return liquidity of account in excess of collateral requirements
     * @return shortfall of account below collateral requirements
     */
    function getAccountLiquidity(address account) public view returns (uint, uint) {
        (uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account, CToken(address(0)), 0, 0
        );

        return (liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return liquidity of account in excess of collateral requirements
     * @return shortfall of account below collateral requirements
     */
    function getAccountLiquidityInternal(address account) internal view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, CToken(address(0)), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return uint hypothetical account liquidity in excess of collateral requirements,
     * @return uint hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint redeemTokens,
        uint borrowAmount) public view returns (uint, uint) {

        (uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account, CToken(cTokenModify), redeemTokens, borrowAmount
        );
        
        return (liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral cToken using stored data,
     *  without calculating accumulated interest.
     * @return uint hypothetical account liquidity in excess of collateral requirements,
     * @return uint hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        CToken cTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (uint, uint) {

        // AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint sumCollateral;
        uint sumBorrowPlusEffects;

        // For each asset the account is in
        CToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            CToken asset = assets[i];

            // uint oraclePrice = oracle.getUnderlyingPrice(asset);
            // Read the balances and exchange rate from the cToken
            // (
            //     vars.cTokenBalance, 
            //     vars.borrowBalance, 
            //     vars.exchangeRateMantissa
            // ) = asset.getAccountSnapshot(account);

            (
                //, 
                uint cTokenBalance, 
                uint borrowBalance, 
                uint exchangeRateScaled
            ) = asset.getAccountSnapshot(account);

            /// TODO Check!
            // vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
            // uint collateralFactor = markets[address(asset)].collateralFactorScaled; TODO had to remove due to stack full!

            // vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            // vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            // uint oraclePriceMantissa = oracle.getUnderlyingPrice(asset); // not needed if checking the oracle price below
            // if (vars.oraclePriceMantissa == 0) {
            // if (oraclePriceMantissa == 0) { // not needed if checking the oracle price below
            //     revert PriceError(); // not needed if checking the oracle price below
            // } // not needed if checking the oracle price below

            // vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});
            // uint oraclePrice = oraclePriceMantissa * PRECISION; // not needed if calling here
            uint oraclePrice = (oracle.getUnderlyingPrice(asset) * expScale);
            if (oraclePrice == 0) revert PriceError();

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            // vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);
            uint tokensToDenom = (markets[address(asset)].collateralFactorScaled * exchangeRateScaled) * oraclePrice;

            // vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.cTokenBalance, vars.sumCollateral);
            /// TODO Should this really be added to here within the for loop? Or is it a once-off per loop?
            sumCollateral += ((tokensToDenom * cTokenBalance) / expScale);

            // vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);
            /// TODO Should this really be added to here within the for loop? Or is it a once-off per loop?
            sumBorrowPlusEffects += ((oraclePrice * borrowBalance) / expScale);

            // Calculate effects of interacting with cTokenModify
            if (asset == cTokenModify) {
                // redeem effect
                // vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);
                sumBorrowPlusEffects += ((tokensToDenom * redeemTokens) / expScale);

                // borrow effect
                // vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
                sumBorrowPlusEffects += ((oraclePrice * borrowAmount) / expScale);
            }
        }

        // These are safe, as the underflow condition is checked first
        // if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
        //     return (vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        if (sumCollateral > sumBorrowPlusEffects) {
            return (sumCollateral - sumBorrowPlusEffects, 0);
        } else {
            // return (0, vars.sumBorrowPlusEffects - vars.sumCollateral);
            return (0, sumBorrowPlusEffects - sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in cToken.liquidateBorrowFresh)
     * @param cTokenBorrowed The address of the borrowed cToken
     * @param cTokenCollateral The address of the collateral cToken
     * @param actualRepayAmount The amount of cTokenBorrowed underlying to convert into cTokenCollateral tokens
     * @return uint The number of cTokenCollateral tokens to be seized in a liquidation
     */
    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed, 
        address cTokenCollateral, 
        uint actualRepayAmount
    ) override external view returns (uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedScaled = oracle.getUnderlyingPrice(CToken(cTokenBorrowed));
        uint priceCollateralScaled = oracle.getUnderlyingPrice(CToken(cTokenCollateral));

        if (priceBorrowedScaled == 0 || priceCollateralScaled == 0) {
            revert PriceError();
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateScaled = CToken(cTokenCollateral).exchangeRateStored();
        uint numerator = liquidationIncentiveScaled * priceBorrowedScaled; 
        uint denominator = priceCollateralScaled * exchangeRateScaled;
        uint ratio = numerator * expScale / denominator;
        uint seizeTokens = (ratio * actualRepayAmount) / expScale;

        return seizeTokens;
    }

    /*** Admin Functions ***/

    function _setRewardsContract(IReward newRewarder) public {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        IReward oldRewarder = rewarder;

        rewarder = newRewarder;

        emit NewRewardContract(oldRewarder, newRewarder);
    }

    /**
      * @notice Sets a new price oracle for the comptroller
      * @dev Admin function to set a new price oracle
      */
    function _setPriceOracle(PriceOracle newOracle) public {
        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);
    }

    /**
      * @notice Sets the closeFactor used when liquidating borrows
      * @dev Admin function to set closeFactor
      * @param newCloseFactorScaled New close factor, scaled by 1e18
      */
    function _setCloseFactor(uint newCloseFactorScaled) external {
        // Check caller is admin}
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        uint oldCloseFactorScaled = closeFactorScaled;
        closeFactorScaled = newCloseFactorScaled;
        emit NewCloseFactor(oldCloseFactorScaled, closeFactorScaled);
    }

    /**
      * @notice Sets the collateralFactor for a market
      * @dev Admin function to set per-market collateralFactor
      * @param cToken The market to set the factor on
      * @param newCollateralFactorScaled The new collateral factor, scaled by 1e18
      */
    function _setCollateralFactor(CToken cToken, uint newCollateralFactorScaled) external {
        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Verify market is listed
        Market storage market = markets[address(cToken)];
        if (!market.isListed) {
            revert MarketNotListed(address(cToken));
        }

        // Check collateral factor <= 0.9
        if (collateralFactorMaxScaled < newCollateralFactorScaled) {
            revert InvalidValue();
        }

        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorScaled != 0 && oracle.getUnderlyingPrice(cToken) == 0) {
            revert PriceError();
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorScaled = market.collateralFactorScaled;
        market.collateralFactorScaled = newCollateralFactorScaled;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(cToken, oldCollateralFactorScaled, newCollateralFactorScaled);
    }

    /**
      * @notice Sets liquidationIncentive
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveScaled New liquidationIncentive scaled by 1e18
      */
    function _setLiquidationIncentive(uint newLiquidationIncentiveScaled) external {
        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveScaled = liquidationIncentiveScaled;

        // Set liquidation incentive to new incentive
        liquidationIncentiveScaled = newLiquidationIncentiveScaled;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveScaled, newLiquidationIncentiveScaled);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param cToken The address of the market (token) to list
      */
    function _supportMarket(CToken cToken) external {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        if (markets[address(cToken)].isListed) {
            revert MarketAlreadyListed();
        }

        cToken.isCToken(); // Sanity check to make sure its really a CToken

        // Note that isComped is not in active use anymore
        Market storage market = markets[address(cToken)];
        market.isListed = true;
        market.isComped = false;
        market.collateralFactorScaled = 0;

        _addMarketInternal(address(cToken));

        emit MarketListed(cToken);
    }

    function _addMarketInternal(address cToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            if (allMarkets[i] == CToken(cToken)) {
                revert MarketAlreadyListed();
            }
        }
        allMarkets.push(CToken(cToken));
    }


    /**
      * @notice Set the given borrow caps for the given cToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
      * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
      * @param cTokens The addresses of the markets (tokens) to change the borrow caps for
      * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
      */
    function _setMarketBorrowCaps(CToken[] calldata cTokens, uint[] calldata newBorrowCaps) external {
        if (msg.sender != admin && msg.sender != borrowCapGuardian) {
            revert AddressUnauthorized();
        }
        uint numMarkets = cTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        if (numMarkets == 0 || numMarkets != numBorrowCaps) {
            revert InvalidValue();
        }

        for(uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(cTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(cTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     */
    function _setPauseGuardian(address newPauseGuardian) public {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }

    function _setMintPaused(CToken cToken, bool state) public returns (bool) {
        if (!markets[address(cToken)].isListed) {
            revert MarketNotListed(address(cToken));
        }
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert AddressUnauthorized();
        }
        if (msg.sender != admin && state != true) {
            revert AddressUnauthorized();
        }

        mintGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(CToken cToken, bool state) public returns (bool) {
        if (!markets[address(cToken)].isListed) {
            revert MarketNotListed(address(cToken));
        }
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert AddressUnauthorized();
        }
        if (msg.sender != admin && state != true) {
            revert AddressUnauthorized();
        }

        borrowGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert AddressUnauthorized();
        }
        if (msg.sender != admin && state != true) {
            revert AddressUnauthorized();
        }


        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert AddressUnauthorized();
        }
        if (msg.sender != admin && state != true) {
            revert AddressUnauthorized();
        }


        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        if (msg.sender != unitroller.admin()) {
            revert AddressUnauthorized();
        }
        unitroller._acceptImplementation();
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }
    
    function min(uint a, uint b) internal pure returns (uint) {
        if (a <= b) {
            return a;
        } else {
            return b;
        }
    }


    /** GETTER FUNCTIONS */
    function getIsMarkets(address cToken) external view override returns (bool, uint, bool) {
        // bool listed = markets[cToken].isListed;
        // bool comped = markets[cToken].isComped;
        // return (listed, comped);
        return (
            markets[cToken].isListed,
            markets[cToken].collateralFactorScaled,
            markets[cToken].isComped
        );
    }

    function getAccountMembership(address cToken, address user) external view override returns (bool) {
        return markets[cToken].accountMembership[user];
    }

    function getAllMarkets() external view override returns (CToken[] memory) {
        return allMarkets;
    }

    function getAccountAssets(address user) external view override returns (CToken[] memory) {
        return accountAssets[user];
    }


}