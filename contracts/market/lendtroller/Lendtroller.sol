// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165 } from "contracts/libraries/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IMToken, accountSnapshot } from "contracts/interfaces/market/IMToken.sol";

/// @title Curvance Lendtroller
/// @notice Manages risk within the lending markets
contract Lendtroller is ILendtroller, ERC165 {
    /// TYPES ///

    /// @param assets Array of account assets.
    /// @param lastBorrowTimestamp Last time an account borrowed an asset.
    struct AccountData {
        IMToken[] assets;
        uint256 lastBorrowTimestamp;
    }

    /// @param isListed Whether or not this market token is listed.
    /// @param collateralizationRatio Multiplier representing the most one can
    ///                 borrow against their collateral in this market.
    ///                 On scale of 0 to 1e18 with 0.8e18 corresponding to 80%
    ///                 collateral value.
    /// @param accountInMarket Mapping that indicates whether an account is in
    ///                 a market, 0 or 1 for no; 2 for yes
    struct MarketToken {
        bool isListed;
        uint256 collateralizationRatio;
        mapping(address => uint256) accountInMarket;
    }

    /// CONSTANTS ///

    /// @notice gaugePool contract address.
    address public immutable gaugePool;
    /// @notice Scalar for math.
    uint256 internal constant expScale = 1e18;
    /// @notice 100% E.g close entire position.
    uint256 internal constant maxCloseFactor = 1e18;
    /// @notice Maximum collateralization ratio. 90%
    uint256 internal constant maxCollateralizationRatio = 0.9e18;
    /// @notice Minimum hold time to prevent oracle price attacks.
    uint256 internal constant minHoldPeriod = 15 minutes;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    // `bytes4(keccak256(bytes("Lendtroller__InvalidValue()")))`
    uint256 internal constant _INVALID_VALUE_SELECTOR = 0x74ebdb4f;

    // `bytes4(keccak256(bytes("Lendtroller__InsufficientShortfall()")))`
    uint256 internal constant _INSUFFICIENT_SHORTFALL_SELECTOR = 0xa160c28b;

    /// STORAGE ///

    /// @dev 1 = unpaused; 2 = paused
    uint256 public transferPaused = 1;
    /// @dev 1 = unpaused; 2 = paused
    uint256 public seizePaused = 1;
    /// @dev Token => 0 or 1 = unpaused; 2 = paused
    mapping(address => uint256) public mintPaused;
    /// @dev Token => 0 or 1 = unpaused; 2 = paused
    mapping(address => uint256) public borrowPaused;
    /// @notice Token => Borrow Cap
    /// @dev 0 = unlimited
    mapping(address => uint256) public borrowCaps;

    /// @notice Maximum % that a liquidator can repay when liquidating a user.
    uint256 public closeFactor;
    /// @notice Default discount multiplier a liquidation receives.
    uint256 public liquidationIncentiveScaled;
    /// @notice PositionFolding contract address.
    address public positionFolding;

    /// @notice A list of all markets for frontend.
    IMToken[] public allMarkets;

    /// @notice Market Token => Token metadata.
    mapping(address => MarketToken) public marketTokenData;
    /// @notice Account => Assets, lastBorrowTimestamp.
    mapping(address => AccountData) public accountAssets;

    /// EVENTS ///

    event MarketListed(address mToken);
    event MarketEntered(address mToken, address account);
    event MarketExited(address mToken, address account);
    event NewCloseFactor(uint256 oldCloseFactor, uint256 newCloseFactor);
    event NewCollateralizationRatio(
        IMToken mToken,
        uint256 oldCR,
        uint256 newCR
    );
    event NewLiquidationIncentive(
        uint256 oldLiquidationIncentiveScaled,
        uint256 newLiquidationIncentiveScaled
    );
    event ActionPaused(string action, bool pauseState);
    event ActionPaused(IMToken mToken, string action, bool pauseState);
    event NewBorrowCap(IMToken mToken, uint256 newBorrowCap);
    event SetDisableCollateral(IMToken mToken, bool disable);
    event NewPositionFoldingContract(address oldPF, address newPF);

    /// ERRORS ///

    error Lendtroller__CentralRegistryIsInvalid();
    error Lendtroller__PositionFoldingIsInvalid();
    error Lendtroller__GaugePoolIsZeroAddress();
    error Lendtroller__TokenNotListed();
    error Lendtroller__TokenAlreadyListed();
    error Lendtroller__Paused();
    error Lendtroller__InsufficientLiquidity();
    error Lendtroller__PriceError();
    error Lendtroller__HasActiveLoan();
    error Lendtroller__BorrowCapReached();
    error Lendtroller__InsufficientShortfall();
    error Lendtroller__TooMuchRepay();
    error Lendtroller__LendtrollerMismatch();
    error Lendtroller__InvalidValue();
    error Lendtroller__AddressUnauthorized();
    error Lendtroller__MinimumHoldPeriod();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "Lendtroller: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "Lendtroller: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyAuthorizedPermissions(bool state) {
        if (state) {
            require(
                centralRegistry.hasDaoPermissions(msg.sender),
                "Lendtroller: UNAUTHORIZED"
            );
        } else {
            require(
                centralRegistry.hasElevatedPermissions(msg.sender),
                "Lendtroller: UNAUTHORIZED"
            );
        }
        _;
    }

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address gaugePool_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert Lendtroller__CentralRegistryIsInvalid();
        }
        if (gaugePool_ == address(0)) {
            revert Lendtroller__GaugePoolIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        gaugePool = gaugePool_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Returns the assets an account has entered
    /// @param account The address of the account to pull assets for
    /// @return A dynamic list with the assets the account has entered
    function getAccountAssets(
        address account
    ) external view override returns (IMToken[] memory) {
        return accountAssets[account].assets;
    }

    /// @notice Add assets to be included in account liquidity calculation
    /// @param mTokens The list of addresses of the mToken markets to be enabled
    function enterMarkets(address[] calldata mTokens) external {
        uint256 numCTokens = mTokens.length;

        for (uint256 i; i < numCTokens; ) {
            unchecked {
                _enterMarket(mTokens[i++], msg.sender);
            }
        }
    }

    /// @notice Removes an asset from an account's liquidity calculation
    /// @dev Sender must not have an outstanding borrow balance in the asset,
    ///      or be providing necessary collateral for an outstanding borrow.
    /// @param mTokenAddress The address of the asset to be removed
    function exitMarket(address mTokenAddress) external {
        IMToken mToken = IMToken(mTokenAddress);
        // Get sender tokensHeld and amountOwed underlying from the mToken
        (uint256 tokensHeld, uint256 amountOwed, ) = mToken.getAccountSnapshot(
            msg.sender
        );

        // Do not let them leave if they owe a balance
        if (amountOwed != 0) {
            revert Lendtroller__HasActiveLoan();
        }

        MarketToken storage marketToExit = marketTokenData[mTokenAddress];

        // We do not need to update any values if the account is not ‘in’ the market
        if (marketToExit.accountInMarket[msg.sender] < 2) {
            return;
        }

        // Fail if the sender is not permitted to redeem all of their tokens
        _redeemAllowed(mTokenAddress, msg.sender, tokensHeld);

        // Remove mToken account membership to `mTokenAddress`
        marketToExit.accountInMarket[msg.sender] = 1;

        // Delete mToken from the account’s list of assets
        IMToken[] memory userAssetList = accountAssets[msg.sender].assets;

        // Cache asset list
        uint256 numUserAssets = userAssetList.length;
        uint256 assetIndex = numUserAssets;

        for (uint256 i; i < numUserAssets; ++i) {
            if (userAssetList[i] == mToken) {
                assetIndex = i;
                break;
            }
        }

        // Validate we found the asset and remove 1 from numUserAssets
        // so it corresponds to last element index now starting at index 0
        require(
            assetIndex < numUserAssets--,
            "Lendtroller: asset list misconfigured"
        );

        // copy last item in list to location of item to be removed
        IMToken[] storage storedList = accountAssets[msg.sender].assets;
        // copy the last market index slot to assetIndex
        storedList[assetIndex] = storedList[numUserAssets];
        // remove the last element
        storedList.pop();

        emit MarketExited(mTokenAddress, msg.sender);
    }

    /// @notice Checks if the account should be allowed to mint tokens
    ///         in the given market
    /// @param mToken The market to verify the mint against
    function mintAllowed(address mToken, address) external view override {
        if (mintPaused[mToken] == 2) {
            revert Lendtroller__Paused();
        }

        if (!marketTokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
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
    function borrowAllowedWithNotify(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external override {
        require(
            marketTokenData[msg.sender].isListed,
            "Lendtroller: Caller not MToken"
        );
        accountAssets[borrower].lastBorrowTimestamp = block.timestamp;

        borrowAllowed(mToken, borrower, borrowAmount);
    }

    /// @notice Checks if the account should be allowed to repay a borrow
    ///         in the given market
    /// @param mToken The market to verify the repay against
    /// @param account The account who will have their loan repaid
    function repayAllowed(
        address mToken,
        address account
    ) external view override {
        if (!marketTokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        // We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        // as well as short term price manipulations if the dynamic dual oracle
        // fails to protect the market somehow
        if (
            accountAssets[account].lastBorrowTimestamp + minHoldPeriod >
            block.timestamp
        ) {
            revert Lendtroller__MinimumHoldPeriod();
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
        if (!marketTokenData[mTokenBorrowed].isListed) {
            revert Lendtroller__TokenNotListed();
        }
        if (!marketTokenData[mTokenCollateral].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        // The borrower must have shortfall in order to be liquidatable
        (, uint256 shortfall) = _getAccountLiquidity(borrower);

        assembly {
            if iszero(shortfall) {
                // store the error selector to location 0x0
                mstore(0x0, _INSUFFICIENT_SHORTFALL_SELECTOR)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }

        // The liquidator may not close out more collateral than
        // what is allowed by the closeFactor
        uint256 borrowBalance = IMToken(mTokenBorrowed).borrowBalanceStored(
            borrower
        );
        uint256 maxClose = (closeFactor * borrowBalance) / expScale;

        if (repayAmount > maxClose) {
            revert Lendtroller__TooMuchRepay();
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
        if (seizePaused == 2) {
            revert Lendtroller__Paused();
        }

        if (!marketTokenData[mTokenBorrowed].isListed) {
            revert Lendtroller__TokenNotListed();
        }
        if (!marketTokenData[mTokenCollateral].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        if (
            IMToken(mTokenCollateral).lendtroller() !=
            IMToken(mTokenBorrowed).lendtroller()
        ) {
            revert Lendtroller__LendtrollerMismatch();
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
        if (transferPaused == 2) {
            revert Lendtroller__Paused();
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
        // Read oracle prices for borrowed and collateral markets
        IPriceRouter router = getPriceRouter();
        (uint256 debtTokenPrice, uint256 debtTokenError) = router.getPrice(
            mTokenBorrowed,
            true,
            false
        );
        (uint256 collateralTokenPrice, uint256 collateralTokenError) = router
            .getPrice(mTokenCollateral, true, true);

        // Validate that we were able to securely query prices from the dual oracle
        if (debtTokenError == 2 || collateralTokenError == 2) {
            revert Lendtroller__PriceError();
        }

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        //  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        //  seizeTokens = seizeAmount / exchangeRate
        //   = actualRepayAmount * (liquidationIncentive * priceBorrowedDebt) / (priceCollateral * exchangeRate)
        uint256 ratio = (liquidationIncentiveScaled *
            debtTokenPrice *
            expScale) /
            (collateralTokenPrice *
                IMToken(mTokenCollateral).exchangeRateStored());

        return (ratio * actualRepayAmount) / expScale;
    }

    /// @notice Sets the closeFactor used when liquidating borrows
    /// @dev Admin function to set closeFactor
    /// @param newCloseFactor New close factor, scaled by 1e18
    function setCloseFactor(
        uint256 newCloseFactor
    ) external onlyElevatedPermissions {
        if (newCloseFactor > maxCloseFactor) {
            revert Lendtroller__InvalidValue();
        }
        // Cache the current value for event log and gas savings
        uint256 oldCloseFactor = closeFactor;
        // Assign new closeFactor
        closeFactor = newCloseFactor;

        emit NewCloseFactor(oldCloseFactor, newCloseFactor);
    }

    /// @notice Sets the collateralizationRatio for a market token
    /// @param mToken The market to set the collateralization ratio on
    /// @param newCollateralizationRatio The new collateral factor, scaled by 1e18
    function setCollateralizationRatio(
        IMToken mToken,
        uint256 newCollateralizationRatio
    ) external onlyElevatedPermissions {
        // Validate collateralization ratio is not above maximum allowed
        if (maxCollateralizationRatio < newCollateralizationRatio) {
            revert Lendtroller__InvalidValue();
        }

        // Verify mToken is listed
        MarketToken storage marketToken = marketTokenData[address(mToken)];
        if (!marketToken.isListed) {
            revert Lendtroller__TokenNotListed();
        }

        (, uint256 errorCode) = getPriceRouter().getPrice(
            address(mToken),
            true,
            true
        );

        // Validate that we got a price
        if (errorCode == 2) {
            revert Lendtroller__PriceError();
        }

        // Cache the current value for gas and log
        uint256 oldCollateralizationRatio = marketToken.collateralizationRatio;

        // Assign new collateralization ratio
        // Note that a collateralization ratio of 0 corresponds to
        // no collateralization of the mToken
        marketToken.collateralizationRatio = newCollateralizationRatio;

        emit NewCollateralizationRatio(
            mToken,
            oldCollateralizationRatio,
            newCollateralizationRatio
        );
    }

    /// @notice Sets liquidationIncentive
    /// @dev Admin function to set liquidationIncentive
    /// @param newLiquidationIncentiveScaled New liquidationIncentive scaled by 1e18
    function setLiquidationIncentive(
        uint256 newLiquidationIncentiveScaled
    ) external onlyElevatedPermissions {
        // Cache the current value for event log and gas savings
        uint256 oldLiquidationIncentiveScaled = liquidationIncentiveScaled;

        // Assign new liquidation incentive
        liquidationIncentiveScaled = newLiquidationIncentiveScaled;

        emit NewLiquidationIncentive(
            oldLiquidationIncentiveScaled,
            newLiquidationIncentiveScaled
        );
    }

    /// @notice Add the market token to the market and set it as listed
    /// @dev Admin function to set isListed and add support for the market
    /// @param mToken The address of the market (token) to list
    function listMarketToken(address mToken) external onlyElevatedPermissions {
        if (marketTokenData[mToken].isListed) {
            revert Lendtroller__TokenAlreadyListed();
        }

        IMToken(mToken).tokenType(); // Sanity check to make sure its really a mToken

        MarketToken storage market = marketTokenData[mToken];
        market.isListed = true;
        market.collateralizationRatio = 0;

        _addMarketToken(mToken);

        if (IMToken(mToken).totalSupply() == 0) {
            require(
                IMToken(mToken).startMarket(msg.sender),
                "Lendtroller: Market needs to be initialized"
            );
        }

        emit MarketListed(mToken);
    }

    /// @notice Set the given borrow caps for the given mToken markets.
    ///         Borrowing that brings total borrows to or above borrow cap will revert.
    /// @dev Admin or borrowCapGuardian function to set the borrow caps.
    ///      A borrow cap of 0 corresponds to unlimited borrowing.
    /// @param mTokens The addresses of the markets (tokens) to
    ///                change the borrow caps for
    /// @param newBorrowCaps The new borrow cap values in underlying to be set.
    ///                      A value of 0 corresponds to unlimited borrowing.
    function setMarketTokenBorrowCaps(
        IMToken[] calldata mTokens,
        uint256[] calldata newBorrowCaps
    ) external onlyDaoPermissions {
        uint256 numMarkets = mTokens.length;

        assembly {
            if iszero(numMarkets) {
                // store the error selector to location 0x0
                mstore(0x0, _INVALID_VALUE_SELECTOR)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }

        if (numMarkets != newBorrowCaps.length) {
            _revert(_INVALID_VALUE_SELECTOR);
        }

        for (uint256 i; i < numMarkets; ++i) {
            borrowCaps[address(mTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(mTokens[i], newBorrowCaps[i]);
        }
    }

    /// @notice Returns market status
    /// @param mToken market token address
    function getMarketTokenData(
        address mToken
    ) external view override returns (bool, uint256) {
        return (
            marketTokenData[mToken].isListed,
            marketTokenData[mToken].collateralizationRatio
        );
    }

    /// @notice Returns if user joined market
    /// @param mToken market token address
    /// @param user user address
    function getAccountMembership(
        address mToken,
        address user
    ) external view override returns (bool) {
        return marketTokenData[mToken].accountInMarket[user] == 2;
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

    /// @notice Admin function to set market mint paused
    /// @dev requires timelock authority if unpausing
    /// @param mToken market token address
    /// @param state pause or unpause
    function setMintPaused(
        IMToken mToken,
        bool state
    ) external onlyAuthorizedPermissions(state) {
        if (!marketTokenData[address(mToken)].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        mintPaused[address(mToken)] = state ? 2 : 1;
        emit ActionPaused(mToken, "Mint Paused", state);
    }

    /// @notice Admin function to set market borrow paused
    /// @dev requires timelock authority if unpausing
    /// @param mToken market token address
    /// @param state pause or unpause
    function setBorrowPaused(
        IMToken mToken,
        bool state
    ) external onlyAuthorizedPermissions(state) {
        if (!marketTokenData[address(mToken)].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        borrowPaused[address(mToken)] = state ? 2 : 1;
        emit ActionPaused(mToken, "Borrow Paused", state);
    }

    /// @notice Admin function to set transfer paused
    /// @dev requires timelock authority if unpausing
    /// @param state pause or unpause
    function setTransferPaused(
        bool state
    ) external onlyAuthorizedPermissions(state) {
        transferPaused = state ? 2 : 1;
        emit ActionPaused("Transfer Paused", state);
    }

    /// @notice Admin function to set seize paused
    /// @dev requires timelock authority if unpausing
    /// @param state pause or unpause
    function setSeizePaused(
        bool state
    ) external onlyAuthorizedPermissions(state) {
        seizePaused = state ? 2 : 1;
        emit ActionPaused("Seize Paused", state);
    }

    /// @notice Admin function to set position folding address
    /// @param newPositionFolding new position folding address
    function setPositionFolding(
        address newPositionFolding
    ) external onlyElevatedPermissions {
        if (
            !ERC165Checker.supportsInterface(
                newPositionFolding,
                type(IPositionFolding).interfaceId
            )
        ) {
            revert Lendtroller__PositionFoldingIsInvalid();
        }

        // Cache the current value for event log
        address oldPositionFolding = positionFolding;

        // Assign new position folding contract
        positionFolding = newPositionFolding;

        emit NewPositionFoldingContract(
            oldPositionFolding,
            newPositionFolding
        );
    }

    /// @notice Updates `accounts` lastBorrowTimestamp to the current block timestamp
    /// @dev The caller must be a listed MToken in the `markets` mapping
    /// @param borrower The address of the account that has just borrowed
    function notifyAccountBorrow(address borrower) external override {
        require(
            marketTokenData[msg.sender].isListed,
            "Lendtroller: Caller not MToken"
        );
        accountAssets[borrower].lastBorrowTimestamp = block.timestamp;
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Checks if the account should be allowed to borrow
    ///         the underlying asset of the given market
    /// @param mToken The market to verify the borrow against
    /// @param borrower The account which would borrow the asset
    /// @param borrowAmount The amount of underlying the account would borrow
    function borrowAllowed(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) public override {
        if (borrowPaused[mToken] == 2) {
            revert Lendtroller__Paused();
        }

        if (!marketTokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        if (marketTokenData[mToken].accountInMarket[borrower] < 2) {
            // only mTokens may call borrowAllowed if borrower not in market
            if (msg.sender != mToken) {
                revert Lendtroller__AddressUnauthorized();
            }

            // The user is not in the market yet, so make them enter
            marketTokenData[mToken].accountInMarket[borrower] = 2;
            accountAssets[borrower].assets.push(IMToken(mToken));

            emit MarketEntered(mToken, borrower);
        }

        uint256 borrowCap = borrowCaps[mToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            // Validate that if there is a borrow cap,
            // we will not be over the cap with this new borrow
            if ((IMToken(mToken).totalBorrows() + borrowAmount) > borrowCap) {
                revert Lendtroller__BorrowCapReached();
            }
        }

        // We call hypothetical account liquidity as normal but with
        // heavier error code restriction on borrow
        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(
            borrower,
            IMToken(mToken),
            0,
            borrowAmount,
            1
        );

        if (shortfall > 0) {
            revert Lendtroller__InsufficientLiquidity();
        }
    }

    /// @notice Fetches the current price router from the central registry
    /// @return Current PriceRouter interface address
    function getPriceRouter() public view returns (IPriceRouter) {
        return IPriceRouter(centralRegistry.priceRouter());
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
                0,
                2
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
                0,
                2
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
                borrowAmount,
                2
            );

        return (liquidity, shortfall);
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ILendtroller).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Documents a user entering a market for liquidity calculations
    /// @param mToken The market to enter
    /// @param user The address of the account entering the market
    function _enterMarket(address mToken, address user) internal {
        MarketToken storage marketToJoin = marketTokenData[mToken];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return;
        }

        if (marketToJoin.accountInMarket[user] == 2) {
            // user already joined market
            return;
        }

        marketToJoin.accountInMarket[user] = 2;
        accountAssets[user].assets.push(IMToken(mToken));

        emit MarketEntered(mToken, user);
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
        if (!marketTokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        // We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        // as well as short term price manipulations if the dynamic dual oracle
        // fails to protect the market somehow
        if (
            accountAssets[redeemer].lastBorrowTimestamp + minHoldPeriod >
            block.timestamp
        ) {
            revert Lendtroller__MinimumHoldPeriod();
        }

        // If the redeemer is not 'in' the market, then we can bypass
        // the liquidity check
        if (marketTokenData[mToken].accountInMarket[redeemer] < 2) {
            return;
        }

        // Otherwise, perform a hypothetical liquidity check to guard against
        // shortfall
        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(
            redeemer,
            IMToken(mToken),
            redeemTokens,
            0,
            2
        );

        if (shortfall > 0) {
            revert Lendtroller__InsufficientLiquidity();
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
                0,
                2
            );
    }

    /// @notice Determine what the account liquidity would be if
    ///         the given amounts were redeemed/borrowed
    /// @param mTokenModify The market to hypothetically redeem/borrow in
    /// @param account The account to determine liquidity for
    /// @param redeemTokens The number of tokens to hypothetically redeem
    /// @param borrowAmount The amount of underlying to hypothetically borrow
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return uint256 hypothetical account liquidity in excess
    ///              of collateral requirements,
    /// @return uint256 hypothetical account shortfall below collateral requirements)
    function _getHypotheticalAccountLiquidity(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount,
        uint256 errorCodeBreakpoint
    ) internal view returns (uint256, uint256) {
        (
            ,
            uint256 maxBorrow,
            uint256 sumBorrowPlusEffects
        ) = _getHypotheticalAccountPosition(
                account,
                mTokenModify,
                redeemTokens,
                borrowAmount,
                errorCodeBreakpoint
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
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return sumCollateral total collateral amount of user
    /// @return maxBorrow max borrow amount of user
    /// @return sumBorrowPlusEffects total borrow amount of user
    function _getHypotheticalAccountPosition(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount,
        uint256 errorCodeBreakpoint
    )
        internal
        view
        returns (
            uint256 sumCollateral,
            uint256 maxBorrow,
            uint256 sumBorrowPlusEffects
        )
    {
        uint256 numAccountAssets = accountAssets[account].assets.length;
        bool isCToken;
        IPriceRouter router = getPriceRouter();
        accountSnapshot memory assetSnapshot;

        // For each asset the account is in
        for (uint256 i; i < numAccountAssets; ) {
            // Pull user token snapshot data for the asset and then increment i
            unchecked {
                assetSnapshot = accountAssets[account]
                    .assets[i++]
                    .getAccountSnapshotPacked(account);
            }
            isCToken = assetSnapshot.tokenType == 1;

            // Collateralized assets (CTokens) use the lower price, Debt assets (DTokens) use the higher price
            (uint256 price, uint256 errorCode) = router.getPrice(
                address(assetSnapshot.asset),
                true,
                isCToken
            );
            if (errorCode == errorCodeBreakpoint) {
                revert Lendtroller__PriceError();
            }

            if (isCToken) {
                // If the asset has a collateral ratio increment their collateral and max borrow value
                if (
                    !(marketTokenData[address(assetSnapshot.asset)]
                        .collateralizationRatio == 0)
                ) {
                    uint256 assetValue = (assetSnapshot.mTokenBalance *
                        price *
                        assetSnapshot.exchangeRateScaled) / expScale;

                    sumCollateral += assetValue;
                    maxBorrow +=
                        (assetValue *
                            marketTokenData[address(assetSnapshot.asset)]
                                .collateralizationRatio) /
                        expScale;
                }
            } else {
                // If they have a borrow balance we need to document it
                if (assetSnapshot.borrowBalance > 0) {
                    sumBorrowPlusEffects += ((price *
                        assetSnapshot.borrowBalance) / expScale);
                }
            }

            // Calculate effects of interacting with mTokenModify
            if (assetSnapshot.asset == mTokenModify) {
                // If its a CToken our only option is to redeem it since it cant be borrowed
                // If its a DToken we can redeem it but it will not have any effect on borrow amount
                // since DToken have a collateral value of 0
                if (isCToken) {
                    if (
                        !(marketTokenData[address(assetSnapshot.asset)]
                            .collateralizationRatio == 0)
                    ) {
                        // Pre-compute a conversion factor
                        // from tokens -> $ (normalized price value)
                        uint256 tokensToDenom = (((marketTokenData[
                            address(assetSnapshot.asset)
                        ].collateralizationRatio *
                            assetSnapshot.exchangeRateScaled) / expScale) *
                            price) / expScale;

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

    /// @notice Add the market token to the markets mapping and set it as listed
    /// @param mToken The address of the market (token) to list
    function _addMarketToken(address mToken) internal {
        uint256 numMarkets = allMarkets.length;

        for (uint256 i; i < numMarkets; ) {
            unchecked {
                if (allMarkets[i++] == IMToken(mToken)) {
                    revert Lendtroller__TokenAlreadyListed();
                }
            }
        }
        allMarkets.push(IMToken(mToken));
    }

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }
}
