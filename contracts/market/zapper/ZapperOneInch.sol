//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/token/collateral/CErc20.sol";
import "contracts/interfaces/external/curve/ICurve.sol";
import "contracts/interfaces/IWETH.sol";

contract ZapperOneInch {
    using SafeERC20 for IERC20;

    address public immutable lendtroller;
    address public immutable oneInchRouter;
    address public immutable weth;
    address public constant ETH = address(0);

    constructor(
        address _lendtroller,
        address _oneInchRouter,
        address _weth
    ) {
        lendtroller = _lendtroller;
        oneInchRouter = _oneInchRouter;
        weth = _weth;
    }

    /**
     * @dev Deposit inputToken and enter curvance
     * @param cToken The curvance deposit token address
     * @param inputToken The input token address
     * @param inputAmount The amount to deposit
     * @param lpMinter The minter address of Curve LP
     * @param lpToken The Curve LP token address
     * @param lpMinOutAmount The minimum output amount
     * @param tokens The underlying coins of curve LP token
     * @param tokenSwaps The swap aggregation data for OneInch
     * @return cTokenOutAmount The output amount
     */
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
            inputToken = weth;
            IWETH(weth).deposit{ value: inputAmount }(inputAmount);
        } else {
            IERC20(inputToken).safeTransferFrom(
                msg.sender,
                address(this),
                inputAmount
            );
        }

        // check valid cToken
        (bool isListed, , ) = Lendtroller(lendtroller).getIsMarkets(cToken);
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
        uint256 lpOutAmount = _enterCurve(
            lpMinter,
            lpToken,
            tokens,
            lpMinOutAmount
        );

        // enter curvance
        cTokenOutAmount = _enterCurvance(cToken, lpToken, lpOutAmount);

        // transfer cToken back to user
        IERC20(cToken).safeTransfer(msg.sender, cTokenOutAmount);
    }

    /**
     * @dev Swap input token via OneInch
     * @param _inputToken The input token address
     * @param _callData The swap aggregation data for OneInch
     */
    function _swapViaOneInch(address _inputToken, bytes memory _callData)
        private
    {
        _approveTokenIfNeeded(_inputToken, address(oneInchRouter));

        (bool success, bytes memory retData) = oneInchRouter.call(_callData);

        propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
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

    /**
     * @dev Enter curvance
     * @param lpMinter The minter address of Curve LP
     * @param lpToken The Curve LP token address
     * @param tokens The underlying coin addresses of Curve LP
     * @param lpMinOutAmount The minimum output amount
     */
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
                ICurveSwap(lpMinter).add_liquidity{ value: _getBalance(ETH) }(
                    amounts,
                    0
                );
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        } else if (numTokens == 3) {
            uint256[3] memory amounts;
            amounts[0] = _getBalance(tokens[0]);
            amounts[1] = _getBalance(tokens[1]);
            amounts[2] = _getBalance(tokens[2]);
            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{ value: _getBalance(ETH) }(
                    amounts,
                    0
                );
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        } else {
            uint256[2] memory amounts;
            amounts[0] = _getBalance(tokens[0]);
            amounts[1] = _getBalance(tokens[1]);

            if (hasETH) {
                ICurveSwap(lpMinter).add_liquidity{ value: _getBalance(ETH) }(
                    amounts,
                    0
                );
            } else {
                ICurveSwap(lpMinter).add_liquidity(amounts, 0);
            }
        }

        // check min out amount
        lpOutAmount = IERC20(lpToken).balanceOf(address(this));
        require(
            lpOutAmount >= lpMinOutAmount,
            "Received less than lpMinOutAmount"
        );
    }

    /**
     * @dev Get token balance of this contract
     * @param token The token address
     */
    function _getBalance(address token) private view returns (uint256) {
        if (token == ETH) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @dev Enter curvance
     * @param cToken The curvance deposit token address
     * @param lpToken The Curve LP token address
     * @param amount The amount to deposit
     * @return out The output amount
     */
    function _enterCurvance(
        address cToken,
        address lpToken,
        uint256 amount
    ) private returns (uint256 out) {
        // approve lp token
        _approveTokenIfNeeded(lpToken, cToken);

        // enter curvance
        require(CErc20(cToken).mint(amount), "curvance");

        out = _getBalance(cToken);
    }
}
