// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CErc20, IERC20 } from "contracts/market/collateral/CErc20.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICurveSwap } from "contracts/interfaces/external/curve/ICurve.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";

contract ZapperGeneric {

    /// CONSTANTS ///
    ICentralRegistry public immutable centralRegistry;
    uint256 public constant SLIPPAGE = 500;
    address public constant ETH = address(0);
    ILendtroller public immutable lendtroller;
    address public immutable weth;

    constructor(
        ICentralRegistry _centralRegistry,
        address _lendtroller,
        address _weth
    ) {
        
        require(
            ERC165Checker.supportsInterface(
                address(_centralRegistry),
                type(ICentralRegistry).interfaceId
            ),
            "PositionFolding: Central Registry is invalid"
        );

        centralRegistry = _centralRegistry;

        require(centralRegistry.lendingMarket(_lendtroller), "PositionFolding: lendtroller is invalid");

        lendtroller = ILendtroller(_lendtroller);
        weth = _weth;
    }

    function isETH (address token) internal pure returns (bool) {
        /// We need to check against both null address and 0xEee because each protocol uses different implementations
        return token == address(0) || token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }

    /// @dev Deposit inputToken and enter curvance
    /// @param cToken The curvance deposit token address
    /// @param inputToken The input token address
    /// @param inputAmount The amount to deposit
    /// @param lpMinter The minter address of Curve LP
    /// @param lpToken The Curve LP token address
    /// @param lpMinOutAmount The minimum output amount
    /// @param tokens The underlying coins of curve LP token
    /// @param tokenSwaps The swap aggregation data
    /// @return cTokenOutAmount The output amount
    function curvanceIn(
        address cToken,
        address inputToken,
        uint256 inputAmount,
        address lpMinter,
        address lpToken,
        uint256 lpMinOutAmount,
        address[] calldata tokens,
        SwapperLib.Swap[] memory tokenSwaps,
        address recipient
    ) external payable returns (uint256 cTokenOutAmount) {
        if (isETH(inputToken)) {
            require(inputAmount == msg.value, "invalid amount");
            inputToken = weth;
            IWETH(weth).deposit{ value: inputAmount }(inputAmount);
        } else {
            SafeTransferLib.safeTransferFrom(
                inputToken,
                msg.sender,
                address(this),
                inputAmount
            );
        }

        // check valid cToken
        (bool isListed, ) = lendtroller.getIsMarkets(cToken);
        require(isListed, "invalid cToken address");
        // check cToken underlying
        require(CErc20(cToken).underlying() == lpToken, "invalid lp address");

        uint256 numTokenSwaps = tokenSwaps.length;

        // prepare tokens to mint LP
        for (uint256 i; i < numTokenSwaps; ++i) {
            SwapperLib.swap(
                tokenSwaps[i],
                ICentralRegistry(centralRegistry).priceRouter(),
                SLIPPAGE
            );
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
        SafeTransferLib.safeTransfer(cToken, recipient, cTokenOutAmount);
    }

    function curveOut(
        address lpMinter,
        address lpToken,
        uint256 lpAmount,
        address[] calldata tokens,
        SwapperLib.Swap[] memory tokenSwaps,
        address outputToken,
        uint256 minoutAmount,
        address recipient
    ) external returns (uint256 outAmount) {
        SafeTransferLib.safeTransferFrom(
            lpToken,
            msg.sender,
            address(this),
            lpAmount
        );
        _exitCurve(lpMinter, lpToken, tokens, lpAmount);

        uint256 numTokenSwaps = tokenSwaps.length;
        // prepare tokens to mint LP
        for (uint256 i; i < numTokenSwaps; ++i) {
            SwapperLib.swap(
                tokenSwaps[i],
                ICentralRegistry(centralRegistry).priceRouter(),
                SLIPPAGE
            );
        }

        outAmount = IERC20(outputToken).balanceOf(address(this));
        require(outAmount >= minoutAmount, "Received less than minOutAmount");

        // transfer token back to user
        SafeTransferLib.safeTransfer(outputToken, recipient, outAmount);
    }

    /// @dev Enter curvance
    /// @param lpMinter The minter address of Curve LP
    /// @param lpToken The Curve LP token address
    /// @param tokens The underlying coin addresses of Curve LP
    /// @param lpMinOutAmount The minimum output amount
    function _enterCurve(
        address lpMinter,
        address lpToken,
        address[] memory tokens,
        uint256 lpMinOutAmount
    ) private returns (uint256 lpOutAmount) {
        bool hasETH;

        uint256 numTokens = tokens.length;

        uint256[] memory balances = new uint256[](numTokens);
        // approve tokens
        for (uint256 i; i < numTokens; ++i) {
            balances[i] = _getBalance(tokens[i]);
            SwapperLib.approveTokenIfNeeded(tokens[i], lpMinter, balances[i]);
            if (isETH(tokens[i])) {
                hasETH = true;
            }
        }

        // enter curve lp minter
        if (numTokens == 4) {
            uint256[4] memory amounts;
            amounts[0] = balances[0];
            amounts[1] = balances[1];
            amounts[2] = balances[2];
            amounts[3] = balances[3];
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
            amounts[0] = balances[0];
            amounts[1] = balances[1];
            amounts[2] = balances[2];
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
            amounts[0] = balances[0];
            amounts[1] = balances[1];

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

    /// @dev Exit curvance
    /// @param lpMinter The minter address of Curve LP
    /// @param lpToken The Curve LP token address
    /// @param tokens The underlying coin addresses of Curve LP
    /// @param lpAmount The LP amount to exit
    function _exitCurve(
        address lpMinter,
        address lpToken,
        address[] memory tokens,
        uint256 lpAmount
    ) private {
        // approve lp token
        SwapperLib.approveTokenIfNeeded(lpToken, lpMinter, lpAmount);

        uint256 numTokens = tokens.length;
        // enter curve lp minter
        if (numTokens == 4) {
            uint256[4] memory amounts;
            ICurveSwap(lpMinter).remove_liquidity(lpAmount, amounts);
        } else if (numTokens == 3) {
            uint256[3] memory amounts;
            ICurveSwap(lpMinter).remove_liquidity(lpAmount, amounts);
        } else {
            uint256[2] memory amounts;
            ICurveSwap(lpMinter).remove_liquidity(lpAmount, amounts);
        }
    }

    /// @dev Get token balance of this contract
    /// @param token The token address
    function _getBalance(address token) private view returns (uint256) {
        if (isETH(token)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /// @dev Enter curvance
    /// @param cToken The curvance deposit token address
    /// @param lpToken The Curve LP token address
    /// @param amount The amount to deposit
    /// @return out The output amount
    function _enterCurvance(
        address cToken,
        address lpToken,
        uint256 amount
    ) private returns (uint256 out) {
        // approve lp token
        SwapperLib.approveTokenIfNeeded(lpToken, cToken, amount);

        // enter curvance
        require(CErc20(cToken).mint(amount), "curvance");

        out = _getBalance(cToken);
    }
}
