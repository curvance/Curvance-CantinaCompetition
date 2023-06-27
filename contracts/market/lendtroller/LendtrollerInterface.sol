// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CToken } from "contracts/token/collateral/CToken.sol";

import "./LendtrollerStorage.sol";

abstract contract LendtrollerInterface is LendtrollerStorage {
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
    error LendtrollerMismatch();
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
    event NewCloseFactor(
        uint256 oldCloseFactorScaled,
        uint256 newCloseFactorScaled
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        CToken cToken,
        uint256 oldCollateralFactorScaled,
        uint256 newCollateralFactorScaled
    );

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(
        uint256 oldLiquidationIncentiveScaled,
        uint256 newLiquidationIncentiveScaled
    );

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(
        PriceOracle oldPriceOracle,
        PriceOracle newPriceOracle
    );

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(CToken cToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a cToken is changed
    event NewBorrowCap(CToken indexed cToken, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap for a cToken is changed
    event SetDisableCollateral(CToken indexed cToken, bool disable);

    /// @notice Emitted when borrow cap for a cToken is changed
    event SetUserDisableCollateral(
        address indexed user,
        CToken indexed cToken,
        bool disable
    );

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(
        address oldBorrowCapGuardian,
        address newBorrowCapGuardian
    );

    /// @notice Emitted when rewards contract address is changed
    //event NewRewardContract(RewardsInterface oldRewarder, RewardsInterface newRewarder);

    /// @notice Emitted when position folding contract address is changed
    event NewPositionFoldingContract(
        address indexed oldPositionFolding,
        address indexed newPositionFolding
    );

    ////////// Constants //////////

    /// @notice Indicator that this is a Lendtroller contract (for inspection)
    bool public constant isLendtroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata cTokens)
        external
        virtual
        returns (uint256[] memory);

    function exitMarket(address cToken) external virtual;

    /*** Policy Hooks ***/

    function mintAllowed(address cToken, address minter) external virtual;

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external virtual;

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external virtual;

    function repayBorrowAllowed(address cToken, address borrower)
        external
        virtual;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external virtual;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower
    ) external virtual;

    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external virtual;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 repayAmount
    ) external view virtual returns (uint256);

    /** Query functions */
    function getIsMarkets(address cToken)
        external
        view
        virtual
        returns (
            bool,
            uint256,
            bool
        );

    function getAccountMembership(address cToken, address user)
        external
        view
        virtual
        returns (bool);

    function getAllMarkets() external view virtual returns (CToken[] memory);

    function getAccountAssets(address cToken)
        external
        view
        virtual
        returns (CToken[] memory);
}
