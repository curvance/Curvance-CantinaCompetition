// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { IPositionFolding } from "./IPositionFolding.sol";
import { Lendtroller } from "../lendingMarket/Lendtroller/Lendtroller.sol";
import { PriceOracle } from "../lendingMarket/Oracle/PriceOracle.sol";
import { CToken } from "../lendingMarket/Token/CToken.sol";
import { CEther } from "../lendingMarket/Token/CEther.sol";
import { CErc20 } from "../lendingMarket/Token/CErc20.sol";
import { IWETH } from "../zapper/IWETH.sol";

contract PositionFolding is ReentrancyGuard, IPositionFolding {
    using SafeERC20 for IERC20;

    struct Swap {
        address target;
        bytes call;
    }

    uint256 public constant MAX_LEVERAGE = 9900; // 0.99
    uint256 public constant DENOMINATOR = 10000;
    address public constant ETH = address(0);

    Lendtroller public lendtroller;
    PriceOracle public oracle;
    address public cether;
    address public weth;

    receive() external payable {}

    constructor(address _lendtroller, address _oracle, address _cether, address _weth) ReentrancyGuard() {
        lendtroller = Lendtroller(_lendtroller);
        oracle = PriceOracle(_oracle);
        cether = _cether;
        weth = _weth;
    }

    modifier checkSlippage(address user, uint256 slippage) {
        (uint256 sumCollateralBefore, , uint256 sumBorrowBefore) = lendtroller.getAccountPosition(user);
        uint256 userValueBefore = sumCollateralBefore - sumBorrowBefore;

        _;

        (uint256 sumCollateral, , uint256 sumBorrow) = lendtroller.getAccountPosition(user);
        uint256 userValue = sumCollateral - sumBorrow;

        uint256 diff = userValue > userValueBefore ? userValue - userValueBefore : userValueBefore - userValue;
        require(diff < (userValueBefore * slippage) / DENOMINATOR, "PositionFolding: slippage");
    }

    function queryAmountToBorrowForLeverageMax(address user, CToken borrowToken) public view returns (uint256) {
        (uint256 sumCollateral, uint256 maxBorrow, uint256 sumBorrow) = lendtroller.getAccountPosition(user);
        uint256 maxLeverage = ((sumCollateral - sumBorrow) * MAX_LEVERAGE * sumCollateral) /
            (sumCollateral - maxBorrow) /
            DENOMINATOR -
            sumCollateral;

        return ((maxLeverage - sumBorrow) * 1e18) / oracle.getUnderlyingPrice(borrowToken);
    }

    function leverageMax(
        CToken borrowToken,
        CToken collateral,
        Swap memory swapData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        uint256 amountToBorrow = queryAmountToBorrowForLeverageMax(msg.sender, borrowToken);
        _leverage(borrowToken, amountToBorrow, collateral, swapData);
    }

    function leverage(
        CToken borrowToken,
        uint256 borrowAmount,
        CToken collateral,
        Swap memory swapData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        uint256 maxBorrowAmount = queryAmountToBorrowForLeverageMax(msg.sender, borrowToken);
        require(borrowAmount <= maxBorrowAmount, "PositionFolding: exceeded maximum borrow amount");
        _leverage(borrowToken, borrowAmount, collateral, swapData);
    }

    function batchLeverage(
        CToken[] memory borrowTokens,
        uint256[] memory borrowAmounts,
        CToken[] memory collateralTokens,
        Swap[] memory swapData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) {
        uint256 length = borrowTokens.length;
        require(
            borrowAmounts.length == length && collateralTokens.length == length && swapData.length == length,
            "PositionFolding: invalid array length"
        );
        for (uint256 i = 0; i < length; ++i) {
            uint256 maxBorrowAmount = queryAmountToBorrowForLeverageMax(msg.sender, borrowTokens[i]);
            require(borrowAmounts[i] <= maxBorrowAmount, "PositionFolding: exceeded maximum borrow amount");
            _leverage(borrowTokens[i], borrowAmounts[i], collateralTokens[i], swapData[i]);
        }
    }

    function _leverage(CToken borrowToken, uint256 borrowAmount, CToken collateral, Swap memory swapData) internal {
        bytes memory params = abi.encode(collateral, swapData);

        if (address(borrowToken) == cether) {
            CEther(payable(address(borrowToken))).borrowForPositionFolding(msg.sender, borrowAmount, params);
        } else {
            CErc20(address(borrowToken)).borrowForPositionFolding(msg.sender, borrowAmount, params);
        }
    }

    function onBorrow(address borrowToken, address borrower, uint256 amount, bytes memory params) external override {
        (bool isListed, , ) = Lendtroller(lendtroller).getIsMarkets(borrowToken);
        require(isListed && msg.sender == borrowToken, "PositionFolding: UNAUTHORIZED");

        (CToken collateral, Swap memory swapData) = abi.decode(params, (CToken, Swap));

        address borrowUnderlying;
        if (borrowToken == cether) {
            borrowUnderlying = ETH;
            require(address(this).balance >= amount, "PositionFolding: invalid amount");
        } else {
            borrowUnderlying = CErc20(borrowToken).underlying();
            require(IERC20(borrowUnderlying).balanceOf(address(this)) >= amount, "PositionFolding: invalid amount");
        }

        if (borrowToken != address(collateral)) {
            if (borrowToken == cether) {
                borrowUnderlying = weth;
                IWETH(weth).deposit{ value: amount }(amount);
            }

            if (swapData.call.length > 0) {
                _swap(borrowUnderlying, swapData);
            }
        }

        if (address(collateral) == cether) {
            CEther(payable(address(collateral))).mintFor{ value: address(this).balance }(borrower);
        } else {
            address collateralUnderlying = CErc20(address(collateral)).underlying();
            uint256 collateralAmount = IERC20(collateralUnderlying).balanceOf(address(this));
            _approveTokenIfNeeded(collateralUnderlying, address(collateral));
            CErc20(address(collateral)).mintFor(collateralAmount, borrower);
        }
    }

    function deleverage(
        CToken collateral,
        uint256 collateralAmount,
        CToken borrowToken,
        uint256 repayAmount,
        Swap memory swapData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        _deleverage(collateral, collateralAmount, borrowToken, repayAmount, swapData);
    }

    function batchDeleverage(
        CToken[] memory collateralTokens,
        uint256[] memory collateralAmount,
        CToken[] memory borrowTokens,
        uint256[] memory repayAmounts,
        Swap[] memory swapData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) {
        uint256 length = collateralTokens.length;
        require(
            collateralAmount.length == length &&
                borrowTokens.length == length &&
                repayAmounts.length == length &&
                swapData.length == length,
            "PositionFolding: invalid array length"
        );
        for (uint256 i = 0; i < length; ++i) {
            _deleverage(collateralTokens[i], collateralAmount[i], borrowTokens[i], repayAmounts[i], swapData[i]);
        }
    }

    function _deleverage(
        CToken collateral,
        uint256 collateralAmount,
        CToken borrowToken,
        uint256 repayAmount,
        Swap memory swapData
    ) internal {
        bytes memory params = abi.encode(borrowToken, repayAmount, swapData);

        if (address(borrowToken) == cether) {
            CEther(payable(address(collateral))).redeemUnderlyingForPositionFolding(
                msg.sender,
                collateralAmount,
                params
            );
        } else {
            CErc20(address(collateral)).redeemUnderlyingForPositionFolding(msg.sender, collateralAmount, params);
        }
    }

    function onRedeem(address collateral, address redeemer, uint256 amount, bytes memory params) external override {
        (bool isListed, , ) = Lendtroller(lendtroller).getIsMarkets(collateral);
        require(isListed && msg.sender == collateral, "PositionFolding: UNAUTHORIZED");

        (CToken borrowToken, uint256 repayAmount, Swap memory swapData) = abi.decode(params, (CToken, uint256, Swap));

        // swap collateral token to borrow token
        address collateralUnderlying;
        if (collateral == cether) {
            collateralUnderlying = ETH;
            require(address(this).balance >= amount, "PositionFolding: invalid amount");
        } else {
            collateralUnderlying = CErc20(collateral).underlying();
            require(IERC20(collateralUnderlying).balanceOf(address(this)) >= amount, "PositionFolding: invalid amount");
        }

        if (collateral != address(borrowToken)) {
            if (collateral == cether) {
                collateralUnderlying = weth;
                IWETH(weth).deposit{ value: amount }(amount);
            }

            if (swapData.call.length > 0) {
                _swap(collateralUnderlying, swapData);
            }
        }

        // repay debt
        address borrowUnderlying;
        uint256 remaining;
        if (address(borrowToken) == cether) {
            borrowUnderlying = ETH;
            remaining = address(this).balance - repayAmount;
            CEther(payable(address(borrowToken))).repayBorrowBehalf{ value: repayAmount }(redeemer);

            if (remaining > 0) {
                // remaining balance back to collateral
                CEther(payable(address(borrowToken))).mintFor{ value: remaining }(redeemer);
            }
        } else {
            borrowUnderlying = CErc20(address(borrowToken)).underlying();
            remaining = IERC20(borrowUnderlying).balanceOf(address(this)) - repayAmount;
            _approveTokenIfNeeded(borrowUnderlying, address(borrowToken));
            CErc20(address(borrowToken)).repayBorrowBehalf(redeemer, repayAmount);

            if (remaining > 0) {
                // remaining balance back to collateral
                CErc20(address(borrowToken)).mintFor(remaining, redeemer);
            }
        }
    }

    /**
     * @dev Swap input token
     * @param _inputToken The input asset address
     * @param _swapData The swap aggregation data
     */
    function _swap(address _inputToken, Swap memory _swapData) private {
        _approveTokenIfNeeded(_inputToken, address(_swapData.target));

        (bool success, bytes memory retData) = _swapData.target.call(_swapData.call);

        propagateError(success, retData, "swap");

        require(success == true, "calling swap got an error");
    }

    /**
     * @dev Approve token if needed
     * @param _token The token address
     * @param _spender The spender address
     */
    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint256).max);
        }
    }

    /**
     * @dev Propagate error message
     * @param success If transaction is successful
     * @param data The transaction result data
     * @param errorMessage The custom error message
     */
    function propagateError(bool success, bytes memory data, string memory errorMessage) public pure {
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }
}
