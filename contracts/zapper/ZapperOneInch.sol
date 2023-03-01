//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../compound/Comptroller/Comptroller.sol";
import "../compound/Token/CErc20.sol";
import "./ICurve.sol";

contract ZapperOneInch {
    using SafeERC20 for IERC20;

    address public immutable comptroller;
    address public immutable oneInchRouter;
    address public immutable WETH;
    address public constant ETH = address(0);

    constructor(
        address _comptroller,
        address _oneInchRouter,
        address _WETH
    ) {
        comptroller = _comptroller;
        oneInchRouter = _oneInchRouter;
        WETH = _WETH;
    }

    function curvanceIn(
        address cToken,
        address inputToken,
        uint256 inputAmount,
        address lpMinter,
        address lpToken,
        uint256 lpMinOutAmount,
        address[] memory tokens,
        bytes[] memory tokenSwaps
    ) external payable returns (uint256 cTokenOutAmount) {
        if (inputToken == ETH) {
            require(inputAmount == msg.value, "invalid amount");
        } else {
            IERC20(inputToken).safeTransferFrom(msg.sender, address(this), inputAmount);
        }

        // check valid cToken
        (bool isListed, , ) = Comptroller(comptroller).getIsMarkets(cToken);
        require(isListed, "invalid cToken address");
        // check cToken underlying
        require(CErc20(cToken).underlying() == lpToken, "invalid lp address");

        // prepare tokens to mint LP
        for (uint256 i = 0; i < tokens.length; i++) {
            // swap input token to underlying token
            if (tokens[i] != inputToken && tokenSwaps[i].length > 0) {
                _swapViaOneInch(inputToken, tokenSwaps[i]);
            }
        }

        // enter curve
        uint256 lpOutAmount = _enterCurve(lpMinter, lpToken, tokens, lpMinOutAmount);

        // enter curvance
        cTokenOutAmount = _enterCurvance(cToken, lpToken, lpOutAmount);

        // transfer cToken back to user
        IERC20(cToken).safeTransfer(msg.sender, cTokenOutAmount);
    }

    function _swapViaOneInch(address _inputToken, bytes memory _callData) private {
        _approveTokenIfNeeded(_inputToken, address(oneInchRouter));

        (bool success, bytes memory retData) = oneInchRouter.call(_callData);

        propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
    }

    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint256).max);
        }
    }

    function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) public pure {
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function _enterCurve(
        address lpMinter,
        address lpToken,
        address[] memory tokens,
        uint256 lpMinOutAmount
    ) private returns (uint256 lpOutAmount) {
        bool hasETH = false;
        // approve tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            _approveTokenIfNeeded(tokens[i], lpMinter);
            if (tokens[i] == ETH) {
                hasETH = true;
            }
        }

        // enter curve lp minter
        uint256 numTokens = tokens.length;
        if (numTokens == 4) {
            uint256[4] memory amounts;
            amounts[0] = _getBalance(tokens[0]);
            amounts[1] = _getBalance(tokens[1]);
            amounts[2] = _getBalance(tokens[2]);
            amounts[3] = _getBalance(tokens[3]);
            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{ value: _getBalance(ETH) }(amounts, 0);
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        } else if (numTokens == 3) {
            uint256[3] memory amounts;
            amounts[0] = _getBalance(tokens[0]);
            amounts[1] = _getBalance(tokens[1]);
            amounts[2] = _getBalance(tokens[2]);
            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{ value: _getBalance(ETH) }(amounts, 0);
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        } else {
            uint256[2] memory amounts;
            amounts[0] = _getBalance(tokens[0]);
            amounts[1] = _getBalance(tokens[1]);

            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{ value: _getBalance(ETH) }(amounts, 0);
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        }

        // check min out amount
        lpOutAmount = IERC20(lpToken).balanceOf(address(this));
        require(lpOutAmount >= lpMinOutAmount, "Received less than lpMinOutAmount");
    }

    function _getBalance(address token) private view returns (uint256) {
        if (token == ETH) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    function _enterCurvance(
        address cToken,
        address lpToken,
        uint256 amount
    ) private returns (uint256) {
        // approve lp token
        _approveTokenIfNeeded(lpToken, cToken);

        // enter curvance
        CErc20(cToken).mint(amount);

        return _getBalance(cToken);
    }
}
