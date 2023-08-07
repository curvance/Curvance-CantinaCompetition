// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

contract PositionFolding is ReentrancyGuard, IPositionFolding {
    
    /// TYPES ///

    struct LeverageStruct {
        DToken borrowToken;
        uint256 borrowAmount;
        CToken collateralToken;
        // borrow underlying -> zapper input token
        SwapperLib.Swap swapData;
        // zapper input token -> enter curvance
        SwapperLib.ZapperCall zapperCall;
    }

    struct DeleverageStruct {
        CToken collateralToken;
        uint256 collateralAmount;
        CToken borrowToken;
        // collateral underlying to a single token (can be borrow underlying)
        SwapperLib.ZapperCall zapperCall;
        // (optional) zapper outout to borrow underlying
        SwapperLib.Swap swapData;
        uint256 repayAmount;
    }

    /// CONSTANTS ///

    uint256 public constant MAX_LEVERAGE = 9900; // 99%
    uint256 public constant DENOMINATOR = 10000; // Scalar for math
    uint256 public constant SLIPPAGE = 500; // 5%

    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub
    ILendtroller public immutable lendtroller; // Lendtroller linked

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "PositionFolding: UNAUTHORIZED"
        );
        _;
    }

    modifier checkSlippage(address user, uint256 slippage) {
        (uint256 sumCollateralBefore, , uint256 sumBorrowBefore) = lendtroller
            .getAccountPosition(user);
        uint256 userValueBefore = sumCollateralBefore - sumBorrowBefore;

        _;

        (uint256 sumCollateral, , uint256 sumBorrow) = lendtroller
            .getAccountPosition(user);
        uint256 userValue = sumCollateral - sumBorrow;

        uint256 diff = userValue > userValueBefore
            ? userValue - userValueBefore
            : userValueBefore - userValue;
        require(
            diff < (userValueBefore * slippage) / DENOMINATOR,
            "PositionFolding: slippage"
        );
    }

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address lendtroller_) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "PositionFolding: invalid central registry"
        );

        centralRegistry = centralRegistry_;

        require(
            centralRegistry.isLendingMarket(lendtroller_),
            "PositionFolding: lendtroller is invalid"
        );

        lendtroller = ILendtroller(lendtroller_);
    }

    function getProtocolLeverageFee() public view returns (uint256) {
        return ICentralRegistry(centralRegistry).protocolLeverageFee();
    }

    function getDaoAddress() public view returns (address) {
        return ICentralRegistry(centralRegistry).daoAddress();
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
        (bool isListed, ) = lendtroller.getMarketTokenData(borrowToken);

        require(
            isListed && msg.sender == borrowToken,
            "PositionFolding: UNAUTHORIZED"
        );

        LeverageStruct memory leverageData = abi.decode(
            params,
            (LeverageStruct)
        );

        require(
            borrowToken == address(leverageData.borrowToken) &&
                borrowAmount == leverageData.borrowAmount,
            "PositionFolding: invalid params"
        );

        address borrowUnderlying = CToken(borrowToken).underlying();

        require(
            IERC20(borrowUnderlying).balanceOf(address(this)) == borrowAmount,
            "PositionFolding: invalid amount"
        );

        // take protocol fee
        uint256 fee = (borrowAmount * getProtocolLeverageFee()) / 10000;
        if (fee > 0) {
            borrowAmount -= fee;
            SafeTransferLib.safeTransfer(
                borrowUnderlying,
                getDaoAddress(),
                fee
            );
        }

        if (leverageData.swapData.call.length > 0) {
            // swap borrow underlying to zapper input token
            require(
                centralRegistry.isSwapper(leverageData.swapData.target),
                "PositionFolding: invalid swapper"
            );

            SwapperLib.swap(leverageData.swapData);
        }

        // enter curvance
        SwapperLib.ZapperCall memory zapperCall = leverageData.zapperCall;

        if (zapperCall.call.length > 0) {
            require(
                centralRegistry.isZapper(leverageData.zapperCall.target),
                "PositionFolding: invalid zapper"
            );

            SwapperLib.zap(zapperCall);
        }

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
    }

    function onRedeem(
        address collateralToken,
        address redeemer,
        uint256 collateralAmount,
        bytes calldata params
    ) external override {
        require (msg.sender == collateralToken,"PositionFolding: UNAUTHORIZED");

        (bool isListed, ) = lendtroller.getMarketTokenData(collateralToken);
        require( isListed,"PositionFolding: UNAUTHORIZED");

        DeleverageStruct memory deleverageData = abi.decode(
            params,
            (DeleverageStruct)
        );

        require(
            collateralToken == address(deleverageData.collateralToken) &&
                collateralAmount == deleverageData.collateralAmount,
            "PositionFolding: invalid params"
        );

        // swap collateral token to borrow token
        address collateralUnderlying = CToken(collateralToken).underlying();

        require(
            IERC20(collateralUnderlying).balanceOf(address(this)) ==
                collateralAmount,
            "PositionFolding: invalid amount"
        );

        // take protocol fee
        uint256 fee = (collateralAmount * getProtocolLeverageFee()) / 10000;
        if (fee > 0) {
            collateralAmount -= fee;
            SafeTransferLib.safeTransfer(
                collateralUnderlying,
                getDaoAddress(),
                fee
            );
        }

        SwapperLib.ZapperCall memory zapperCall = deleverageData.zapperCall;

        if (zapperCall.call.length > 0) {
            require(
                collateralUnderlying == zapperCall.inputToken,
                "PositionFolding: invalid zapper param"
            );
            require(
                centralRegistry.isZapper(
                    deleverageData.zapperCall.target
                ),
                "PositionFolding: invalid zapper"
            );

            SwapperLib.zap(zapperCall);
        }

        if (deleverageData.swapData.call.length > 0) {
            // swap for borrow underlying
            require(
                centralRegistry.isSwapper(
                    deleverageData.swapData.target
                ),
                "PositionFolding: invalid swapper"
            );

            SwapperLib.swap(deleverageData.swapData);
        }

        // repay debt
        uint256 repayAmount = deleverageData.repayAmount;
        CToken borrowToken = deleverageData.borrowToken;

        address borrowUnderlying = CToken(address(borrowToken)).underlying();
        uint256 remaining = IERC20(borrowUnderlying).balanceOf(address(this)) -
            repayAmount;

        SwapperLib.approveTokenIfNeeded(
            borrowUnderlying,
            address(borrowToken),
            repayAmount + remaining
        );

        DToken(address(borrowToken)).repayForPositionFolding(
            redeemer,
            repayAmount
        );

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
    }

    /// PUBLIC FUNCTIONS ///

    function queryAmountToBorrowForLeverageMax(
        address user,
        address borrowToken
    ) public view returns (uint256) {
        (
            uint256 sumCollateral,
            uint256 maxBorrow,
            uint256 sumBorrow
        ) = lendtroller.getAccountPosition(user);
        uint256 maxLeverage = ((sumCollateral - sumBorrow) *
            MAX_LEVERAGE *
            sumCollateral) /
            (sumCollateral - maxBorrow) /
            DENOMINATOR -
            sumCollateral;

        (uint256 price, uint256 errorCode) = IPriceRouter(
            ICentralRegistry(centralRegistry).priceRouter()
        ).getPrice(address(borrowToken), true, false);

        require(errorCode == 0, "PositionFolding: invalid token price");

        return ((maxLeverage - sumBorrow) * 1e18) / price;
    }

    /// INTERNAL FUNCTIONS ///

    function _leverage(LeverageStruct memory leverageData) internal {
        DToken borrowToken = leverageData.borrowToken;
        uint256 borrowAmount = leverageData.borrowAmount;
        uint256 maxBorrowAmount = queryAmountToBorrowForLeverageMax(
            msg.sender,
            address(borrowToken)
        );

        require(
            borrowAmount <= maxBorrowAmount,
            "PositionFolding: exceeded maximum borrow amount"
        );

        bytes memory params = abi.encode(leverageData);

        DToken(address(borrowToken)).borrowForPositionFolding(
            payable(msg.sender),
            borrowAmount,
            params
        );
    }

    function _deleverage(DeleverageStruct memory deleverageData) internal {
        bytes memory params = abi.encode(deleverageData);
        CToken collateralToken = deleverageData.collateralToken;
        uint256 collateralAmount = deleverageData.collateralAmount;

        CToken(address(collateralToken)).redeemUnderlyingForPositionFolding(
            payable(msg.sender),
            collateralAmount,
            params
        );
    }
}
