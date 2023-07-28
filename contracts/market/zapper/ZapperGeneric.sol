// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { CommonLib } from "contracts/market/zapper/protocols/CommonLib.sol";
import { CurveLib } from "contracts/market/zapper/protocols/CurveLib.sol";
import { BalancerLib } from "contracts/market/zapper/protocols/BalancerLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CToken, IERC20 } from "contracts/market/collateral/CToken.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICurveSwap } from "contracts/interfaces/external/curve/ICurve.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ZapperGeneric {
    
    /// CONSTANTS ///

    uint256 public constant SLIPPAGE = 500;
    address public constant ETH = address(0);
    ICentralRegistry public immutable centralRegistry;
    ILendtroller public immutable lendtroller;
    address public immutable weth;

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address lendtroller_,
        address weth_
    ) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "PositionFolding: invalid central registry"
        );

        centralRegistry = centralRegistry_;

        require(
            centralRegistry.lendingMarket(lendtroller_),
            "PositionFolding: lendtroller is invalid"
        );

        lendtroller = ILendtroller(lendtroller_);
        weth = weth_;
    }

    /// EXTERNAL FUNCTIONS ///

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
    function curveInForCurvance(
        address cToken,
        address inputToken,
        uint256 inputAmount,
        SwapperLib.Swap[] memory tokenSwaps,
        address lpMinter,
        address lpToken,
        uint256 lpMinOutAmount,
        address[] calldata tokens,
        address recipient
    ) external payable returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            cToken,
            inputToken,
            inputAmount,
            tokenSwaps,
            lpToken
        );

        // enter curve
        uint256 lpOutAmount = CurveLib.enterCurve(
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
        CurveLib.exitCurve(lpMinter, lpToken, tokens, lpAmount);

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

    /// @dev Deposit inputToken and enter curvance
    /// @param cToken The curvance deposit token address
    /// @param inputToken The input token address
    /// @param inputAmount The amount to deposit
    /// @param balancerVault The balancer vault address
    /// @param balancerPoolId The balancer pool ID
    /// @param lpToken The Curve LP token address
    /// @param lpMinOutAmount The minimum output amount
    /// @param tokens The underlying coins of curve LP token
    /// @param tokenSwaps The swap aggregation data
    /// @return cTokenOutAmount The output amount
    function balancerInForCurvance(
        address cToken,
        address inputToken,
        uint256 inputAmount,
        SwapperLib.Swap[] memory tokenSwaps,
        address balancerVault,
        bytes32 balancerPoolId,
        address lpToken,
        uint256 lpMinOutAmount,
        address[] calldata tokens,
        address recipient
    ) external payable returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            cToken,
            inputToken,
            inputAmount,
            tokenSwaps,
            lpToken
        );

        // enter balancer
        uint256 lpOutAmount = BalancerLib.enterBalancer(
            balancerVault,
            balancerPoolId,
            lpToken,
            tokens,
            lpMinOutAmount
        );

        // enter curvance
        cTokenOutAmount = _enterCurvance(cToken, lpToken, lpOutAmount);

        // transfer cToken back to user
        SafeTransferLib.safeTransfer(cToken, recipient, cTokenOutAmount);
    }

    function balancerOut(
        address balancerVault,
        bytes32 balancerPoolId,
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
        BalancerLib.exitBalancer(
            balancerVault,
            balancerPoolId,
            lpToken,
            tokens,
            lpAmount
        );

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

    /// @dev Deposit inputToken and enter curvance
    /// @param cToken The curvance deposit token address
    /// @param inputToken The input token address
    /// @param inputAmount The amount to deposit
    /// @param tokenSwaps The swap aggregation data
    /// @param lpToken The Curve LP token address
    function _swapForUnderlyings(
        address cToken,
        address inputToken,
        uint256 inputAmount,
        SwapperLib.Swap[] memory tokenSwaps,
        address lpToken
    ) private {
        if (CommonLib.isETH(inputToken)) {
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
        require(CToken(cToken).underlying() == lpToken, "invalid lp address");

        uint256 numTokenSwaps = tokenSwaps.length;

        // prepare tokens to mint LP
        for (uint256 i; i < numTokenSwaps; ++i) {
            SwapperLib.swap(
                tokenSwaps[i],
                ICentralRegistry(centralRegistry).priceRouter(),
                SLIPPAGE
            );
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
        require(CToken(cToken).mint(amount), "curvance");

        out = CommonLib.getTokenBalance(cToken);
    }
}
