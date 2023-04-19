// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { IPositionFolding } from "./IPositionFolding.sol";
import { Comptroller } from "../compound/Comptroller/Comptroller.sol";
import { PriceOracle } from "../compound/Oracle/PriceOracle.sol";
import { CToken } from "../compound/Token/CToken.sol";
import { CEther } from "../compound/Token/CEther.sol";
import { CErc20 } from "../compound/Token/CErc20.sol";
import { IWETH } from "../zapper/IWETH.sol";

contract PositionFolding is ReentrancyGuard, IPositionFolding {
    using SafeERC20 for IERC20;

    struct Swap {
        address target;
        bytes call;
    }

    uint256 public constant MAX_LEVERAGE = 9000; // 0.9
    uint256 public constant DENOMINATOR = 10000;
    address public constant ETH = address(0);

    Comptroller public comptroller;
    PriceOracle public oracle;
    address public cether;
    address public weth;

    receive() external payable {}

    constructor(address _comptroller, address _oracle, address _cether, address _weth) ReentrancyGuard() {
        comptroller = Comptroller(_comptroller);
        oracle = PriceOracle(_oracle);
        cether = _cether;
        weth = _weth;
    }

    function queryAmountToBorrowForLeverageMax(address user, CToken borrowToken) public view returns (uint256) {
        (uint256 sumCollateral, uint256 maxBorrow, uint256 sumBorrow) = comptroller.getAccountPosition(user);
        uint256 maxLeverage = ((sumCollateral - sumBorrow) * MAX_LEVERAGE * sumCollateral) /
            (sumCollateral - maxBorrow) /
            DENOMINATOR -
            sumCollateral;

        return ((maxLeverage - sumBorrow) * 1e18) / oracle.getUnderlyingPrice(borrowToken);
    }

    function leverageMax(CToken borrowToken, CToken collateral, Swap memory swapData) external {
        uint256 amountToBorrow = queryAmountToBorrowForLeverageMax(msg.sender, borrowToken);

        bytes memory params = abi.encode(collateral, swapData);

        if (address(borrowToken) == cether) {
            CEther(payable(address(borrowToken))).borrowForPositionFolding(msg.sender, amountToBorrow, params);
        } else {
            CErc20(address(borrowToken)).borrowForPositionFolding(msg.sender, amountToBorrow, params);
        }
    }

    function onBorrow(address borrowToken, address borrower, uint256 amount, bytes memory params) external override {
        (bool isListed, , ) = Comptroller(comptroller).getIsMarkets(borrowToken);
        require(isListed && msg.sender == borrowToken, "unauthorized");

        (CToken collateral, Swap memory swapData) = abi.decode(params, (CToken, Swap));

        address borrowUnderlying;
        if (borrowToken == cether) {
            borrowUnderlying = ETH;
            require(address(this).balance == amount, "invalid amount");
        } else {
            borrowUnderlying = CErc20(borrowToken).underlying();
            require(IERC20(borrowUnderlying).balanceOf(address(this)) == amount, "invalid amount");
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
            address collateralUnderlying = CErc20(borrowToken).underlying();
            uint256 collateralAmount = IERC20(collateralUnderlying).balanceOf(address(this));
            _approveTokenIfNeeded(collateralUnderlying, address(collateral));
            CErc20(address(collateral)).mintFor(collateralAmount, borrower);
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
