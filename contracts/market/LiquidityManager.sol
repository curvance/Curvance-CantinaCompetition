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

    /// @notice Storage structure for Account data involving liquidity
    ///         positions, and pending redemption cooldown.
    /// @param assets Array of account assets.
    /// @param cooldownTimestamp Last time an account performed an action,
    ///                          which activates the redeem/repay/exit market
    ///                          cooldown.
    struct AccountData {
        IMToken[] assets;
        uint256 cooldownTimestamp;
    }

    /// @param activePosition Value that indicates whether an account has
    ///                       an active position in the token.
    ///                       0 or 1 for no; 2 for yes.
    /// @param collateralPosted The amount of collateral an account has posted
    ///                         inside the market. Only applicable to cTokens,
    ///                         not dTokens.
    struct AccountPosition {
        uint256 activePosition;
        uint256 collateralPosted;
    }

    /// @notice Storage configuration for how a market token should behave
    ///         in the liquidity manager.
    /// @param isListed Whether or not this market token is listed.
    ///                 false = unlisted; true = listed.
    /// @param collRatio The ratio at which this token can be collateralized.
    ///                  in `WAD`, e.g. 0.8e18 = 80% collateral value.
    /// @param collReqSoft The collateral requirement where dipping below this
    ///                    will cause a soft liquidation.
    /// @dev In `WAD`, e.g. 1.2e18 = 120% collateral vs debt value.
    /// @param collReqHard The collateral requirement where dipping below
    ///                    this will cause a hard liquidation.
    /// @dev In `WAD`, e.g. 1.2e18 = 120% collateral vs debt value.
    ///      NOTE: Should ALWAYS be less than `collReqSoft`.
    /// @param liqBaseIncentive The base ratio at which this token will be
    ///                         compensated on soft liquidation.
    /// @dev In `WAD`, stored as (Incentive + WAD) e.g. 1.05e18 = 5% incentive,
    ///      this saves gas for liquidation calculations.
    /// @param liqCurve The liquidation incentive curve length between 
    ///                 soft liquidation to hard liquidation.
    ///                 e.g. 5% base incentive with 8% curve length results
    ///                 in 13% liquidation incentive on hard liquidation.
    /// @dev In `WAD`, e.g. 0.05e18 = 5% maximum additional incentive.
    /// @param liqFee The protocol fee that will be taken on liquidation
    ///               for this market token.
    /// @dev In `WAD`, e.g. 0.01e18 = 1% liquidation fee to protocol.
    ///      Note: this is stored as (Fee * WAD) / `liqIncA`
    ///      in order to save gas for liquidation calculations.
    /// @param baseCFactor Maximum % that a liquidator can repay when
    ///                    soft liquidating an account.
    /// @dev In `WAD` format, e.g. 0.1e18 = 10% base close factor.
    /// @param cFactorCurve cFactor curve length between soft liquidation
    ///                     and hard liquidation, should be equal to
    ///                     100% - baseCFactor.
    /// @dev In `WAD` format, e.g. 0.9e18 = 90% distance between base cFactor,
    ///      and 100%.
    /// @param accountPositions Mapping that stores account information like token
    ///                    positions and collateral posted.
    struct MarketToken {
        bool isListed;
        uint256 collRatio;
        uint256 collReqSoft;
        uint256 collReqHard;
        uint256 liqBaseIncentive;
        uint256 liqCurve;
        uint256 liqFee;
        uint256 baseCFactor;
        uint256 cFactorCurve;
        mapping(address => AccountPosition) accountPositions;
    }

    /// @notice Data structure containing information on hypothetical action
    ///         to execute.
    /// @param mTokenModified The mToken to hypothetically redeem/borrow.
    /// @param redeemTokens The number of tokens to hypothetically redeem,
    ///                     in `shares`.
    /// @param borrowAmount The amount of underlying to hypothetically borrow,
    ///                     in `assets`.
    /// @param errorCodeBreakpoint The error code that will cause liquidity
    ///                            operations to revert. We reuse 
    ///                            `errorCodeBreakpoint` as a return variable 
    ///                            as a garbage collection flag to minimize local
    ///                            variables.
    struct HypotheticalAction {
        address mTokenModified;
        uint256 redeemTokens;
        uint256 borrowAmount;
        uint256 errorCodeBreakpoint;
    }

    /// @notice Data structure returned on hypothetical calculation containing
    ///         whether there was a collateral surplus or a liquidity deficit,
    ///         and whether account positions need to be updated.
    /// @param collateralSurplus Excess collateral when adjusted for debt
    ///                          obligations.
    /// @param liquidityDeficit Liquidity deficit when adjusted for debt
    ///                         obligations.
    /// @param updateNeeded Whether account positions need to be updated.
    struct HypotheticalData {
        uint256 collateralSurplus;
        uint256 liquidityDeficit;
        uint256 updateNeeded;
    }

    /// @notice Data structure returned on liquidation calculation containing
    ///         lFactor, and c/d token prices for efficient liquidation processing.
    /// @param lFactor The liquidation factor value corresponding to a users
    ///                posted collateral vs outstanding debt. A lFactor of 0
    ///                corresponds to no liquidation available, an lFactor of
    ///                100% corresponds to a full hard liquidation.
    /// @param collateralTokenPrice The current price of the cToken
    ///                             to be liquidated.
    /// @param debtTokenPrice The current price of the dToken to be repaid.
    struct LiqData {
        uint256 lFactor;
        uint256 collateralTokenPrice;
        uint256 debtTokenPrice;
    }

    /// @notice Data structure returned on Bad Debt calculation containing
    ///         account collateral, amount of debt to repay, total account
    ///         debt.
    /// @paramcollateral Total value of `account` collateral.
    /// @param debt Total value of `account` debt.
    /// @param debtToPay The amount of debt to repay to receive
    ///                  `accountCollateral`.
    struct BadDebtData {
        uint256 collateral;
        uint256 debt;
        uint256 debtToPay;
    }
    
    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Market token data including listing status,
    ///         token characterists, account position data.
    /// @dev Market Token Address => MarketToken struct.
    mapping(address => MarketToken) public tokenData;
    /// @notice Assets and redemption cooldown data for an account.
    /// @dev Account => AccountData struct.
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

        for (uint256 i; i < numAssets; ++i) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the asset has a CR increment their collateral
                // and max borrow value.
                if (tokenData[snapshot.asset].collRatio != 0) {
                    uint256 collateralValue = _assetValue(
                        ((tokenData[snapshot.asset]
                            .accountPositions[account]
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
                    accountDebt += _assetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }
        }
    }

    /// @notice Determine what `account`'s liquidity would be if
    ///         `mTokenModified` were redeemed or borrowed.
    /// @dev Note that we calculate the exchangeRateCached for each collateral
    ///      mToken using stored data, without calculating accumulated
    ///      interest. Function has majority of actions inlined to minimize
    ///      gas costs.
    /// @param account The account to determine liquidity for with a
    ///                hypothetical action.
    /// @param action Struct containing information on hypothetical action
    ///               to execute. Containing Values:
    ///               mTokenModified The mToken to hypothetically redeem/borrow.
    ///               redeemTokens The number of tokens to hypothetically redeem,
    ///                            in `shares`.
    ///               borrowAmount The amount of underlying to hypothetically borrow,
    ///                            in `assets`.
    ///               errorCodeBreakpoint The error code that will cause liquidity
    ///                                   operations to revert. We reuse 
    ///                                   `errorCodeBreakpoint` as a return variable 
    ///                                   as a garbage collection flag to minimize
    ///                                   local variables.
    /// @return result Containing values:
    ///                Excess collateral when adjusted for debt obligations.
    ///                Liquidity deficit when adjusted for debt obligations.
    ///                Whether account positions need to be updated..
    /// @return Array containing whether a user position should be closed or not.
    function _hypotheticalLiquidityOf(
        address account,
        HypotheticalAction memory action
    ) internal view returns (HypotheticalData memory result, bool[] memory) {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, action.errorCodeBreakpoint);
        bool[] memory positionsToClose = new bool[](numAssets);
        uint256 maxDebt;
        uint256 newDebt;

        {
            // Use scoping to avoid stack too deep.
            AccountSnapshot memory snapshot;
            uint256 posted;
            uint256 cr;

            for (uint256 i; i < numAssets; ++i) {
                snapshot = snapshots[i];

                if (snapshot.isCToken) {
                    // Cache Collateralization for cToken status and potential
                    // hypothetical action below.
                    cr = tokenData[snapshot.asset].collRatio;
                    // If the cToken has a Collateralization Ratio,
                    // increment their collateral and max borrow value.
                    if (cr != 0) {
                        // Cache collateral posted.
                        posted = tokenData[snapshot.asset].accountPositions[
                            account].collateralPosted;

                        // If there is no collateral posted and its not a position
                        // to be modified, clean up the position entry as the user
                        // was liquidated.
                        if (posted == 0) {
                            // If there is no collateral posted and its not a position
                            // to be modified, clean up the position entry as the user
                            // was liquidated.
                            if (action.mTokenModified != snapshot.asset) {
                                positionsToClose[i] = true;
                                if (result.updateNeeded == 0) {
                                    result.updateNeeded = 1;
                                }
                            }
                        } else {
                            // There is collateral posted in this cToken, and the user
                            // can take on more debt.
                            maxDebt = _liquidityValue(
                                maxDebt,
                                posted,
                                snapshot.exchangeRate,
                                underlyingPrices[i],
                                snapshot.decimals,
                                cr
                            );
                        }
                    }
                } else {
                    // If they have a debt balance, increment their debt.
                    if (snapshot.debtBalance > 0) {
                        newDebt += _assetValue(
                            snapshot.debtBalance,
                            underlyingPrices[i],
                            snapshot.decimals
                        );
                    } else {
                        // If there is no debt and its not a position
                        // to be modified, clean up the position entry as the user
                        // was liquidated (bad debt insolvency).
                        if (action.mTokenModified != snapshot.asset) {
                            positionsToClose[i] = true;
                            if (result.updateNeeded == 0) {
                                result.updateNeeded = 1;
                            }
                        }
                    }
                }

                // Calculate impact of mTokenModified action.
                if (action.mTokenModified == snapshot.asset) {
                    // If its a CToken our only option is to redeem it since
                    // it cant be borrowed.
                    // If its a DToken we can redeem it but it will not have
                    // any effect on borrow amount since DToken have a collateral
                    // value of 0.
                    if (snapshot.isCToken) {
                        // If the cToken has a Collateralization Ratio,
                        // increase their new debt.
                        if (cr != 0) {
                            // If they are trying to redeem more tokens than they have,
                            // the transaction will fail before it gets to this point,
                            // so no special case needed.
                            if (posted == action.redeemTokens) {
                                positionsToClose[i] = true;
                                if (result.updateNeeded == 0) {
                                    result.updateNeeded = 1;
                                }
                            }
                            
                            // Hypothetical redemption action.
                            newDebt += _redemptionValue(
                                action.redeemTokens,
                                snapshot.exchangeRate,
                                underlyingPrices[i],
                                snapshot.decimals,
                                cr
                            );
                        }
                    } else {
                        // Hypothetical borrow action.
                        newDebt += _assetValue(
                            action.borrowAmount,
                            underlyingPrices[i],
                            snapshot.decimals
                        );
                        // We don't need to check for closing a position here since
                        // borrow action will only expand a position.
                    }
                }
            }
        }

        // These will not underflow/overflow as condition is checked prior.
        // Returns excess liquidity on hypothetical positions.
        if (maxDebt > newDebt) {
            unchecked {
                result.collateralSurplus = maxDebt - newDebt;
            }

            return (result, positionsToClose);
        }

        // Returns shortfall on hypothetical positions.
        unchecked {
            result.liquidityDeficit = newDebt - maxDebt;
        }

        return (result, positionsToClose);
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

        for (uint256 i; i < numAssets; ++i) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                // If the cToken has a Collateralization Ratio,
                // increment their collateral.
                if (tokenData[snapshot.asset].collRatio != 0) {
                    accountCollateral += _assetValue(
                        ((tokenData[snapshot.asset]
                            .accountPositions[account]
                            .collateralPosted * snapshot.exchangeRate) / WAD),
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            } else {
                // If they have a debt balance, increment their debt.
                if (snapshot.debtBalance > 0) {
                    accountDebt += _assetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
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

        for (uint256 i; i < numAssets; ++i) {
            snapshot = snapshots[i];

            if (snapshot.isCToken) {
                if (snapshot.asset == collateralToken) {
                    result.collateralTokenPrice = underlyingPrices[i];
                }

                // If the asset has a CR increment their collateral.
                if (tokenData[snapshot.asset].collRatio != 0) {
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
                    accountDebt += _assetValue(
                        snapshot.debtBalance,
                        underlyingPrices[i],
                        snapshot.decimals
                    );
                }
            }
        }

        // Indicates no liquidation.
        if (accountCollateralSoft >= accountDebt) {
            return result;
        }

        // Indicates hard liquidation.
        if (accountDebt >= accountCollateralHard) {
            result.lFactor = WAD;
            return result;
        }

        // Indicates soft liquidation.
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

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity and whether theres associated bad debt available.
    /// @param account The account to determine bad debt status.
    /// @return result Containing values:
    ///                Total value of `account` collateral.
    ///                The amount of debt to repay to receive `accountCollateral`.
    ///                Total value of `account` debt.
    /// @return Array of the amount of collateral posted for each user asset.
    function _BadDebtTermsOf(
        address account
    )
        internal
        view
        returns (
            BadDebtData memory result,
            uint256[] memory
        )
    {
        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = _assetDataOf(account, 2);
        uint256[] memory assetBalances = new uint256[](numAssets);

        {
            AccountSnapshot memory snapshot;
            uint256 posted;
            
            for (uint256 i; i < numAssets; ++i) {
                snapshot = snapshots[i];

                if (snapshot.isCToken) {
                    // If the cToken has a Collateralization Ratio,
                    // increment their collateral and debt to pay.
                    if (tokenData[snapshot.asset].collRatio != 0) {
                        // Cache collateral posted.
                        posted = tokenData[snapshot.asset].accountPositions[
                            account].collateralPosted;

                        assetBalances[i] = posted;
                        uint256 collateralValue = _assetValue(
                            ((posted * snapshot.exchangeRate) / WAD),
                            underlyingPrices[i],
                            snapshot.decimals
                        );
                        result.collateral += collateralValue;
                        result.debtToPay +=
                            (collateralValue * WAD) /
                            tokenData[snapshot.asset].liqBaseIncentive;
                    }
                } else {
                    // If they have a debt balance, increment their debt.
                    uint256 currentDebtBalance = snapshot.debtBalance;
                    if (currentDebtBalance > 0) {
                        assetBalances[i] = currentDebtBalance;
                        result.debt += _assetValue(
                            currentDebtBalance,
                            underlyingPrices[i],
                            snapshot.decimals
                        );
                    }
                }
            }
        }

        return (result, assetBalances);
    }

    /// @notice Retrieves the prices and account data of multiple assets
    ///         inside this market.
    /// @param account The account to retrieve data for.
    /// @param errorCodeBreakpoint The error code that will cause liquidity
    ///                            operations to revert.
    /// @return Assets data for `account`.
    /// @return Prices for `account` assets.
    /// @return The number of assets `account` is in.
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

    /// @notice Calculates an assets value based on its `price`,
    ///         `amount`, and adjusts for decimals.
    /// @param amount The asset amount to calculate asset value from.
    /// @param price The asset price to calculate asset value from.
    /// @param decimals The asset decimals to adjust asset value
    ///                 into proper form.
    /// @return The calculated asset value.
    function _assetValue(
        uint256 amount,
        uint256 price,
        uint256 decimals
    ) internal pure returns (uint256) {
        return (amount * price) / (10 ** decimals);
    }

    /// @notice Calculates a redemptions value based on its `amount`,
    ///         `exchangeRate`, `price`, `collRatio`, and adjusts for decimals.
    /// @param amount The asset amount to redeem.
    /// @param exchangeRate The exchange rate between cToken and underlying.
    /// @param price The asset's price.
    /// @param decimals The asset's decimals to adjust redemption value
    ///                 into proper form.
    /// @param collRatio The collateralization ratio of the asset.
    /// @return The calculated redemption value.
    function _redemptionValue(
        uint256 amount,
        uint256 exchangeRate,
        uint256 price,
        uint256 decimals,
        uint256 collRatio
    ) internal pure returns (uint256) {
        uint256 assetValue = _assetValue(
            (amount * exchangeRate) / WAD,
            price,
            decimals
        );

        // Hypothetical redemption action.
        return ((assetValue * collRatio) / WAD);
    }

    /// @notice Calculates asset liquidity for the purpose of borrowing
    ///         assets.
    /// @param liqForBorrowPrior Prior liquidity value to sum with asset value
    ///                          calculated for new maximum borrow allowed.
    /// @param posted Current collateral posted.
    /// @param exchangeRate The exchange rate between cToken and underlying.
    /// @param price The asset's price.
    /// @param decimals The asset's decimals to adjust liquidity value
    ///                 into proper form.
    /// @param collRatio The collateralization ratio of the asset.
    /// @return The calculated liquidity value plus previous value.
    function _liquidityValue(
        uint256 liqForBorrowPrior,
        uint256 posted,
        uint256 exchangeRate,
        uint256 price,
        uint256 decimals,
        uint256 collRatio
    ) internal pure returns (uint256) {
        uint256 assetValue = _assetValue(
            ((posted * exchangeRate) / WAD),
            price,
            decimals
        );

        return (liqForBorrowPrior + (assetValue * collRatio) / WAD);
    }

    /// @notice Calculates new soft and hard liquidation values based
    ///         on prior values and asset snapshot.
    /// @param snapshot Asset snapshot to calculate asset value from.
    /// @param account The account to query collateral posted for to calculate
    ///                liquidation values off of.
    /// @param price The asset price to calculate asset value from.
    /// @param softSumPrior Prior soft liquidation value to sum with asset
    ///                     value calculated.
    /// @param hardSumPrior Prior hard liquidation value to sum with asset
    ///                     value calculated.
    /// @return The calculated soft liquidation value.
    /// @return The calculated hard liquidation value.
    function _addLiquidationValues(
        AccountSnapshot memory snapshot,
        address account,
        uint256 price,
        uint256 softSumPrior,
        uint256 hardSumPrior
    ) internal view returns (uint256, uint256) {
        uint256 assetValue = _assetValue(
            ((tokenData[snapshot.asset].accountPositions[account].collateralPosted *
                snapshot.exchangeRate) / WAD),
            price,
            snapshot.decimals
        ) * WAD;

        return (
            softSumPrior + (assetValue / tokenData[snapshot.asset].collReqSoft),
            hardSumPrior + (assetValue / tokenData[snapshot.asset].collReqHard)
        );
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
