// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";

interface ILendtroller {

    /// Events ///

    /// @notice Emitted when an admin supports a market
    event MarketListed(IMToken mToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(IMToken mToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(IMToken mToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        uint256 oldCloseFactorScaled,
        uint256 newCloseFactorScaled
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        IMToken mToken,
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
    event ActionPaused(IMToken mToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a mToken is changed
    event NewBorrowCap(IMToken indexed mToken, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap for a mToken is changed
    event SetDisableCollateral(IMToken indexed mToken, bool disable);

    /// @notice Emitted when borrow cap for a mToken is changed
    event SetUserDisableCollateral(
        address indexed user,
        IMToken indexed mToken,
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
        address[] calldata mTokens
    ) external returns (uint256[] memory);

    function exitMarket(address mToken) external;

    function mintAllowed(address mToken, address minter) external;

    function redeemAllowed(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) external;

    function borrowAllowed(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayAllowed(address mToken, address borrower) external;

    function liquidateUserAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external;

    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower
    ) external;

    function transferAllowed(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    function notifyAccountBorrow(address account) external;

    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256);

    function getMarketTokenData(
        address mToken
    ) external view returns (bool, uint256);

    function getAccountMembership(
        address mToken,
        address user
    ) external view returns (bool);

    function getAllMarkets() external view returns (IMToken[] memory);

    function getAccountAssets(
        address mToken
    ) external view returns (IMToken[] memory);

    function positionFolding() external view returns (address);

    function gaugePool() external view returns (address);

    function isLendtroller() external view returns (bool);

    function getAccountPosition(
        address account
    ) external view returns (uint256, uint256, uint256);
}
