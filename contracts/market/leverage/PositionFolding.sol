// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { DENOMINATOR, WAD } from "contracts/libraries/Constants.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/external/ReentrancyGuard.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

contract PositionFolding is IPositionFolding, ERC165, ReentrancyGuard {
    /// TYPES ///

    struct LeverageStruct {
        DToken borrowToken;
        uint256 borrowAmount;
        CTokenPrimitive collateralToken;
        // borrow underlying -> zapper input token
        SwapperLib.Swap swapData;
        // zapper input token -> enter curvance
        SwapperLib.ZapperCall zapperCall;
    }

    struct DeleverageStruct {
        CTokenPrimitive collateralToken;
        uint256 collateralAmount;
        DToken borrowToken;
        // collateral underlying to a single token (can be borrow underlying)
        SwapperLib.ZapperCall zapperCall;
        // (optional) zapper outout to borrow underlying
        SwapperLib.Swap swapData;
        uint256 repayAmount;
    }

    /// CONSTANTS ///

    uint256 public constant MAX_LEVERAGE = 9900; // 99%

    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub
    IMarketManager public immutable marketManager; // MarketManager linked

    /// ERRORS ///

    error PositionFolding__Unauthorized();
    error PositionFolding__InvalidSlippage();
    error PositionFolding__InvalidCentralRegistry();
    error PositionFolding__InvalidMarketManager();
    error PositionFolding__InvalidSwapper(address invalidSwapper);
    error PositionFolding__InvalidParam();
    error PositionFolding__InvalidAmount();
    error PositionFolding__InvalidZapper(address invalidZapper);
    error PositionFolding__InvalidZapperParam();
    error PositionFolding__InvalidTokenPrice();
    error PositionFolding__ExceedsMaximumBorrowAmount(
        uint256 amount,
        uint256 maximum
    );

    /// MODIFIERS ///

    modifier checkSlippage(address user, uint256 slippage) {
        (uint256 collateralBefore, uint256 debtBefore) = marketManager
            .solvencyOf(user);
        uint256 liquidityBefore = collateralBefore - debtBefore;

        _;

        (uint256 sumCollateral, uint256 sumDebt) = marketManager.solvencyOf(
            user
        );

        uint256 liquidityAfter = sumCollateral - sumDebt;
        // If there was slippage, make sure its within slippage tolerance
        if (liquidityBefore > liquidityAfter) {
            if (
                liquidityBefore - liquidityAfter >=
                (liquidityBefore * slippage) / DENOMINATOR
            ) {
                revert PositionFolding__InvalidSlippage();
            }
        }
    }

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address marketManager_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert PositionFolding__InvalidCentralRegistry();
        }

        if (!centralRegistry_.isMarketManager(marketManager_)) {
            revert PositionFolding__InvalidMarketManager();
        }

        centralRegistry = centralRegistry_;
        marketManager = IMarketManager(marketManager_);
    }

    function getProtocolLeverageFee() public view returns (uint256) {
        return centralRegistry.protocolLeverageFee();
    }

    /// EXTERNAL FUNCTIONS ///

    function leverage(
        LeverageStruct calldata leverageData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        _leverage(leverageData);
    }

    function deleverage(
        DeleverageStruct calldata deleverageData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        _deleverage(deleverageData);
    }

    function onBorrow(
        address borrowToken,
        address borrower,
        uint256 borrowAmount,
        bytes calldata params
    ) external override {
        if (!marketManager.isListed(borrowToken) && msg.sender != borrowToken) {
            revert PositionFolding__Unauthorized();
        }

        LeverageStruct memory leverageData = abi.decode(
            params,
            (LeverageStruct)
        );

        if (
            borrowToken != address(leverageData.borrowToken) ||
            borrowAmount != leverageData.borrowAmount
        ) {
            revert PositionFolding__InvalidParam();
        }

        address borrowUnderlying = CTokenPrimitive(borrowToken).underlying();

        if (IERC20(borrowUnderlying).balanceOf(address(this)) < borrowAmount) {
            revert PositionFolding__InvalidAmount();
        }

        // take protocol fee
        uint256 fee = (borrowAmount * getProtocolLeverageFee()) / WAD;
        if (fee > 0) {
            SafeTransferLib.safeTransfer(
                borrowUnderlying,
                centralRegistry.daoAddress(),
                fee
            );
        }

        if (leverageData.swapData.call.length > 0) {
            // swap borrow underlying to zapper input token
            if (!centralRegistry.isSwapper(leverageData.swapData.target)) {
                revert PositionFolding__InvalidSwapper(
                    leverageData.swapData.target
                );
            }

            SwapperLib.swap(leverageData.swapData);
        }

        // prepare LP
        SwapperLib.ZapperCall memory zapperCall = leverageData.zapperCall;

        if (zapperCall.call.length > 0) {
            if (!centralRegistry.isZapper(leverageData.zapperCall.target)) {
                revert PositionFolding__InvalidZapper(
                    leverageData.zapperCall.target
                );
            }

            SwapperLib.zap(zapperCall);
        }

        // enter curvance
        address collateralUnderlying = leverageData
            .collateralToken
            .underlying();
        uint256 amount = IERC20(collateralUnderlying).balanceOf(address(this));
        SwapperLib._approveTokenIfNeeded(
            collateralUnderlying,
            address(leverageData.collateralToken),
            amount
        );
        leverageData.collateralToken.depositAsCollateral(amount, borrower);

        // transfer remaining zapper input token back to the user
        uint256 remaining = IERC20(zapperCall.inputToken).balanceOf(
            address(this)
        );

        if (remaining > 0) {
            SafeTransferLib.safeTransfer(
                zapperCall.inputToken,
                borrower,
                remaining
            );
        }

        // transfer remaining borrow underlying back to the user
        remaining = IERC20(borrowUnderlying).balanceOf(address(this));

        if (remaining > 0) {
            SafeTransferLib.safeTransfer(
                borrowUnderlying,
                borrower,
                remaining
            );
        }

        SwapperLib._removeApprovalIfNeeded(
            borrowUnderlying,
            address(borrowToken)
        );
    }

    function onRedeem(
        address collateralToken,
        address redeemer,
        uint256 collateralAmount,
        bytes calldata params
    ) external override {
        if (msg.sender != collateralToken) {
            revert PositionFolding__Unauthorized();
        }

        if (!marketManager.isListed(collateralToken)) {
            revert PositionFolding__Unauthorized();
        }

        DeleverageStruct memory deleverageData = abi.decode(
            params,
            (DeleverageStruct)
        );

        if (
            collateralToken != address(deleverageData.collateralToken) ||
            collateralAmount != deleverageData.collateralAmount
        ) {
            revert PositionFolding__InvalidParam();
        }

        // swap collateral token to borrow token
        address collateralUnderlying = CTokenPrimitive(collateralToken)
            .underlying();

        if (
            IERC20(collateralUnderlying).balanceOf(address(this)) <
            collateralAmount
        ) {
            revert PositionFolding__InvalidAmount();
        }

        // take protocol fee
        uint256 fee = (collateralAmount * getProtocolLeverageFee()) / 10000;
        if (fee > 0) {
            collateralAmount -= fee;
            SafeTransferLib.safeTransfer(
                collateralUnderlying,
                centralRegistry.daoAddress(),
                fee
            );
        }

        SwapperLib.ZapperCall memory zapperCall = deleverageData.zapperCall;

        if (zapperCall.call.length > 0) {
            if (collateralUnderlying != zapperCall.inputToken) {
                revert PositionFolding__InvalidZapperParam();
            }
            if (!centralRegistry.isZapper(deleverageData.zapperCall.target)) {
                revert PositionFolding__InvalidZapper(
                    deleverageData.zapperCall.target
                );
            }

            SwapperLib.zap(zapperCall);
        }

        if (deleverageData.swapData.call.length > 0) {
            // swap for borrow underlying
            if (!centralRegistry.isSwapper(deleverageData.swapData.target)) {
                revert PositionFolding__InvalidSwapper(
                    deleverageData.swapData.target
                );
            }

            SwapperLib.swap(deleverageData.swapData);
        }

        // repay debt
        uint256 repayAmount = deleverageData.repayAmount;
        DToken borrowToken = deleverageData.borrowToken;

        address borrowUnderlying = borrowToken.underlying();
        uint256 remaining = IERC20(borrowUnderlying).balanceOf(address(this)) -
            repayAmount;

        SwapperLib._approveTokenIfNeeded(
            borrowUnderlying,
            address(borrowToken),
            repayAmount
        );

        DToken(address(borrowToken)).repayFor(redeemer, repayAmount);

        if (remaining > 0) {
            // remaining borrow underlying back to user
            SafeTransferLib.safeTransfer(
                borrowUnderlying,
                redeemer,
                remaining
            );
        }

        // transfer remaining collateral underlying back to the user
        remaining = IERC20(collateralUnderlying).balanceOf(address(this));

        if (remaining > 0) {
            SafeTransferLib.safeTransfer(
                collateralUnderlying,
                redeemer,
                remaining
            );
        }

        SwapperLib._removeApprovalIfNeeded(
            borrowUnderlying,
            address(borrowToken)
        );
    }

    /// PUBLIC FUNCTIONS ///

    function queryAmountToBorrowForLeverageMax(
        address user,
        address borrowToken
    ) public view returns (uint256) {
        (uint256 sumCollateral, uint256 maxDebt, uint256 sumDebt) = marketManager
            .statusOf(user);
        uint256 maxLeverage = ((sumCollateral - sumDebt) *
            MAX_LEVERAGE *
            sumCollateral) /
            (sumCollateral - maxDebt) /
            DENOMINATOR -
            sumCollateral;

        (uint256 price, uint256 errorCode) = IOracleRouter(
            ICentralRegistry(centralRegistry).oracleRouter()
        ).getPrice(address(borrowToken), true, false);

        if (errorCode != 0) {
            revert PositionFolding__InvalidTokenPrice();
        }

        return ((maxLeverage - sumDebt) * 1e18) / price;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IPositionFolding).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    function _leverage(LeverageStruct memory leverageData) internal {
        DToken borrowToken = leverageData.borrowToken;
        uint256 borrowAmount = leverageData.borrowAmount;
        uint256 maxBorrowAmount = queryAmountToBorrowForLeverageMax(
            msg.sender,
            address(borrowToken)
        );

        if (borrowAmount > maxBorrowAmount) {
            revert PositionFolding__ExceedsMaximumBorrowAmount(
                borrowAmount,
                maxBorrowAmount
            );
        }

        bytes memory params = abi.encode(leverageData);

        DToken(address(borrowToken)).borrowForPositionFolding(
            payable(msg.sender),
            borrowAmount,
            params
        );
    }

    function _deleverage(DeleverageStruct memory deleverageData) internal {
        bytes memory params = abi.encode(deleverageData);
        CTokenPrimitive collateralToken = deleverageData.collateralToken;
        uint256 collateralAmount = deleverageData.collateralAmount;

        CTokenPrimitive(address(collateralToken)).withdrawByPositionFolding(
            payable(msg.sender),
            collateralAmount,
            params
        );
    }
}
