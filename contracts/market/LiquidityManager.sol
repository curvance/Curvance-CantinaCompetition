// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";

/// @title Curvance Liquidity Manager.
/// @notice Calculates liquidity of an account in various positions.
/// @dev NOTE: Only use this as an abstract contract as no account
///            data is written here.
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
        /// @notice Value that indicates whether an account has an active
        ///         position in the token.
        /// @dev    0 or 1 for no; 2 for yes.
        uint256 activePosition;
        /// @notice The amount of collateral an account has posted.
        /// @dev    Only relevant for cTokens not dTokens.
        uint256 collateralPosted;
    }

    struct MarketToken {
        /// @notice Whether or not this market token is listed.
        /// @dev    false = unlisted; true = listed.
        bool isListed;
        /// @notice The ratio at which this token can be collateralized.
        /// @dev    in `WAD` format, with 0.8e18 = 80% collateral value.
        uint256 collRatio;
        /// @notice The collateral requirement where dipping below this will 
        ///         cause a soft liquidation.
        /// @dev    in `WAD` format, with 1.2e18 = 120% collateral vs debt value.
        uint256 collReqSoft;
        /// @notice The collateral requirement where dipping below this will 
        ///         cause a hard liquidation.
        /// @dev    in `WAD` format, with 1.2e18 = 120% collateral vs debt value.
        ///         NOTE: Should ALWAYS be less than `collReqSoft`.
        uint256 collReqHard;
        /// @notice The base ratio at which this token will be compensated on
        ///         soft liquidation.
        /// @dev    In `WAD` format, stored as (Incentive + WAD)
        ///         e.g 1.05e18 = 5% incentive, this saves gas for liquidation
        ///         calculations.
        uint256 liqBaseIncentive;
        /// @notice The liquidation incentive curve length between 
        ///         soft liquidation to hard liquidation.
        ///         e.g. 5% base incentive with 8% curve length results 
        ///         in 13% liquidation incentive on hard liquidation.
        /// @dev    In `WAD` format.
        ///         e.g 05e18 = 5% maximum additional incentive.
        uint256 liqCurve;
        /// @notice The protocol fee that will be taken on liquidation for this token.
        /// @dev    In `WAD` format, 0.01e18 = 1%.
        ///         Note: this is stored as (Fee * WAD) / `liqIncA`
        ///         in order to save gas for liquidation calculations.
        uint256 liqFee;
        /// @notice Maximum % that a liquidator can repay when
        ///         soft liquidating an account.
        /// @dev    In `WAD` format.
        uint256 baseCFactor;
        /// @notice cFactor curve length between soft liquidation
        ///         and hard liquidation.
        /// @dev    In `WAD` format.
        uint256 cFactorCurve;
        /// @notice Mapping that stores account information like token
        ///         positions and collateral posted.
        mapping(address => AccountMetadata) accountData;
    }

    struct LiqData {
        uint256 lFactor;
        uint256 debtTokenPrice;
        uint256 collateralTokenPrice;
    }

    /// STORAGE ///

    /// @notice Curvance DAO hub.
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
            // bytes4(keccak256(bytes("LiquidityManager__InvalidParameter()"))).
            _revert(0x78eefdcc);
        }

        centralRegistry = centralRegistry_;
    }

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity.
    /// @param account The account to determine liquidity for.
    /// @return accountCollateral Total value of `account` collateral.
    /// @return maxDebt The maximum amount of debt `account`
    ///                 could take on based on `accountCollateral`.
    /// @return accountDebt Total value of `account` debt.
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
                // If the asset has a CR increment their collateral
                // and max borrow value.
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    uint256 collateralValue = _getAssetValue(
                        ((tokenData[snapshot.asset]
                            .accountData[account]
                            .collateralPosted * snapshot.exchangeRate) / WAD),
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                    accountCollateral += collateralValue;
                    maxDebt =
                        (collateralValue *
                            tokenData[snapshot.asset].collRatio) /
                        WAD;
                }
            } else {
                // If they have a debt balance, increment their debt.
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

    /// @notice Determine what `account`'s liquidity would be if
    ///         `mTokenModified` were redeemed or borrowed.
    /// @param account The account to determine liquidity for.
    /// @param mTokenModified The mToken to hypothetically redeem/borrow.
    /// @param redeemTokens The number of tokens to hypothetically redeem.
    /// @param borrowAmount The amount of underlying to hypothetically borrow.
    /// @param errorCodeBreakpoint The error code that will cause liquidity
    ///                            operations to revert.
    /// @dev Note that we calculate the exchangeRateCached for each collateral
    ///           mToken using stored data, without calculating accumulated
    ///           interest.
    /// @return uint256 Hypothetical `account` excess liquidity versus
    ///         collateral requirements.
    /// @return uint256 Hypothetical `account` liquidity deficit below
    ///         collateral requirements.
    function _hypotheticalLiquidityOf(
        address account,
        address mTokenModified,
        uint256 redeemTokens, // in shares
        uint256 borrowAmount, // in assets
        uint256 errorCodeBreakpoint
    ) internal view returns (uint256, uint256) {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, errorCodeBreakpoint);
        AccountSnapshot memory snapshot;
        uint256 maxDebt;
        uint256 newDebt;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a Collateral Ratio,
                // increment their collateral and max borrow value.
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    maxDebt = _getLiquidityValue(
                        snapshot,
                        account,
                        underlyingPrices[i],
                        maxDebt
                    );
                }
            } else {
                // If they have a debt balance, increment their debt.
                if (snapshot.debtBalance > 0) {
                    newDebt += _getAssetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }

            // Calculate effects of interacting with mTokenModified.
            if (snapshot.asset == mTokenModified) {
                // If its a CToken our only option is to redeem it since
                // it cant be borrowed.
                // If its a DToken we can redeem it but it will not have
                // any effect on borrow amount since DToken have a collateral
                // value of 0.
                if (snapshot.isCToken) {
                    if (!(tokenData[snapshot.asset].collRatio == 0)) {
                        uint256 collateralValue = _getAssetValue(
                            (redeemTokens * snapshot.exchangeRate) / WAD,
                            underlyingPrices[i],
                            snapshot.decimals
                        );

                        // hypothetical redemption.
                        newDebt += ((collateralValue *
                            tokenData[snapshot.asset].collRatio) / WAD);
                    }
                } else {
                    // hypothetical borrow.
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

        // These will not underflow/overflow as condition is checked prior.
        if (maxDebt > newDebt) {
            unchecked {
                return (maxDebt - newDebt, 0);
            }
        }

        unchecked {
            return (0, newDebt - maxDebt);
        }
    }

    /// @notice Determine `account`'s current collateral and debt values
    ///        in the market.
    /// @param account The account to check bad debt status for.
    /// @return accountCollateral The total market value of
    ///                           `account`'s collateral.
    /// @return accountDebt The total outstanding debt value of `account`.
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
                // If the asset has a CR increment their collateral.
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    accountCollateral += _getAssetValue(
                        ((tokenData[snapshot.asset]
                            .accountData[account]
                            .collateralPosted * snapshot.exchangeRate) / WAD),
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            } else {
                // If they have a debt balance, increment their debt.
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
    ///         collateral versus outstanding debt.
    /// @param account The account to check liquidation status for.
    /// @param debtToken The dToken to be repaid during potential liquidation.
    /// @param collateralToken The cToken to be seized during potential
    ///                        liquidation.
    /// @return result Containing values:
    ///                Current `account` lFactor.
    ///                Current price for `debtToken`.
    ///                Current price for `collateralToken`.
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
        // Collateral value for soft liquidation level.
        uint256 accountCollateralSoft;
        // Collateral value for hard liquidation level.
        uint256 accountCollateralHard;
        // Current outstanding account debt.
        uint256 accountDebt;

        for (uint256 i; i < numAssets; ) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                if (snapshot.asset == collateralToken) {
                    result.collateralTokenPrice = underlyingPrices[i];
                }

                // If the asset has a CR increment their collateral.
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    (
                        accountCollateralSoft,
                        accountCollateralHard
                    ) = _addLiquidationValues(
                        snapshot,
                        account,
                        underlyingPrices[i],
                        accountCollateralSoft,
                        accountCollateralHard
                    );
                }
            } else {
                if (snapshot.asset == debtToken) {
                    result.debtTokenPrice = underlyingPrices[i];
                }

                // If they have a debt balance,
                // we need to document collateral requirements.
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

        if (accountCollateralSoft >= accountDebt) {
            return result;
        }

        if (accountDebt >= accountCollateralHard) {
            result.lFactor = WAD;
        } else {
            result.lFactor =
                ((accountDebt - accountCollateralSoft) * WAD) /
                (accountCollateralHard - accountCollateralSoft);
            
            // Its theoretically possible for lFactor calculation to round
            // down here, if the delta between the hard and soft collateral
            // thresholds are significant (> WAD), with a minimal numerator
            // (~ WAD). For this case we round up on the side of the protocol.
            if (result.lFactor == 0) {
                // Round to 1 wei to trigger a soft liquidation.
                result.lFactor = 1;
            }
        }
    }

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity.
    /// @param account The account to determine liquidity for.
    /// @return accountCollateral Total value of `account` collateral.
    /// @return accountDebtToPay The amount of debt to repay to receive `accountCollateral`.
    /// @return accountDebt Total value of `account` debt.
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
                // If the asset has a CR increment their collateral and debt to pay.
                if (!(tokenData[snapshot.asset].collRatio == 0)) {
                    uint256 collateralValue = _getAssetValue(
                        ((tokenData[snapshot.asset]
                            .accountData[account]
                            .collateralPosted * snapshot.exchangeRate) / WAD),
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                    accountCollateral += collateralValue;
                    accountDebtToPay +=
                        (collateralValue * WAD) /
                        tokenData[snapshot.asset].liqBaseIncentive;
                }
            } else {
                // If they have a debt balance, increment their debt.
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
            IOracleRouter(centralRegistry.oracleRouter()).getPricesForMarket(
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
        uint256 softSumPrior,
        uint256 hardSumPrior
    ) internal view returns (uint256, uint256) {
        uint256 assetValue = _getAssetValue(
            ((tokenData[snapshot.asset].accountData[account].collateralPosted *
                snapshot.exchangeRate) / WAD),
            price,
            snapshot.decimals
        ) * WAD;

        return (
            softSumPrior + (assetValue / tokenData[snapshot.asset].collReqSoft),
            hardSumPrior + (assetValue / tokenData[snapshot.asset].collReqHard)
        );
    }

    function _getLiquidityValue(
        AccountSnapshot memory snapshot,
        address account,
        uint256 price,
        uint256 previousBorrow
    ) internal view returns (uint256) {
        uint256 assetValue = _getAssetValue(
            ((tokenData[snapshot.asset].accountData[account].collateralPosted *
                snapshot.exchangeRate) / WAD),
            price,
            snapshot.decimals
        );
        return (previousBorrow +
            (assetValue * tokenData[snapshot.asset].collRatio) /
            WAD);
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
