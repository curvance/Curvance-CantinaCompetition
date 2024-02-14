// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Zapper } from "contracts/market/zapper/Zapper.sol";
import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { CommonLib } from "contracts/libraries/CommonLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";

contract ZapperSimple is ReentrancyGuard {
    /// CONSTANTS ///

    IMarketManager public immutable marketManager; // MarketManager linked
    address public immutable WETH; // Address of WETH
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// ERRORS ///

    error ZapperSimple__ExecutionError();
    error ZapperSimple__InvalidCentralRegistry();
    error ZapperSimple__MarketManagerIsNotLendingMarket();
    error ZapperSimple__Unauthorized();
    error ZapperSimple__InsufficientToRepay();
    error ZapperSimple__InvalidZapper(address invalidZapper);

    /// CONSTRUCTOR ///

    receive() external payable {}

    constructor(
        ICentralRegistry centralRegistry_,
        address marketManager_,
        address WETH_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert ZapperSimple__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        if (!centralRegistry.isMarketManager(marketManager_)) {
            revert ZapperSimple__MarketManagerIsNotLendingMarket();
        }

        marketManager = IMarketManager(marketManager_);
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    function zapAndDeposit(
        SwapperLib.ZapperCall memory zapperCall,
        address cToken,
        address recipient
    ) external payable returns (uint256) {
        if (CommonLib.isETH(zapperCall.inputToken)) {
            if (zapperCall.inputAmount != msg.value) {
                revert ZapperSimple__ExecutionError();
            }
        } else {
            SafeTransferLib.safeTransferFrom(
                zapperCall.inputToken,
                msg.sender,
                address(this),
                zapperCall.inputAmount
            );
        }

        if (!centralRegistry.isZapper(zapperCall.target)) {
            revert ZapperSimple__InvalidZapper(zapperCall.target);
        }

        SwapperLib.zap(zapperCall);

        return _enterCurvance(cToken, recipient);
    }

    function swapAndRepay(
        SwapperLib.Swap memory swapperData,
        address dToken,
        uint256 repayAmount,
        address recipient
    ) external payable {
        if (CommonLib.isETH(swapperData.inputToken)) {
            if (swapperData.inputAmount != msg.value) {
                revert ZapperSimple__ExecutionError();
            }
        } else {
            SafeTransferLib.safeTransferFrom(
                swapperData.inputToken,
                msg.sender,
                address(this),
                swapperData.inputAmount
            );
        }

        if (!centralRegistry.isSwapper(swapperData.target)) {
            revert ZapperSimple__InvalidZapper(swapperData.target);
        }

        SwapperLib.swap(centralRegistry, swapperData);

        address dTokenUnderlying = DToken(dToken).underlying();
        uint256 balance = IERC20(dTokenUnderlying).balanceOf(address(this));
        if (balance < repayAmount) {
            revert ZapperSimple__InsufficientToRepay();
        }

        SwapperLib._approveTokenIfNeeded(
            dTokenUnderlying,
            address(dToken),
            repayAmount
        );
        DToken(dToken).repayFor(recipient, repayAmount);
        SwapperLib._removeApprovalIfNeeded(dTokenUnderlying, address(dToken));

        if (balance > repayAmount) {
            // transfer token back to user
            _transferOut(dTokenUnderlying, recipient, balance - repayAmount);
        }
    }

    /// @dev Enter curvance
    /// @param cToken The curvance deposit token address
    /// @param recipient The recipient address
    /// @return The output amount
    function _enterCurvance(
        address cToken,
        address recipient
    ) private returns (uint256) {
        // check valid cToken
        if (!marketManager.isListed(cToken)) {
            revert ZapperSimple__Unauthorized();
        }

        address cTokenUnderlying = CTokenPrimitive(cToken).underlying();
        uint256 balance = IERC20(cTokenUnderlying).balanceOf(address(this));

        // approve lp token
        SwapperLib._approveTokenIfNeeded(cTokenUnderlying, cToken, balance);

        uint256 priorBalance = IERC20(cToken).balanceOf(recipient);

        // enter curvance
        if (CTokenPrimitive(cToken).deposit(balance, recipient) == 0) {
            revert ZapperSimple__ExecutionError();
        }

        SwapperLib._removeApprovalIfNeeded(cTokenUnderlying, cToken);

        return IERC20(cToken).balanceOf(recipient) - priorBalance;
    }

    function _transferOut(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (CommonLib.isETH(token)) {
            SafeTransferLib.forceSafeTransferETH(recipient, amount);
        } else {
            SafeTransferLib.safeTransfer(token, recipient, amount);
        }
    }
}
