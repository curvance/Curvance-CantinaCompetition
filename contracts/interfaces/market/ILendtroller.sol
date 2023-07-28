// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";

interface ILendtroller {

    /// TYPES ///

    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint256 collateralFactorScaled;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
    }

    /// Errors ///

    error MarketNotListed(address);
    error AddressAlreadyJoined();
    error NonZeroBorrowBalance(); /// Take a look here, could soften the landing
    error Paused();
    error InsufficientLiquidity();
    error PriceError();
    error BorrowCapReached();
    error InsufficientShortfall();
    error TooMuchRepay();
    error LendtrollerMismatch();
    error MarketAlreadyListed();
    error InvalidValue();
    error AddressUnauthorized();
    error MinimumHoldPeriod();

    /// Events ///

    /// @notice Emitted when an admin supports a market
    event MarketListed(IMToken cToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(IMToken cToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(IMToken cToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        uint256 oldCloseFactorScaled,
        uint256 newCloseFactorScaled
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        IMToken cToken,
        uint256 oldCollateralFactorScaled,
        uint256 newCollateralFactorScaled
    );

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(
        uint256 oldLiquidationIncentiveScaled,
        uint256 newLiquidationIncentiveScaled
    );

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(address oldPriceOracle, address newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(IMToken cToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a cToken is changed
    event NewBorrowCap(IMToken indexed cToken, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap for a cToken is changed
    event SetDisableCollateral(IMToken indexed cToken, bool disable);

    /// @notice Emitted when borrow cap for a cToken is changed
    event SetUserDisableCollateral(
        address indexed user,
        IMToken indexed cToken,
        bool disable
    );

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(
        address oldBorrowCapGuardian,
        address newBorrowCapGuardian
    );

    /// @notice Emitted when position folding contract address is changed
    event NewPositionFoldingContract(
        address indexed oldPositionFolding,
        address indexed newPositionFolding
    );

    /// FUNCTIONS ///

    function enterMarkets(
        address[] calldata cTokens
    ) external returns (uint256[] memory);

    function exitMarket(address cToken) external;

    function mintAllowed(address cToken, address minter) external;

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external;

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayAllowed(address cToken, address borrower) external;

    function liquidateUserAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower
    ) external;

    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    function notifyAccountBorrow(address account) external;

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256);

    function getIsMarkets(
        address cToken
    ) external view returns (bool, uint256);

    function getAccountMembership(
        address cToken,
        address user
    ) external view returns (bool);

    function getAllMarkets() external view returns (IMToken[] memory);

    function getAccountAssets(
        address cToken
    ) external view returns (IMToken[] memory);

    function positionFolding() external view returns (address);

    function gaugePool() external view returns (address);

    function isLendtroller() external view returns (bool);

    function getAccountPosition(
        address account
    ) external view returns (uint256, uint256, uint256);
}
