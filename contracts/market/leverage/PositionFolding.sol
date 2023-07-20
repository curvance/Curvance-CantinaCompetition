// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { CEther } from "contracts/market/collateral/CEther.sol";
import { CErc20 } from "contracts/market/collateral/CErc20.sol";

import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";

contract PositionFolding is ReentrancyGuard, IPositionFolding {
    struct ZapperCall {
        address target;
        bytes call;
    }

    uint256 public constant MAX_LEVERAGE = 9900; // 0.99
    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant SLIPPAGE = 500;
    address public constant ETH = address(0);

    address public centralRegistry;
    ILendtroller public lendtroller;
    address public cether;
    address public weth;

    receive() external payable {}

    constructor(
        address _centralRegistry,
        address _lendtroller,
        address _cether,
        address _weth
    ) {
        centralRegistry = _centralRegistry;
        lendtroller = ILendtroller(_lendtroller);
        cether = _cether;
        weth = _weth;
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

    function leverage(
        CToken borrowToken,
        uint256 borrowAmount,
        SwapperLib.Swap calldata swapData,
        address collateralUnderlying,
        ZapperCall calldata zapperCall,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        uint256 maxBorrowAmount = queryAmountToBorrowForLeverageMax(
            msg.sender,
            address(borrowToken)
        );
        require(
            borrowAmount <= maxBorrowAmount,
            "PositionFolding: exceeded maximum borrow amount"
        );
        _leverage(
            borrowToken,
            borrowAmount,
            swapData,
            collateralUnderlying,
            zapperCall
        );
    }

    function batchLeverage(
        CToken[] memory borrowTokens,
        uint256[] memory borrowAmounts,
        SwapperLib.Swap[] memory swapData,
        address[] memory collateralUnderlyings,
        ZapperCall[] memory zapperCalls,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) {
        uint256 numBorrowTokens = borrowTokens.length;
        require(
            borrowAmounts.length == numBorrowTokens &&
                collateralUnderlyings.length == numBorrowTokens &&
                swapData.length == numBorrowTokens &&
                zapperCalls.length == numBorrowTokens,
            "PositionFolding: invalid array length"
        );

        uint256 maxBorrowAmount;
        for (uint256 i; i < numBorrowTokens; ++i) {
            maxBorrowAmount = queryAmountToBorrowForLeverageMax(
                msg.sender,
                address(borrowTokens[i])
            );
            require(
                borrowAmounts[i] <= maxBorrowAmount,
                "PositionFolding: exceeded maximum borrow amount"
            );
            _leverage(
                borrowTokens[i],
                borrowAmounts[i],
                swapData[i],
                collateralUnderlyings[i],
                zapperCalls[i]
            );
        }
    }

    function _leverage(
        CToken borrowToken,
        uint256 borrowAmount,
        SwapperLib.Swap memory swapData,
        address collateralUnderlying,
        ZapperCall memory zapperCall // this should be enter curvance
    ) internal {
        bytes memory params = abi.encode(
            swapData,
            collateralUnderlying,
            zapperCall
        );

        if (address(borrowToken) == cether) {
            CEther(payable(address(borrowToken))).borrowForPositionFolding(
                msg.sender,
                borrowAmount,
                params
            );
        } else {
            CErc20(address(borrowToken)).borrowForPositionFolding(
                msg.sender,
                borrowAmount,
                params
            );
        }
    }

    function onBorrow(
        address borrowToken,
        address borrower,
        uint256 amount,
        bytes memory params
    ) external override {
        (bool isListed, ) = lendtroller.getIsMarkets(borrowToken);
        require(
            isListed && msg.sender == borrowToken,
            "PositionFolding: UNAUTHORIZED"
        );

        (
            SwapperLib.Swap memory swapData,
            address collateralUnderlying,
            ZapperCall memory zapperCall
        ) = abi.decode(params, (SwapperLib.Swap, address, ZapperCall));

        if (borrowToken == cether) {
            require(
                address(this).balance >= amount,
                "PositionFolding: invalid amount"
            );
            IWETH(weth).deposit{ value: amount }(amount);
        } else {
            address borrowUnderlying = CErc20(borrowToken).underlying();
            require(
                IERC20(borrowUnderlying).balanceOf(address(this)) >= amount,
                "PositionFolding: invalid amount"
            );
        }

        if (swapData.call.length > 0) {
            SwapperLib.swap(
                swapData,
                ICentralRegistry(centralRegistry).priceRouter(),
                SLIPPAGE
            );
        }

        uint256 collateralAmount = IERC20(collateralUnderlying).balanceOf(
            address(this)
        );
        SwapperLib.approveTokenIfNeeded(
            collateralUnderlying,
            zapperCall.target,
            collateralAmount
        );

        (bool success, bytes memory retData) = zapperCall.target.call(
            zapperCall.call
        );

        SwapperLib.propagateError(success, retData, "zapper");

        // check remaining collateral amount
        collateralAmount = IERC20(collateralUnderlying).balanceOf(
            address(this)
        );
        // transfer remaining back to the user
        SafeTransferLib.safeTransfer(
            collateralUnderlying,
            borrower,
            collateralAmount
        );
    }

    function deleverage(
        CToken collateral,
        uint256 collateralAmount,
        SwapperLib.Swap calldata swapData,
        address borrowUnderlying,
        ZapperCall calldata zapperCall,
        CToken borrowToken,
        uint256 repayAmount,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        _deleverage(
            collateral,
            collateralAmount,
            borrowToken,
            repayAmount,
            swapData
        );
    }

    function batchDeleverage(
        CToken[] memory collateralTokens,
        uint256[] memory collateralAmount,
        CToken[] memory borrowTokens,
        uint256[] memory repayAmounts,
        SwapperLib.Swap[] memory swapData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) {
        uint256 numCollateralTokens = collateralTokens.length;
        require(
            collateralAmount.length == numCollateralTokens &&
                borrowTokens.length == numCollateralTokens &&
                repayAmounts.length == numCollateralTokens &&
                swapData.length == numCollateralTokens,
            "PositionFolding: invalid array length"
        );

        for (uint256 i; i < numCollateralTokens; ++i) {
            _deleverage(
                collateralTokens[i],
                collateralAmount[i],
                borrowTokens[i],
                repayAmounts[i],
                swapData[i]
            );
        }
    }

    function _deleverage(
        CToken collateral,
        uint256 collateralAmount,
        CToken borrowToken,
        uint256 repayAmount,
        SwapperLib.Swap memory swapData
    ) internal {
        bytes memory params = abi.encode(borrowToken, repayAmount, swapData);

        if (address(borrowToken) == cether) {
            CEther(payable(address(collateral)))
                .redeemUnderlyingForPositionFolding(
                    msg.sender,
                    collateralAmount,
                    params
                );
        } else {
            CErc20(address(collateral)).redeemUnderlyingForPositionFolding(
                msg.sender,
                collateralAmount,
                params
            );
        }
    }

    function onRedeem(
        address collateral,
        address redeemer,
        uint256 amount,
        bytes calldata params
    ) external override {
        (bool isListed, ) = lendtroller.getIsMarkets(collateral);
        require(
            isListed && msg.sender == collateral,
            "PositionFolding: UNAUTHORIZED"
        );

        (
            CToken borrowToken,
            uint256 repayAmount,
            SwapperLib.Swap memory swapData
        ) = abi.decode(params, (CToken, uint256, SwapperLib.Swap));

        // swap collateral token to borrow token
        address collateralUnderlying;
        if (collateral == cether) {
            collateralUnderlying = ETH;
            require(
                address(this).balance >= amount,
                "PositionFolding: invalid amount"
            );
        } else {
            collateralUnderlying = CErc20(collateral).underlying();
            require(
                IERC20(collateralUnderlying).balanceOf(address(this)) >=
                    amount,
                "PositionFolding: invalid amount"
            );
        }

        if (collateral != address(borrowToken)) {
            if (collateral == cether) {
                collateralUnderlying = weth;
                IWETH(weth).deposit{ value: amount }(amount);
            }

            if (swapData.call.length > 0) {
                SwapperLib.swap(
                    swapData,
                    ICentralRegistry(centralRegistry).priceRouter(),
                    SLIPPAGE
                );
            }
        }

        // repay debt
        address borrowUnderlying;
        uint256 remaining;
        if (address(borrowToken) == cether) {
            borrowUnderlying = ETH;
            remaining = address(this).balance - repayAmount;
            CEther(payable(address(borrowToken))).repayBorrowBehalf{
                value: repayAmount
            }(redeemer);

            if (remaining > 0) {
                // remaining balance back to collateral
                CEther(payable(address(borrowToken))).mintFor{
                    value: remaining
                }(redeemer);
            }
        } else {
            borrowUnderlying = CErc20(address(borrowToken)).underlying();
            remaining =
                IERC20(borrowUnderlying).balanceOf(address(this)) -
                repayAmount;
            SwapperLib.approveTokenIfNeeded(
                borrowUnderlying,
                address(borrowToken),
                repayAmount + remaining
            );
            CErc20(address(borrowToken)).repayBorrowBehalf(
                redeemer,
                repayAmount
            );

            if (remaining > 0) {
                // remaining balance back to collateral
                CErc20(address(borrowToken)).mintFor(remaining, redeemer);
            }
        }
    }
}
