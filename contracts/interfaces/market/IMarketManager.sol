// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

interface IMarketManager {

    /// @notice Whether mToken minting is paused. 
    /// @dev Token => 0 or 1 = unpaused; 2 = paused.
    function mintPaused(address mToken) external view returns (uint256);

    /// @notice Post collateral for `mToken` inside this market.
    /// @param account The account posting collateral.
    /// @param mToken The address of the mToken to post collateral for.
    /// @param tokens The amount of `mToken` to post as collateral, in shares.
    function postCollateral(
        address account, 
        address mToken, 
        uint256 tokens
    ) external;

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
    ) external;

    /// @notice Checks if the account should be allowed to mint tokens
    ///         in the given market.
    /// @param mToken The token to verify mints against.
    function canMint(address mToken) external;

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
    ) external;

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
        bool forceReduce
    ) external;

    /// @notice Checks if the account should be allowed to borrow
    ///         the underlying asset of the given market.
    /// @param mToken The market to verify the borrow against.
    /// @param account The account which would borrow the asset.
    /// @param amount The amount of underlying the account would borrow.
    function canBorrow(
        address mToken,
        address account,
        uint256 amount
    ) external;

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
    ) external;

    /// @notice Checks if the account should be allowed to repay a borrow
    ///         in the given market.
    /// @param mToken The market to verify the repay against.
    /// @param account The account who will have their loan repaid.
    function canRepay(address mToken, address borrower) external;

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
    ) external returns (uint256, uint256, uint256);

    /// @notice Checks if the seizing of assets should be allowed to occur.
    /// @param collateralToken Asset which was used as collateral
    ///                        and will be seized.
    /// @param debtToken Asset which was borrowed by the account.
    function canSeize(
        address collateralToken,
        address debtToken
    ) external;

    /// @notice Checks if the account should be allowed to transfer tokens
    ///         in the given market.
    /// @param mToken The market to verify the transfer against.
    /// @param from The account which sources the tokens.
    /// @param amount The number of mTokens to transfer.
    function canTransfer(
        address mToken,
        address from,
        uint256 amount
    ) external;

    /// @notice Updates `account` cooldownTimestamp to the current block timestamp.
    /// @dev The caller must be a listed MToken in the `markets` mapping.
    /// @param mToken The address of the dToken that the account is borrowing.
    /// @param account The address of the account that has just borrowed.
    function notifyBorrow(address mToken, address account) external;

    /// @notice A list of all tokens inside this market for
    ///         offchain querying.
    function tokensListed() external view returns (address[] memory);

    /// @notice Returns whether `mToken` is listed in the lending market.
    /// @param mToken market token address.
    function isListed(address mToken) external view returns (bool);

    /// @notice Returns the assets an account has entered.
    /// @param account The address of the account to pull assets for.
    /// @return A dynamic list with the assets the account has entered.
    function assetsOf(
        address mToken
    ) external view returns (IMToken[] memory);

    /// @notice Returns if an account has an active position in `mToken`.
    /// @param account The address of the account to check a position of.
    /// @param mToken The address of the market token.
    function tokenDataOf(
        address account,
        address mToken
    ) external view returns (bool, uint256, uint256);

    /// @notice Determine `account`'s current status between collateral,
    ///         debt, and additional liquidity.
    /// @param account The account to determine liquidity for.
    /// @return accountCollateral total collateral amount of account.
    /// @return maxDebt max borrow amount of account.
    /// @return accountDebt total borrow amount of account.
    function statusOf(
        address account
    ) external view returns (uint256, uint256, uint256);

    /// @notice Determine `account`'s current collateral and debt values
    ///         in the market.
    /// @param account The account to check bad debt status for.
    /// @return The total market value of `account`'s collateral.
    /// @return The total outstanding debt value of `account`.
    function solvencyOf(
        address account
    ) external view returns (uint256, uint256);

    /// @notice The address of the linked Position Folding Contract.
    function positionFolding() external view returns (address);

    /// @notice The address of the linked Gauge Pool Contract.
    function gaugePool() external view returns (GaugePool);
}
