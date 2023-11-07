// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165 } from "contracts/libraries/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { WAD } from "contracts/libraries/Constants.sol";

/// @title Curvance Lendtroller
/// @notice Manages risk within the lending markets
contract Lendtroller is ILendtroller, ERC165 {
    /// TYPES ///

    struct AccountData {
        /// @notice Array of account assets.
        IMToken[] assets;
        /// @notice cooldownTimestamp Last time an account performed an action,
        ///         which activates the redeem/repay/exit market cooldown.
        uint256 cooldownTimestamp;
    }

    struct AccountMetadata {
        /// @notice Value that indicates whether an account has an active position in the token.
        /// @dev    0 or 1 for no; 2 for yes
        uint256 activePosition;
        /// @notice The amount of collateral an account has posted.
        /// @dev    Only relevant for cTokens not dTokens
        uint256 collateralPosted;
    }

    struct MarketToken {
        /// @notice Whether or not this market token is listed.
        /// @dev    false = unlisted; true = listed
        bool isListed;
        /// @notice The ratio at which this token can be collateralized.
        /// @dev    in `WAD` format, with 0.8e18 = 80% collateral value
        uint256 collRatio;
        /// @notice The collateral requirement where dipping below this will cause a soft liquidation.
        /// @dev    in `WAD` format, with 1.2e18 = 120% collateral vs debt value
        uint256 collReqA;
        /// @notice The collateral requirement where dipping below this will cause a hard liquidation.
        /// @dev    in `WAD` format, with 1.2e18 = 120% collateral vs debt value
        uint256 collReqB;
        /// @notice The ratio at which this token will be compensated on liquidation.
        /// @dev    In `WAD` format, stored as (Incentive + WAD)
        ///         e.g 1.05e18 = 5% incentive, this saves gas for liquidation calculations
        uint256 liqInc;
        /// @notice The protocol fee that will be taken on liquidation for this token.
        /// @dev    In `WAD` format, 0.01e18 = 1%
        ///         Note: this is stored as (Fee * WAD) / `liqInc`
        ///         in order to save gas for liquidation calculations
        uint256 liqFee;
        /// @notice Mapping that stores account information like token positions and collateral posted.
        mapping(address => AccountMetadata) accountData;
    }

    /// CONSTANTS ///

    /// @notice Maximum collateral requirement to avoid liquidation. 40%
    uint256 internal constant _MAX_COLLATERAL_REQUIREMENT = 0.4e18;
    /// @notice Maximum collateralization ratio. 91%
    uint256 internal constant _MAX_COLLATERALIZATION_RATIO = 0.91e18;
    /// @notice Minimum hold time to prevent oracle price attacks.
    uint256 internal constant _MIN_HOLD_PERIOD = 20 minutes;
    /// @notice The maximum liquidation incentive. 30%
    uint256 internal constant _MAX_LIQUIDATION_INCENTIVE = .3e18;
    /// @notice The minimum liquidation incentive. 1%
    uint256 internal constant _MIN_LIQUIDATION_INCENTIVE = .01e18;
    /// @notice The maximum liquidation incentive. 5%
    uint256 internal constant _MAX_LIQUIDATION_FEE = .05e18;
    /// `bytes4(keccak256(bytes("Lendtroller__InvalidParameter()")))`
    uint256 internal constant _INVALID_PARAMETER_SELECTOR = 0x31765827;
    /// `bytes4(keccak256(bytes("Lendtroller__InsufficientShortfall()")))`
    uint256 internal constant _INSUFFICIENT_SHORTFALL_SELECTOR = 0x751bba8d;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;
    /// @notice gaugePool contract address.
    GaugePool public immutable gaugePool;

    /// STORAGE ///

    /// @dev 1 = unpaused; 2 = paused
    uint256 public transferPaused = 1;
    /// @dev 1 = unpaused; 2 = paused
    uint256 public seizePaused = 1;
    /// @dev Token => 0 or 1 = unpaused; 2 = paused
    mapping(address => uint256) public mintPaused;
    /// @dev Token => 0 or 1 = unpaused; 2 = paused
    mapping(address => uint256) public borrowPaused;
    /// @notice Token => Collateral Posted
    mapping(address => uint256) public collateralPosted;
    /// @notice Token => Collateral Cap
    mapping(address => uint256) public collateralCaps;

    /// @notice Maximum % that a liquidator can repay when liquidating a user,
    /// @dev    In `WAD` format, default 50%
    uint256 public closeFactor = 0.5e18;
    /// @notice PositionFolding contract address.
    address public positionFolding;

    /// @notice A list of all markets for frontend.
    IMToken[] public allMarkets;

    /// @notice Market Token => isListed, Token Characteristics, Account Data.
    mapping(address => MarketToken) public tokenData;
    /// @notice Account => Assets, cooldownTimestamp.
    mapping(address => AccountData) public accountAssets;

    /// EVENTS ///

    event TokenListed(address mToken);
    event CollateralPosted(address account, address cToken, uint256 amount);
    event CollateralRemoved(address account, address cToken, uint256 amount);
    event TokenPositionCreated(address mToken, address account);
    event TokenPositionClosed(address mToken, address account);
    event NewCloseFactor(uint256 oldCloseFactor, uint256 newCloseFactor);
    event CollateralTokenUpdated(
        IMToken mToken,
        uint256 newLI,
        uint256 newLF,
        uint256 newCR_A,
        uint256 newCR_B,
        uint256 newCR
    );
    event ActionPaused(string action, bool pauseState);
    event TokenActionPaused(IMToken mToken, string action, bool pauseState);
    event NewCollateralCap(IMToken mToken, uint256 newCollateralCap);
    event NewPositionFoldingContract(address oldPF, address newPF);

    /// ERRORS ///

    error Lendtroller__Unauthorized();
    error Lendtroller__TokenNotListed();
    error Lendtroller__TokenAlreadyListed();
    error Lendtroller__Paused();
    error Lendtroller__InsufficientCollateral();
    error Lendtroller__InsufficientLiquidity();
    error Lendtroller__InsufficientShortfall();
    error Lendtroller__PriceError();
    error Lendtroller__HasActiveLoan();
    error Lendtroller__CollateralCapReached();
    error Lendtroller__LendtrollerMismatch();
    error Lendtroller__InvalidParameter();
    error Lendtroller__MinimumHoldPeriod();
    error Lendtroller__InvariantError();

    /// MODIFIERS ///

    modifier onlyElevatedPermissions() {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            revert Lendtroller__Unauthorized();
        }
        _;
    }

    modifier onlyAuthorizedPermissions(bool state) {
        if (state) {
            if (!centralRegistry.hasDaoPermissions(msg.sender)) {
                revert Lendtroller__Unauthorized();
            }
        } else {
            if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
                revert Lendtroller__Unauthorized();
            }
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
            _revert(_INVALID_PARAMETER_SELECTOR);
        }
        if (gaugePool_ == address(0)) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        centralRegistry = centralRegistry_;
        gaugePool = GaugePool(gaugePool_);
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

    /// @notice Post collateral in some cToken for borrowing inside this market
    /// @param mToken The address of the mToken to post collateral for
    function postCollateral(address mToken, uint256 amount) public {
        AccountMetadata storage accountData = tokenData[mToken].accountData[msg.sender];

        if (!tokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        if (!IMToken(mToken).isCToken()) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        if (accountData.collateralPosted + amount >= IMToken(mToken).balanceOf(msg.sender)) {
            revert Lendtroller__InsufficientCollateral();
        }

        if (collateralPosted[mToken] + amount > collateralCaps[mToken]) {
            revert Lendtroller__CollateralCapReached();
        }

        collateralPosted[mToken] = collateralPosted[mToken] + amount;
        accountData.collateralPosted = accountData.collateralPosted + amount;
        emit CollateralPosted(msg.sender, mToken, amount);

        if (accountData.activePosition != 2) {
            accountData.activePosition = 2;
            accountAssets[msg.sender].assets.push(IMToken(mToken));

            emit TokenPositionCreated(mToken, msg.sender);
        }
    }

    /// @notice Post collateral in some cToken for borrowing inside this market
    /// @param mToken The address of the mToken to post collateral for
    function removeCollateral(address mToken, uint256 amount) public {
        AccountMetadata storage accountData = tokenData[mToken].accountData[msg.sender];

        // We can check this instead of .isListed,
        // since any non-listed token will always have activePosition == 0,
        // and this lets us check for any invariant errors 
        if (accountData.activePosition != 2) {
            revert Lendtroller__InvariantError();
        }

        if (!IMToken(mToken).isCToken()) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        if (accountData.collateralPosted < amount) {
            revert Lendtroller__InsufficientCollateral();
        }

        // Fail if the sender is not permitted to redeem `amount`
        // note: amount is in shares/tokens
        _canRedeem(mToken, msg.sender, amount);

        collateralPosted[mToken] = collateralPosted[mToken] - amount;
        emit CollateralRemoved(msg.sender, mToken, amount);

        if (accountData.collateralPosted == amount) {
            // Remove active position flag
            accountData.activePosition = 1;

            // Delete mToken from the account’s list of assets
            IMToken[] memory userAssetList = accountAssets[msg.sender].assets;

            // Cache asset list
            uint256 numUserAssets = userAssetList.length;
            uint256 assetIndex = numUserAssets;

            for (uint256 i; i < numUserAssets; ++i) {
                if (userAssetList[i] == IMToken(mToken)) {
                    assetIndex = i;
                    break;
                }
            }

            // Validate we found the asset and remove 1 from numUserAssets
            // so it corresponds to last element index now starting at index 0
            if (assetIndex >= numUserAssets--) {
                revert Lendtroller__InvariantError();
            }

            // copy last item in list to location of item to be removed
            IMToken[] storage storedList = accountAssets[msg.sender].assets;
            // copy the last market index slot to assetIndex
            storedList[assetIndex] = storedList[numUserAssets];
            // remove the last element
            storedList.pop();

            emit TokenPositionClosed(mToken, msg.sender);
        }
 
    }

    /// @notice Removes an asset from an account's liquidity calculation
    /// @dev Sender must not have an outstanding borrow balance in the asset,
    ///      or be providing necessary collateral for an outstanding borrow.
    /// @param mTokenAddress The address of the asset to be removed
    function exitMarket(address mTokenAddress) external {
        IMToken mToken = IMToken(mTokenAddress);
        // Get sender tokensHeld and amountOwed underlying from the mToken
        (uint256 tokens, uint256 amountOwed, ) = mToken.getSnapshot(
            msg.sender
        );

        // Do not let them leave if they owe a balance
        if (amountOwed != 0) {
            revert Lendtroller__HasActiveLoan();
        }

        MarketToken storage marketToExit = tokenData[mTokenAddress];

        // We do not need to update any values if the account is not ‘in’ the market
        if (marketToExit.accountData[msg.sender].activePosition < 2) {
            return;
        }

        // Fail if the sender is not permitted to redeem all of their tokens
        _canRedeem(mTokenAddress, msg.sender, tokens);

        // Remove mToken account membership to `mTokenAddress`
        marketToExit.accountData[msg.sender].activePosition = 1;

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
        if (assetIndex >= numUserAssets--) {
            revert Lendtroller__InvariantError();
        }

        // copy last item in list to location of item to be removed
        IMToken[] storage storedList = accountAssets[msg.sender].assets;
        // copy the last market index slot to assetIndex
        storedList[assetIndex] = storedList[numUserAssets];
        // remove the last element
        storedList.pop();

        emit TokenPositionClosed(mTokenAddress, msg.sender);
    }

    /// @notice Checks if the account should be allowed to mint tokens
    ///         in the given market
    /// @param mToken The token to verify mints against
    function canMint(address mToken) external view override {
        if (mintPaused[mToken] == 2) {
            revert Lendtroller__Paused();
        }

        if (!tokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }
    }

    /// @notice Checks if the account should be allowed to redeem tokens
    ///         in the given market
    /// @param mToken The market to verify the redeem against
    /// @param redeemer The account which would redeem the tokens
    /// @param amount The number of mTokens to exchange
    ///               for the underlying asset in the market
    function canRedeem(
        address mToken,
        address redeemer,
        uint256 amount
    ) external view override {
        _canRedeem(mToken, redeemer, amount);
    }

    /// @notice Checks if the account should be allowed to borrow
    ///         the underlying asset of the given market,
    ///         and notifies the market of the borrow
    /// @param mToken The market to verify the borrow against
    /// @param borrower The account which would borrow the asset
    /// @param amount The amount of underlying the account would borrow
    function canBorrowWithNotify(
        address mToken,
        address borrower,
        uint256 amount
    ) external override {
        if (msg.sender != mToken) {
            revert Lendtroller__Unauthorized();
        }

        accountAssets[borrower].cooldownTimestamp = block.timestamp;
        canBorrow(mToken, borrower, amount);
    }

    /// @notice Checks if the account should be allowed to repay a borrow
    ///         in the given market
    /// @param mToken The market to verify the repay against
    /// @param account The account who will have their loan repaid
    function canRepay(address mToken, address account) external view override {
        if (!tokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        // We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        // as well as short term price manipulations if the dynamic dual oracle
        // fails to protect the market somehow
        if (
            accountAssets[account].cooldownTimestamp + _MIN_HOLD_PERIOD >
            block.timestamp
        ) {
            revert Lendtroller__MinimumHoldPeriod();
        }
    }

    /// @notice Checks if the liquidation should be allowed to occur,
    ///         and returns how many collateral tokens should be seized on liquidation
    /// @param debtToken Asset which was borrowed by the borrower
    /// @param collateralToken Asset which was used as collateral and will be seized
    /// @param borrower The address of the borrower
    /// @param amount The amount of `debtToken` underlying being repaid
    /// @return The number of `collateralToken` tokens to be seized in a liquidation
    /// @return The number of `collateralToken` tokens to be seized for the protocol
    function canLiquidateExact(
        address debtToken,
        address collateralToken,
        address borrower,
        uint256 amount
    ) external view override returns (uint256, uint256) {
        (
            uint256 liquidationLimit,
            uint256 debtTokenPrice,
            uint256 collateralTokenPrice
        ) = _canLiquidate(debtToken, collateralToken, borrower);

        if (amount > liquidationLimit) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        return
            _getLiquidatedTokens(
                collateralToken,
                amount,
                debtToken,
                debtTokenPrice,
                collateralTokenPrice
            );
    }

    /// @notice Checks if the liquidation should be allowed to occur,
    ///         and returns how many collateral tokens should be seized on liquidation
    /// @param debtToken Asset which was borrowed by the borrower
    /// @param collateralToken Asset which was used as collateral and will be seized
    /// @param borrower The address of the borrower
    /// @return The amount of `debtToken` underlying to be repaid on liquidation
    /// @return The number of `collateralToken` tokens to be seized in a liquidation
    /// @return The number of `collateralToken` tokens to be seized for the protocol
    function canLiquidate(
        address debtToken,
        address collateralToken,
        address borrower
    ) external view override returns (uint256, uint256, uint256) {
        (
            uint256 amount,
            uint256 debtTokenPrice,
            uint256 collateralTokenPrice
        ) = _canLiquidate(debtToken, collateralToken, borrower);

        (
            uint256 liquidatedTokens,
            uint256 protocolTokens
        ) = _getLiquidatedTokens(
                collateralToken,
                amount,
                debtToken,
                debtTokenPrice,
                collateralTokenPrice
            );

        return (amount, liquidatedTokens, protocolTokens);
    }

    /// @notice Checks if the seizing of assets should be allowed to occur
    /// @param collateralToken Asset which was used as collateral
    ///                        and will be seized
    /// @param debtToken Asset which was borrowed by the borrower
    function canSeize(
        address collateralToken,
        address debtToken
    ) external view override {
        if (seizePaused == 2) {
            revert Lendtroller__Paused();
        }

        if (!tokenData[collateralToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        if (!tokenData[debtToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        if (
            IMToken(collateralToken).lendtroller() !=
            IMToken(debtToken).lendtroller()
        ) {
            revert Lendtroller__LendtrollerMismatch();
        }
    }

    /// @notice Checks if the account should be allowed to transfer tokens
    ///         in the given market
    /// @param mToken The market to verify the transfer against
    /// @param from The account which sources the tokens
    /// @param amount The number of mTokens to transfer
    function canTransfer(
        address mToken,
        address from,
        uint256 amount
    ) external view override {
        if (transferPaused == 2) {
            revert Lendtroller__Paused();
        }

        _canRedeem(mToken, from, amount);
    }

    /// @notice Sets the closeFactor used when liquidating borrows
    /// @dev Admin function to set closeFactor
    /// @param newCloseFactor New close factor in basis points
    function setCloseFactor(
        uint256 newCloseFactor
    ) external onlyElevatedPermissions {
        // Convert parameter from basis points to `WAD`
        newCloseFactor = _bpToWad(newCloseFactor);

        // 100% e.g close entire position
        if (newCloseFactor > WAD) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }
        // Cache the current value for event log and gas savings
        uint256 oldCloseFactor = closeFactor;
        // Assign new closeFactor
        closeFactor = newCloseFactor;

        emit NewCloseFactor(oldCloseFactor, newCloseFactor);
    }

    /// @notice Add the market token to the market and set it as listed
    /// @dev Admin function to set isListed and add support for the market
    /// @param mToken The address of the market (token) to list
    function listToken(address mToken) external onlyElevatedPermissions {
        if (tokenData[mToken].isListed) {
            revert Lendtroller__TokenAlreadyListed();
        }

        IMToken(mToken).isCToken(); // Sanity check to make sure its really a mToken

        MarketToken storage market = tokenData[mToken];
        market.isListed = true;
        market.collRatio = 0;

        uint256 numMarkets = allMarkets.length;

        for (uint256 i; i < numMarkets; ) {
            unchecked {
                if (allMarkets[i++] == IMToken(mToken)) {
                    revert Lendtroller__TokenAlreadyListed();
                }
            }
        }
        allMarkets.push(IMToken(mToken));

        // Start the market if necessary
        if (IMToken(mToken).totalSupply() == 0) {
            if (!IMToken(mToken).startMarket(msg.sender)) {
                revert Lendtroller__InvariantError();
            }
        }

        emit TokenListed(mToken);
    }

    /// @notice Sets the collRatio for a market token
    /// @param mToken The market to set the collateralization ratio on
    /// @param liqInc The liquidation incentive for `mToken`, in basis points
    /// @param liqFee The protocol liquidation fee for `mToken`, in basis points
    /// @param collReqA The premium of excess collateral required to avoid soft liquidation, in basis points
    /// @param collReqB The premium of excess collateral required to avoid hard liquidation, in basis points
    /// @param collRatio The ratio at which $1 of collateral can be borrowed against,
    ///                               for `mToken`, in basis points
    function updateCollateralToken(
        IMToken mToken,
        uint256 liqInc,
        uint256 liqFee,
        uint256 collReqA,
        uint256 collReqB,
        uint256 collRatio
    ) external onlyElevatedPermissions {
        if (!IMToken(mToken).isCToken()) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Verify mToken is listed
        MarketToken storage marketToken = tokenData[address(mToken)];
        if (!marketToken.isListed) {
            revert Lendtroller__TokenNotListed();
        }

        // Convert the parameters from basis points to `WAD` format
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config
        liqInc = _bpToWad(liqInc);
        liqFee = _bpToWad(liqFee);
        collReqA = _bpToWad(collReqA);
        collReqB = _bpToWad(collReqB);
        collRatio = _bpToWad(collRatio);

        // Validate liquidation incentive is not above the maximum allowed
        if (liqInc > _MAX_LIQUIDATION_INCENTIVE) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate protocol liquidation fee is not above the maximum allowed
        if (liqFee > _MAX_LIQUIDATION_FEE) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate collateral requirement is not above the maximum allowed
        if (collReqA > _MAX_COLLATERAL_REQUIREMENT) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate hard liquidation requirement is not above the soft liquidation requirement
        if (collReqB > collReqA) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate collateralization ratio is not above the maximum allowed
        if (collRatio > _MAX_COLLATERALIZATION_RATIO) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate the soft liquidation collateral premium is not more strict than the asset's CR
        if (collRatio > (WAD * WAD) / (WAD + collReqA)) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // Validate collateral requirement is larger than the liquidation incentive
        if (liqInc > collReqB) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // We need to make sure that the liquidation incentive is enough for both the protocol and the users
        if ((liqInc - liqFee) < _MIN_LIQUIDATION_INCENTIVE) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        (, uint256 errorCode) = IPriceRouter(centralRegistry.priceRouter())
            .getPrice(address(mToken), true, true);

        // Validate that we got a price
        if (errorCode == 2) {
            revert Lendtroller__PriceError();
        }

        // We use the value as a premium in `calculateLiquidatedTokens` so it needs to be 1 + incentive
        marketToken.liqInc = WAD + liqInc;

        // Store protocol liquidation fee divided by the liquidation incentive offset,
        // that way we can directly multiply later instead of needing extra calculations
        marketToken.liqFee = (WAD * liqFee) / (WAD + liqInc);

        // Store the collateral requirement as a premium above `WAD`,
        // that way we can calculate solvency via division easily in _getStatusForLiquidation
        marketToken.collReqA = collReqA + WAD;
        marketToken.collReqB = collReqB + WAD;

        // Assign new collateralization ratio
        // Note that a collateralization ratio of 0 corresponds to
        // no collateralization of the mToken
        marketToken.collRatio = collRatio;

        emit CollateralTokenUpdated(
            mToken,
            liqInc,
            liqFee,
            collReqA,
            collReqB,
            collRatio
        );
    }

    /// @notice Set `newCollateralizationCaps` for the given `mTokens`.
    /// @dev    A collateral cap of 0 corresponds to unlimited collateralization.
    /// @param mTokens The addresses of the markets (tokens) to
    ///                change the borrow caps for
    /// @param newCollateralCaps The new collateral cap values in underlying to be set.
    function setCTokenCollateralCaps(
        IMToken[] calldata mTokens,
        uint256[] calldata newCollateralCaps
    ) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert Lendtroller__Unauthorized();
        }

        uint256 numMarkets = mTokens.length;

        assembly {
            if iszero(numMarkets) {
                // store the error selector to location 0x0
                mstore(0x0, _INVALID_PARAMETER_SELECTOR)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }

        if (numMarkets != newCollateralCaps.length) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        for (uint256 i; i < numMarkets; ++i) {
            // Make sure the mToken is a cToken
            if (!mTokens[i].isCToken()) {
                _revert(_INVALID_PARAMETER_SELECTOR);
            }

            collateralCaps[address(mTokens[i])] = newCollateralCaps[i];
            emit NewCollateralCap(mTokens[i], newCollateralCaps[i]);
        }
    }

    /// @notice Returns whether `mToken` is listed in the lending market
    /// @param mToken market token address
    function isListed(address mToken) external view override returns (bool) {
        return (tokenData[mToken].isListed);
    }

    /// @notice Returns market status
    /// @param mToken market token address
    function getTokenData(
        address mToken
    ) external view override returns (bool, uint256, uint256) {
        return (
            tokenData[mToken].isListed,
            tokenData[mToken].liqInc,
            tokenData[mToken].collRatio
        );
    }

    /// @notice Returns if user joined market
    /// @param mToken market token address
    /// @param user user address
    function hasPosition(
        address mToken,
        address user
    ) external view override returns (bool) {
        return tokenData[mToken].accountData[user].activePosition == 2;
    }

    /// @notice Admin function to set market mint paused
    /// @dev requires timelock authority if unpausing
    /// @param mToken market token address
    /// @param state pause or unpause
    function setMintPaused(
        IMToken mToken,
        bool state
    ) external onlyAuthorizedPermissions(state) {
        if (!tokenData[address(mToken)].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        mintPaused[address(mToken)] = state ? 2 : 1;
        emit TokenActionPaused(mToken, "Mint Paused", state);
    }

    /// @notice Admin function to set market borrow paused
    /// @dev requires timelock authority if unpausing
    /// @param mToken market token address
    /// @param state pause or unpause
    function setBorrowPaused(
        IMToken mToken,
        bool state
    ) external onlyAuthorizedPermissions(state) {
        if (!tokenData[address(mToken)].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        borrowPaused[address(mToken)] = state ? 2 : 1;
        emit TokenActionPaused(mToken, "Borrow Paused", state);
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
            _revert(_INVALID_PARAMETER_SELECTOR);
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

    /// @notice Updates `borrower` cooldownTimestamp to the current block timestamp
    /// @dev The caller must be a listed MToken in the `markets` mapping
    /// @param borrower The address of the account that has just borrowed
    function notifyBorrow(address borrower) external override {
        if (!tokenData[msg.sender].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        accountAssets[borrower].cooldownTimestamp = block.timestamp;
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Checks if the account should be allowed to borrow
    ///         the underlying asset of the given market
    /// @param mToken The market to verify the borrow against
    /// @param borrower The account which would borrow the asset
    /// @param amount The amount of underlying the account would borrow
    function canBorrow(
        address mToken,
        address borrower,
        uint256 amount
    ) public override {
        if (borrowPaused[mToken] == 2) {
            revert Lendtroller__Paused();
        }

        if (!tokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        if (tokenData[mToken].accountData[borrower].activePosition < 2) {
            // only mTokens may call borrowAllowed if borrower not in market
            if (msg.sender != mToken) {
                revert Lendtroller__Unauthorized();
            }

            // The user is not in the market yet, so make them enter
            tokenData[mToken].accountData[borrower].activePosition = 2;
            accountAssets[borrower].assets.push(IMToken(mToken));

            emit TokenPositionCreated(mToken, borrower);
        }

        // We call hypothetical account liquidity as normal but with
        // heavier error code restriction on borrow
        (, uint256 shortfall) = _getHypotheticalLiquidity(
            borrower,
            IMToken(mToken),
            0,
            amount,
            1
        );

        if (shortfall > 0) {
            revert Lendtroller__InsufficientLiquidity();
        }
    }

    /// Liquidity/Liquidation Calculations

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity
    /// @param account The account to determine liquidity for
    /// @return sumCollateral total collateral amount of user
    /// @return maxBorrow max borrow amount of user
    /// @return currentDebt total borrow amount of user
    function getStatus(
        address account
    )
        public
        view
        returns (uint256 sumCollateral, uint256 maxBorrow, uint256 currentDebt)
    {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _getAssetData(account, 2);
        AccountSnapshot memory snapshot;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a CR increment their collateral and max borrow value
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    uint256 assetValue = _getAssetValue(
                        (snapshot.balance * snapshot.exchangeRate) / WAD,
                        underlyingPrices[i],
                        snapshot.decimals
                    );

                    sumCollateral += assetValue;
                    maxBorrow +=
                        (assetValue * tokenData[snapshot.asset].collRatio) /
                        WAD;
                }
            } else {
                // If they have a debt balance we need to document it
                if (snapshot.debtBalance > 0) {
                    currentDebt += _getAssetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Determine whether `account` can currently be liquidated in this market
    /// @param account The account to check for liquidation flag
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return Whether `account` can be liquidated currently
    function flaggedForLiquidation(
        address account
    ) internal view returns (bool) {
        (uint256 shortfall, , ) = _getStatusForLiquidation(
            account,
            address(0),
            address(0)
        );
        return shortfall > 0;
    }

    /// @notice Determine what the account liquidity would be if
    ///         the given amounts were redeemed/borrowed
    /// @param mTokenModify The market to hypothetically redeem/borrow in
    /// @param account The account to determine liquidity for
    /// @param redeemTokens The number of tokens to hypothetically redeem
    /// @param borrowAmount The amount of underlying to hypothetically borrow
    /// @return uint256 hypothetical account liquidity in excess
    ///              of collateral requirements,
    /// @return uint256 hypothetical account shortfall below collateral requirements)
    function getHypotheticalLiquidity(
        address account,
        address mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) public view returns (uint256, uint256) {
        return
            _getHypotheticalLiquidity(
                account,
                IMToken(mTokenModify),
                redeemTokens,
                borrowAmount,
                2
            );
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

    /// @notice Checks if the account should be allowed to redeem tokens
    ///         in the given market
    /// @param mToken The market to verify the redeem against
    /// @param redeemer The account which would redeem the tokens
    /// @param amount The number of `mToken` to redeem for
    ///               the underlying asset in the market
    function _canRedeem(
        address mToken,
        address redeemer,
        uint256 amount
    ) internal view {
        if (!tokenData[mToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        // We require a `minimumHoldPeriod` to break flashloan manipulations attempts
        // as well as short term price manipulations if the dynamic dual oracle
        // fails to protect the market somehow
        if (
            accountAssets[redeemer].cooldownTimestamp + _MIN_HOLD_PERIOD >
            block.timestamp
        ) {
            revert Lendtroller__MinimumHoldPeriod();
        }

        // If the redeemer does not have an active position in the token, 
        // then we can bypass the liquidity check
        if (tokenData[mToken].accountData[redeemer].activePosition < 2) {
            return;
        }

        // Otherwise, perform a hypothetical liquidity check to guard against
        // shortfall
        (, uint256 shortfall) = _getHypotheticalLiquidity(
            redeemer,
            IMToken(mToken),
            amount,
            0,
            2
        );

        if (shortfall > 0) {
            revert Lendtroller__InsufficientLiquidity();
        }
    }

    /// @notice Checks if the liquidation should be allowed to occur
    /// @param debtToken Asset which was borrowed by the borrower
    /// @param collateralToken Asset which was used as collateral and will be seized
    /// @param borrower The address of the borrower
    /// @return The maximum amount of `debtToken` that can be repaid during liquidation
    /// @return Current price for `debtToken`
    /// @return Current price for `collateralToken`
    function _canLiquidate(
        address debtToken,
        address collateralToken,
        address borrower
    ) internal view returns (uint256, uint256, uint256) {
        if (!tokenData[debtToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        if (!tokenData[collateralToken].isListed) {
            revert Lendtroller__TokenNotListed();
        }

        // Do not let people liquidate 0 collateralization ratio assets
        if (tokenData[collateralToken].collRatio == 0) {
            _revert(_INVALID_PARAMETER_SELECTOR);
        }

        // The borrower must have shortfall CURRENTLY in order to be liquidatable
        (
            uint256 shortfall,
            uint256 debtTokenPrice,
            uint256 collateralTokenPrice
        ) = _getStatusForLiquidation(borrower, debtToken, collateralToken);

        assembly {
            if iszero(shortfall) {
                // store the error selector to location 0x0
                mstore(0x0, _INSUFFICIENT_SHORTFALL_SELECTOR)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }
        uint256 maxLiquidationAmount = (closeFactor *
            IMToken(debtToken).debtBalanceStored(borrower)) / WAD;

        // Calculate the maximum amount of collateral that can be liquidated
        return (maxLiquidationAmount, debtTokenPrice, collateralTokenPrice);
    }

    /// @notice Calculate number of `collateralToken` to
    ///         seize given an underlying amount
    /// @param collateralToken The address of the collateral mToken
    /// @param amount The amount of debtToken underlying to repay
    /// @param debtToken The address of the debt token
    /// @param debtTokenPrice Current price for the debtToken
    /// @param collateralTokenPrice Current price for `collateralToken`
    /// @return uint256 The number of `collateralToken` tokens to be seized in a liquidation
    /// @return uint256 The number of `collateralToken` tokens to be seized for the protocol
    function _getLiquidatedTokens(
        address collateralToken,
        uint256 amount,
        address debtToken,
        uint256 debtTokenPrice,
        uint256 collateralTokenPrice
    ) internal view returns (uint256, uint256) {
        MarketToken storage mToken = tokenData[collateralToken];

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        uint256 debtToCollateralRatio = (mToken.liqInc *
            debtTokenPrice *
            WAD) /
            (collateralTokenPrice *
                IMToken(collateralToken).exchangeRateStored());

        uint256 amountAdjusted = (amount *
            (10 ** IERC20(collateralToken).decimals())) /
            (10 ** IERC20(debtToken).decimals());
        uint256 liquidatedTokens = (amountAdjusted * debtToCollateralRatio) /
            WAD;

        return (
            liquidatedTokens,
            (liquidatedTokens * mToken.liqFee) / WAD
        );
    }

    /// @notice Determine what the account status if an action were done (redeem/borrow)
    /// @param account The account to determine hypothetical status for
    /// @param mTokenModify The market to hypothetically redeem/borrow in
    /// @param redeemTokens The number of tokens to hypothetically redeem
    /// @param borrowAmount The amount of underlying to hypothetically borrow
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return sumCollateral The total market value of `account`'s collateral
    /// @return maxBorrow Maximum amount `account` can borrow versus current collateral
    /// @return newDebt The new debt of `account` after the hypothetical action
    function _getHypotheticalStatus(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount,
        uint256 errorCodeBreakpoint
    )
        internal
        view
        returns (uint256 sumCollateral, uint256 maxBorrow, uint256 newDebt)
    {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _getAssetData(account, errorCodeBreakpoint);
        AccountSnapshot memory snapshot;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a CR increment their collateral and max borrow value
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    uint256 assetValue = _getAssetValue(
                        (snapshot.balance * snapshot.exchangeRate) / WAD,
                        underlyingPrices[i],
                        snapshot.decimals
                    );

                    sumCollateral += assetValue;
                    maxBorrow +=
                        (assetValue * tokenData[snapshot.asset].collRatio) /
                        WAD;
                }
            } else {
                // If they have a borrow balance we need to document it
                if (snapshot.debtBalance > 0) {
                    newDebt += _getAssetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }

            // Calculate effects of interacting with mTokenModify
            if (IMToken(snapshot.asset) == mTokenModify) {
                // If its a CToken our only option is to redeem it since it cant be borrowed
                // If its a DToken we can redeem it but it will not have any effect on borrow amount
                // since DToken have a collateral value of 0
                if (snapshot.isCToken) {
                    if (!(tokenData[snapshot.asset].collRatio == 0)) {
                        uint256 collateralValue = _getAssetValue(
                            (redeemTokens * snapshot.exchangeRate) / WAD,
                            underlyingPrices[i],
                            snapshot.decimals
                        );

                        // hypothetical redemption
                        newDebt += ((collateralValue *
                            tokenData[snapshot.asset].collRatio) / WAD);
                    }
                } else {
                    // hypothetical borrow
                    newDebt += _getAssetValue(
                        borrowAmount,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Determine what `account`'s liquidity would be if
    ///         `mTokenModify` were redeemed or borrowed.
    /// @param account The account to determine liquidity for.
    /// @param mTokenModify The mToken to hypothetically redeem/borrow.
    /// @param redeemTokens The number of tokens to hypothetically redeem.
    /// @param borrowAmount The amount of underlying to hypothetically borrow.
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert.
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return uint256 Hypothetical `account` excess liquidity versus collateral requirements.
    /// @return uint256 Hypothetical `account` shortfall below collateral requirements.
    function _getHypotheticalLiquidity(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount,
        uint256 errorCodeBreakpoint
    ) internal view returns (uint256, uint256) {
        (, uint256 maxBorrow, uint256 newDebt) = _getHypotheticalStatus(
            account,
            mTokenModify,
            redeemTokens,
            borrowAmount,
            errorCodeBreakpoint
        );

        // These will not underflow/overflow as condition is checked prior
        if (maxBorrow > newDebt) {
            unchecked {
                return (maxBorrow - newDebt, 0);
            }
        }

        unchecked {
            return (0, newDebt - maxBorrow);
        }
    }

    /// @notice Determine what the account liquidity would be if
    ///         the given amounts were redeemed/borrowed
    /// @dev Note that we calculate the exchangeRateStored for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @param account The account to determine liquidity for
    /// @param debtToken The dToken to be repaid during liquidation
    /// @param collateralToken The cToken to be seized during liquidation
    /// @return Current shortfall versus liquidation threshold
    /// @return Current price for `debtToken`
    /// @return Current price for `collateralToken`
    function _getStatusForLiquidation(
        address account,
        address debtToken,
        address collateralToken
    ) internal view returns (uint256, uint256, uint256) {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _getAssetData(account, 2);
        AccountSnapshot memory snapshot;
        uint256 totalCollateral;
        uint256 totalDebt;
        uint256 debtTokenPrice;
        uint256 collateralTokenPrice;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                if (snapshot.asset == collateralToken) {
                    collateralTokenPrice = underlyingPrices[i];
                }

                // If the asset has a CR increment their collateral
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    totalCollateral +=
                        (_getAssetValue(
                            (snapshot.balance * snapshot.exchangeRate) /
                                WAD,
                            underlyingPrices[i],
                            snapshot.decimals
                        ) * WAD) /
                        tokenData[snapshot.asset].collReqA;
                }
            } else {
                if (snapshot.asset == debtToken) {
                    debtTokenPrice = underlyingPrices[i];
                }

                // If they have a debt balance,
                // we need to document collateral requirements
                if (snapshot.debtBalance > 0) {
                    totalDebt += _getAssetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }

            unchecked {
                ++i;
            }
        }

        if (totalCollateral >= totalDebt) {
            return (0, debtTokenPrice, collateralTokenPrice);
        }

        unchecked {
            return (
                totalDebt - totalCollateral,
                debtTokenPrice,
                collateralTokenPrice
            );
        }
    }

    /// @notice Retrieves the prices and account data of multiple assets inside this market.
    /// @param account The account to retrieve data for.
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert.
    /// @return AccountSnapshot[] Contains `assets` data for `account`
    /// @return uint256[] Contains prices for `assets`.
    /// @return uint256 The number of assets `account` is in.
    function _getAssetData(
        address account,
        uint256 errorCodeBreakpoint
    )
        internal
        view
        returns (AccountSnapshot[] memory, uint256[] memory, uint256)
    {
        return
            IPriceRouter(centralRegistry.priceRouter()).getPricesForMarket(
                account,
                accountAssets[account].assets,
                errorCodeBreakpoint
            );
    }

    function _getAssetValue(
        uint256 amount,
        uint256 price,
        uint256 decimals
    ) internal pure returns (uint256) {
        return (amount * price) / (10 ** decimals);
    }

    /// @dev Internal helper function for easily converting between scalars
    function _bpToWad(uint256 value) internal pure returns (uint256 result) {
        assembly {
            result := mul(value, 100000000000000)
        }
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
