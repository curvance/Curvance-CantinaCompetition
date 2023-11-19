// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";

/// @title Curvance Liquidity Manager
/// @notice Calculates liquidity of an account in various positions
/// @dev NOTE: Only use this as an abstract contract as no account data is written here
abstract contract LiquidityManager {
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
        /// @notice The base ratio at which this token will be compensated on soft liquidation.
        /// @dev    In `WAD` format, stored as (Incentive + WAD)
        ///         e.g 1.05e18 = 5% incentive, this saves gas for liquidation calculations
        uint256 liqBaseIncentive;
        /// @notice The liquidation incentive curve length between soft liquidation to hard liquidation.
        ///         e.g. 5% base incentive with 8% curve length results in 13% liquidation incentive
        ///         on hard liquidation.
        /// @dev    In `WAD` format.
        ///         e.g 05e18 = 5% maximum additional incentive
        uint256 liqCurve;
        /// @notice The protocol fee that will be taken on liquidation for this token.
        /// @dev    In `WAD` format, 0.01e18 = 1%
        ///         Note: this is stored as (Fee * WAD) / `liqIncA`
        ///         in order to save gas for liquidation calculations
        uint256 liqFee;
        /// @notice Maximum % that a liquidator can repay when soft liquidating an account,
        /// @dev    In `WAD` format.
        uint256 baseCFactor;
        /// @notice cFactor curve length between soft liquidation and hard liquidation,
        /// @dev    In `WAD` format.
        uint256 cFactorCurve;
        /// @notice Mapping that stores account information like token positions and collateral posted.
        mapping(address => AccountMetadata) accountData;
    }

    struct LiqData {
        uint256 lFactor;
        uint256 debtTokenPrice;
        uint256 collateralTokenPrice;
    }

    /// STORAGE ///

    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// @notice Market Token => isListed, Token Characteristics, Account Data.
    mapping(address => MarketToken) public tokenData;
    /// @notice Account => Assets, cooldownTimestamp.
    mapping(address => AccountData) public accountAssets;

    /// ERRORS ///

    error LiquidityManager__InvalidParameter();

    constructor(ICentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            // bytes4(keccak256(bytes("LiquidityManager__InvalidParameter()")))
            _revert(0x78eefdcc);
        }

        centralRegistry = centralRegistry_;
    }

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity
    /// @param account The account to determine liquidity for
    /// @return accountCollateral Total value of `account` collateral
    /// @return maxDebt The maximum amount of debt `account` 
    ///                 could take on based on `accountCollateral`
    /// @return accountDebt Total value of `account` debt
    function _statusOf(
        address account
    )
        internal
        view
        returns (
            uint256 accountCollateral,
            uint256 maxDebt,
            uint256 accountDebt
        )
    {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, 2);
        AccountSnapshot memory snapshot;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a CR increment their collateral and max borrow value
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    (accountCollateral, maxDebt) = _addCollateralValues(
                        snapshot,
                        account,
                        underlyingPrices[i],
                        accountCollateral,
                        maxDebt
                    );
                }
            } else {
                // If they have a debt balance, increment their debt
                if (snapshot.debtBalance > 0) {
                    accountDebt += _getAssetValue(
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

    /// @notice Determine what the account status if an action were done (redeem/borrow)
    /// @param account The account to determine hypothetical status for
    /// @param mTokenModified The market to hypothetically redeem/borrow in
    /// @param redeemTokens The number of tokens to hypothetically redeem
    /// @param borrowAmount The amount of underlying to hypothetically borrow
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert
    /// @dev Note that we calculate the exchangeRateCached for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return accountCollateral The total market value of `account`'s collateral
    /// @return maxDebt Maximum amount `account` can borrow versus current collateral
    /// @return newDebt The new debt of `account` after the hypothetical action
    function _hypotheticalStatusOf(
        address account,
        IMToken mTokenModified,
        uint256 redeemTokens, // in shares
        uint256 borrowAmount, // in assets
        uint256 errorCodeBreakpoint
    )
        internal
        view
        returns (uint256 accountCollateral, uint256 maxDebt, uint256 newDebt)
    {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, errorCodeBreakpoint);
        AccountSnapshot memory snapshot;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a Collateral Ratio,
                // increment their collateral and max borrow value
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    (accountCollateral, maxDebt) = _addCollateralValues(
                        snapshot,
                        account,
                        underlyingPrices[i],
                        accountCollateral,
                        maxDebt
                    );
                }
            } else {
                // If they have a debt balance, increment their debt
                if (snapshot.debtBalance > 0) {
                    newDebt += _getAssetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }

            // Calculate effects of interacting with mTokenModified
            if (IMToken(snapshot.asset) == mTokenModified) {
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
    ///         `mTokenModified` were redeemed or borrowed.
    /// @param account The account to determine liquidity for.
    /// @param mTokenModified The mToken to hypothetically redeem/borrow.
    /// @param redeemTokens The number of tokens to hypothetically redeem.
    /// @param borrowAmount The amount of underlying to hypothetically borrow.
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert.
    /// @dev Note that we calculate the exchangeRateCached for each collateral
    ///           mToken using stored data, without calculating accumulated interest.
    /// @return uint256 Hypothetical `account` excess liquidity versus collateral requirements.
    /// @return uint256 Hypothetical `account` liquidity deficit below collateral requirements.
    function _hypotheticalLiquidityOf(
        address account,
        IMToken mTokenModified,
        uint256 redeemTokens, // in shares
        uint256 borrowAmount, // in assets
        uint256 errorCodeBreakpoint
    ) internal view returns (uint256, uint256) {
        (, uint256 maxDebt, uint256 newDebt) = _hypotheticalStatusOf(
            account,
            mTokenModified,
            redeemTokens,
            borrowAmount,
            errorCodeBreakpoint
        );

        // These will not underflow/overflow as condition is checked prior
        if (maxDebt > newDebt) {
            unchecked {
                return (maxDebt - newDebt, 0);
            }
        }

        unchecked {
            return (0, newDebt - maxDebt);
        }
    }

    /// @notice Determine `account`'s current collateral and debt values in the market
    /// @param account The account to check bad debt status for
    /// @return accountCollateral The total market value of `account`'s collateral
    /// @return accountDebt The total outstanding debt value of `account`
    function _solvencyOf(
        address account
    ) internal view returns (uint256 accountCollateral, uint256 accountDebt) {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, 2);
        AccountSnapshot memory snapshot;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a CR increment their collateral
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    accountCollateral += _getAssetValue(
                                         ((tokenData[snapshot.asset].accountData[account].collateralPosted *
                                            snapshot.exchangeRate) / WAD),
                                            underlyingPrices[i],
                                            snapshot.decimals
                                         );

                }
            } else {
                // If they have a debt balance, increment their debt
                if (snapshot.debtBalance > 0) {
                    accountDebt += _getAssetValue(
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

    /// @notice Determine whether `account` can be liquidated,
    ///         by calculating their lFactor, based on their
    ///         collateral versus outstanding debt
    /// @param account The account to check liquidation status for
    /// @param debtToken The dToken to be repaid during potential liquidation
    /// @param collateralToken The cToken to be seized during potential liquidation
    /// @return result Containing values:
    ///                Current `account` lFactor
    ///                Current price for `debtToken`
    ///                Current price for `collateralToken`
    function _LiquidationStatusOf(
        address account,
        address debtToken,
        address collateralToken
    ) internal view returns (LiqData memory result) {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, 2);
        AccountSnapshot memory snapshot;
        // Collateral value for soft liquidation level
        uint256 accountCollateralA;
        // Collateral value for hard liquidation level
        uint256 accountCollateralB;
        // Current outstanding account debt
        uint256 accountDebt;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                if (snapshot.asset == collateralToken) {
                    result.collateralTokenPrice = underlyingPrices[i];
                }

                // If the asset has a CR increment their collateral
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    (
                        accountCollateralA,
                        accountCollateralB
                    ) = _addLiquidationValues(
                        snapshot,
                        account,
                        underlyingPrices[i],
                        accountCollateralA,
                        accountCollateralB
                    );
                }
            } else {
                if (snapshot.asset == debtToken) {
                    result.debtTokenPrice = underlyingPrices[i];
                }

                // If they have a debt balance,
                // we need to document collateral requirements
                if (snapshot.debtBalance > 0) {
                    accountDebt += _getAssetValue(
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

        if (accountCollateralA >= accountDebt) {
            return result;
        }

        result.lFactor = _getPositiveCurveResult(
            accountDebt,
            accountCollateralA,
            accountCollateralB
        );
    } 

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity
    /// @param account The account to determine liquidity for
    /// @return accountCollateral Total value of `account` collateral
    /// @return accountDebtToPay The amount of debt to repay to receive `accountCollateral`
    /// @return accountDebt Total value of `account` debt
    function _BadDebtTermsOf(
        address account
    )
        internal
        view
        returns (
            uint256 accountCollateral,
            uint256 accountDebtToPay,
            uint256 accountDebt
        )
    {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, 2);
        AccountSnapshot memory snapshot;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a CR increment their collateral and debt to pay
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    (accountCollateral, accountDebtToPay) = _addValuesForBadDebt(
                        snapshot,
                        account,
                        underlyingPrices[i],
                        accountCollateral,
                        accountDebtToPay
                    );
                }
            } else {
                // If they have a debt balance, increment their debt
                if (snapshot.debtBalance > 0) {
                    accountDebt += _getAssetValue(
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

    /// @notice Retrieves the prices and account data of multiple assets inside this market.
    /// @param account The account to retrieve data for.
    /// @param errorCodeBreakpoint The error code that will cause liquidity operations to revert.
    /// @return AccountSnapshot[] Contains assets data for `account`.
    /// @return uint256[] Contains prices for `account` assets.
    /// @return uint256 The number of assets `account` is in.
    function _assetDataOf(
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

    function _addLiquidationValues(
        AccountSnapshot memory snapshot,
        address account,
        uint256 price,
        uint256 softLiquidationSumPrior,
        uint256 hardLiquidationSumPrior
    ) internal view returns (uint256, uint256) {
        uint256 assetValue = _getAssetValue(
            ((tokenData[snapshot.asset].accountData[account].collateralPosted *
                snapshot.exchangeRate) / WAD),
            price,
            snapshot.decimals
        ) * WAD;

        return (
            softLiquidationSumPrior +
                (assetValue / tokenData[snapshot.asset].collReqA),
            hardLiquidationSumPrior +
                (assetValue / tokenData[snapshot.asset].collReqB)
        );
    }

    function _addCollateralValues(
        AccountSnapshot memory snapshot,
        address account,
        uint256 price,
        uint256 previousCollateral,
        uint256 previousBorrow
    ) internal view returns (uint256, uint256) {
        uint256 assetValue = _getAssetValue(
            ((tokenData[snapshot.asset].accountData[account].collateralPosted *
                snapshot.exchangeRate) / WAD),
            price,
            snapshot.decimals
        );
        return (
            previousCollateral + assetValue,
            previousBorrow +
                (assetValue * tokenData[snapshot.asset].collRatio) /
                WAD
        );
    }

    function _addValuesForBadDebt(
        AccountSnapshot memory snapshot,
        address account,
        uint256 price,
        uint256 previousCollateral,
        uint256 previousDebtToPay
    ) internal view returns (uint256, uint256) {
        uint256 assetValue = _getAssetValue(
            ((tokenData[snapshot.asset].accountData[account].collateralPosted *
                snapshot.exchangeRate) / WAD),
            price,
            snapshot.decimals
        );
        return (
            previousCollateral + assetValue,
            previousDebtToPay +
                (assetValue * WAD) /
                tokenData[snapshot.asset].liqBaseIncentive
        );
    } 

    /// @notice Calculates a positive curve value based on `current`,
    ///         `start`, and `end` values.
    /// @dev The function scales current, start, and end values by `WAD`
    ///      to maintain precision. It returns 1, (in `WAD`) if the
    ///      current value is greater than or equal to `end`. The formula
    ///      used is (current - start) / (end - start), ensuring the result
    ///      is scaled properly.
    /// @param current The current value, representing a point on the curve.
    /// @param start The start value of the curve, marking the beginning of
    ///              the calculation range.
    /// @param end The end value of the curve, marking the end of the
    ///            calculation range.
    /// @return The calculated positive curve value, a proportion between
    ///         the start and end points.
    function _getPositiveCurveResult(
        uint256 current,
        uint256 start,
        uint256 end
    ) internal pure returns (uint256) {
        if (current >= end) {
            return WAD;
        }
        return ((current - start) * WAD) / (end - start);
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