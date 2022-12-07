// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../Token/CToken.sol";
import "../PriceOracle.sol";
import "../CompRewards/RewardsInterface.sol";
import "../Unitroller/Unitroller.sol";
import "./ComptrollerInterface.sol";

/**
 * @title Curvance Comptroller
 * @author Curvance - Based on Compound Finance
 * @notice Manages risk within the lending & collateral markets
 */
contract Comptroller is ComptrollerInterface {
    ////////// Constants //////////

    /// @notice closeFactorScaled must be strictly greater than this value
    uint256 internal constant closeFactorMinScaled = 0.05e18; // 0.05

    /// @notice closeFactorScaled must not exceed this value
    uint256 internal constant closeFactorMaxScaled = 0.9e18; // 0.9

    /// @notice No collateralFactorScaled may exceed this value
    uint256 internal constant collateralFactorMaxScaled = 0.9e18; // 0.9

    /// @notice Scaler for floating point math
    uint256 internal constant expScale = 1e18;

    constructor(RewardsInterface _rewarder) {
        admin = msg.sender;
        rewarder = _rewarder;
    }

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
    function enterMarkets(address[] memory cTokens) public override returns (uint256[] memory) {
        uint256 len = cTokens.length;

        uint256[] memory results = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
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
    function addToMarketInternal(CToken cToken, address borrower) internal returns (uint256) {
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
    function exitMarket(address cTokenAddress) external override {
        CToken cToken = CToken(cTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the cToken */
        (uint256 tokensHeld, uint256 amountOwed, ) = cToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
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
        uint256 len = userAssetList.length;
        uint256 assetIndex = len;
        for (uint256 i = 0; i < len; i++) {
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
    function mintAllowed(address cToken, address minter) external override {
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

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of cTokens to exchange for the underlying asset in the market
     */
    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external override {
        redeemAllowedInternal(cToken, redeemer, redeemTokens);

        // Keep the flywheel moving
        rewarder.updateCveSupplyIndexExternal(cToken);
        rewarder.distributeSupplierCveExternal(cToken, redeemer);
    }

    function redeemAllowedInternal(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) internal view {
        if (!markets[cToken].isListed) {
            revert MarketNotListed(cToken);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[cToken].accountMembership[redeemer]) {
            return;
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, CToken(cToken), redeemTokens, 0);

        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param cToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     */
    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external override {
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

        uint256 borrowCap = borrowCaps[cToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint256 totalBorrows = CToken(cToken).totalBorrows();
            uint256 nextTotalBorrows = totalBorrows + borrowAmount;

            if (nextTotalBorrows >= borrowCap) {
                revert BorrowCapReached();
            }
        }

        getHypotheticalAccountLiquidityInternal(borrower, CToken(cToken), 0, borrowAmount);

        // Keep the flywheel moving
        rewarder.updateCveSupplyIndexExternal(cToken);
        rewarder.distributeSupplierCveExternal(cToken, borrower);
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param cToken The market to verify the repay against
     * @param borrower The account which would borrowed the asset
     */
    function repayBorrowAllowed(address cToken, address borrower) external override {
        if (!markets[cToken].isListed) {
            revert MarketNotListed(cToken);
        }

        // Keep the flywheel moving
        rewarder.updateCveSupplyIndexExternal(cToken);
        rewarder.distributeSupplierCveExternal(cToken, borrower);
    }

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
        uint256 repayAmount
    ) external view override {
        if (!markets[cTokenBorrowed].isListed) {
            revert MarketNotListed(cTokenBorrowed);
        }
        if (!markets[cTokenCollateral].isListed) {
            revert MarketNotListed(cTokenCollateral);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (, uint256 shortfall) = getAccountLiquidityInternal(borrower);
        if (shortfall == 0) {
            revert InsufficientShortfall();
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint256 borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);
        uint256 maxClose = (closeFactorScaled * borrowBalance) / expScale;

        if (repayAmount > maxClose) {
            revert TooMuchRepay();
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower
    ) external override {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (seizeGuardianPaused) {
            revert Paused();
        }

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
        rewarder.updateCveSupplyIndexExternal(cTokenCollateral);
        rewarder.distributeSupplierCveExternal(cTokenCollateral, borrower);
        rewarder.distributeSupplierCveExternal(cTokenCollateral, liquidator);
    }

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
        uint256 transferTokens
    ) external override {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (transferGuardianPaused) {
            revert Paused();
        }

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        redeemAllowedInternal(cToken, src, transferTokens);

        // Keep the flywheel moving
        rewarder.updateCveSupplyIndexExternal(cToken);
        rewarder.distributeSupplierCveExternal(cToken, src);
        rewarder.distributeSupplierCveExternal(cToken, dst);
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return liquidity of account in excess of collateral requirements
     * @return shortfall of account below collateral requirements
     */
    function getAccountLiquidity(address account) public view returns (uint256, uint256) {
        (uint256 liquidity, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            CToken(address(0)),
            0,
            0
        );

        return (liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return liquidity of account in excess of collateral requirements
     * @return shortfall of account below collateral requirements
     */
    function getAccountLiquidityInternal(address account) internal view returns (uint256, uint256) {
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
        uint256 redeemTokens,
        uint256 borrowAmount
    ) public view returns (uint256, uint256) {
        (uint256 liquidity, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            CToken(cTokenModify),
            redeemTokens,
            borrowAmount
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
        uint256 redeemTokens,
        uint256 borrowAmount
    ) internal view returns (uint256, uint256) {
        uint256 sumCollateral;
        uint256 sumBorrowPlusEffects;

        // For each asset the account is in
        CToken[] memory assets = accountAssets[account];
        for (uint256 i = 0; i < assets.length; i++) {
            CToken asset = assets[i];

            (uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRateScaled) = asset.getAccountSnapshot(
                account
            );
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            if (oraclePrice == 0) revert PriceError();

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            uint256 tokensToDenom = (((markets[address(asset)].collateralFactorScaled * exchangeRateScaled) /
                expScale) * oraclePrice) / expScale;

            sumCollateral += ((tokensToDenom * cTokenBalance) / expScale);

            sumBorrowPlusEffects += ((oraclePrice * borrowBalance) / expScale);

            // Calculate effects of interacting with cTokenModify
            if (asset == cTokenModify) {
                // redeem effect
                sumBorrowPlusEffects += ((tokensToDenom * redeemTokens) / expScale);

                // borrow effect
                sumBorrowPlusEffects += ((oraclePrice * borrowAmount) / expScale);
            }
        }

        // These are safe, as the underflow condition is checked first
        if (sumCollateral > sumBorrowPlusEffects) {
            return (sumCollateral - sumBorrowPlusEffects, 0);
        } else {
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
        uint256 actualRepayAmount
    ) external view override returns (uint256) {
        /* Read oracle prices for borrowed and collateral markets */
        uint256 priceBorrowedScaled = oracle.getUnderlyingPrice(CToken(cTokenBorrowed));
        uint256 priceCollateralScaled = oracle.getUnderlyingPrice(CToken(cTokenCollateral));

        if (priceBorrowedScaled == 0 || priceCollateralScaled == 0) {
            revert PriceError();
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint256 exchangeRateScaled = CToken(cTokenCollateral).exchangeRateStored();
        uint256 numerator = liquidationIncentiveScaled * priceBorrowedScaled;
        uint256 denominator = priceCollateralScaled * exchangeRateScaled;
        uint256 ratio = (numerator * expScale) / denominator;
        uint256 seizeTokens = (ratio * actualRepayAmount) / expScale;

        return seizeTokens;
    }

    /*** Admin Functions ***/

    /**
     * @notice Sets a new rewarder contract address
     */
    function _setRewardsContract(RewardsInterface newRewarder) public {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        RewardsInterface oldRewarder = rewarder;

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

        emit NewPriceOracle(oldOracle, newOracle);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorScaled New close factor, scaled by 1e18
     */
    function _setCloseFactor(uint256 newCloseFactorScaled) external {
        // Check caller is admin}
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        uint256 oldCloseFactorScaled = closeFactorScaled;
        closeFactorScaled = newCloseFactorScaled;
        emit NewCloseFactor(oldCloseFactorScaled, closeFactorScaled);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param cToken The market to set the factor on
     * @param newCollateralFactorScaled The new collateral factor, scaled by 1e18
     */
    function _setCollateralFactor(CToken cToken, uint256 newCollateralFactorScaled) external {
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
        uint256 oldCollateralFactorScaled = market.collateralFactorScaled;
        market.collateralFactorScaled = newCollateralFactorScaled;

        emit NewCollateralFactor(cToken, oldCollateralFactorScaled, newCollateralFactorScaled);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveScaled New liquidationIncentive scaled by 1e18
     */
    function _setLiquidationIncentive(uint256 newLiquidationIncentiveScaled) external {
        // Check caller is admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Save current value for use in log
        uint256 oldLiquidationIncentiveScaled = liquidationIncentiveScaled;

        // Set liquidation incentive to new incentive
        liquidationIncentiveScaled = newLiquidationIncentiveScaled;

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
        for (uint256 i = 0; i < allMarkets.length; i++) {
            if (allMarkets[i] == CToken(cToken)) {
                revert MarketAlreadyListed();
            }
        }
        allMarkets.push(CToken(cToken));
    }

    /**
     * @notice Set the given borrow caps for the given cToken markets.
     *   Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps.
     *   A borrow cap of 0 corresponds to unlimited borrowing.
     * @param cTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set.
     *   A value of 0 corresponds to unlimited borrowing.
     */
    function _setMarketBorrowCaps(CToken[] calldata cTokens, uint256[] calldata newBorrowCaps) external {
        if (msg.sender != admin && msg.sender != borrowCapGuardian) {
            revert AddressUnauthorized();
        }
        uint256 numMarkets = cTokens.length;
        uint256 numBorrowCaps = newBorrowCaps.length;

        if (numMarkets == 0 || numMarkets != numBorrowCaps) {
            revert InvalidValue();
        }

        for (uint256 i = 0; i < numMarkets; i++) {
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

        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }

    /**
     * @notice Admin function to set market mint paused
     * @param cToken market token address
     * @param state pause or unpause
     */
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

    /**
     * @notice Admin function to set market borrow paused
     * @param cToken market token address
     * @param state pause or unpause
     */
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

    /**
     * @notice Admin function to set transfer paused
     * @param state pause or unpause
     */
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

    /**
     * @notice Admin function to set seize paused
     * @param state pause or unpause
     */
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

    /**
     * @notice Update implementation address
     */
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

    /**
     * @notice Returns minimum value of a and b
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a <= b) {
            return a;
        } else {
            return b;
        }
    }

    /**
     * @notice Returns market status
     */
    function getIsMarkets(address cToken)
        external
        view
        override
        returns (
            bool,
            uint256,
            bool
        )
    {
        return (markets[cToken].isListed, markets[cToken].collateralFactorScaled, markets[cToken].isComped);
    }

    /**
     * @notice Returns if user joined market
     */
    function getAccountMembership(address cToken, address user) external view override returns (bool) {
        return markets[cToken].accountMembership[user];
    }

    /**
     * @notice Returns all markets
     */
    function getAllMarkets() external view override returns (CToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Returns all markets user joined
     */
    function getAccountAssets(address user) external view override returns (CToken[] memory) {
        return accountAssets[user];
    }
}
