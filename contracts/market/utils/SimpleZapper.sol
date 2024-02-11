// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

contract SimpleZapper is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Address of the Market Manager linked to this contract.
    IMarketManager public immutable marketManager;
    /// @notice The address of WETH on this chain.
    address public immutable WETH;

    /// ERRORS ///

    error SimpleZapper__ExecutionError();
    error SimpleZapper__InvalidCentralRegistry();
    error SimpleZapper__InvalidMarketManager();
    error SimpleZapper__Unauthorized();
    error SimpleZapper__InsufficientToRepay();
    error SimpleZapper__InvalidZapper(address invalidZapper);

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
            revert SimpleZapper__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        // Validate that `marketManager_` is configured as a market manager
        // inside the Central Registry.
        if (!centralRegistry.isMarketManager(marketManager_)) {
            revert SimpleZapper__InvalidMarketManager();
        }

        marketManager = IMarketManager(marketManager_);
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Zaps then deposits `zapperCall.inputToken`, a cToken
    ///         underlying, and enters into Curvance position,
    ///         for `recipient`.
    /// @param zapperCall Zap instruction data to execute the Zap.
    /// @param cToken The Curvance cToken address.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return The output amount received from Zapping.
    function zapAndDeposit(
        SwapperLib.ZapperCall memory zapperCall,
        address cToken,
        address recipient
    ) external payable nonReentrant returns (uint256) {
        if (CommonLib.isETH(zapperCall.inputToken)) {
            // Validate message has gas token attached.
            if (zapperCall.inputAmount != msg.value) {
                revert SimpleZapper__ExecutionError();
            }
        } else {
            SafeTransferLib.safeTransferFrom(
                zapperCall.inputToken,
                msg.sender,
                address(this),
                zapperCall.inputAmount
            );
        }

        // Validate that `cToken` is listed inside the associated
        // Market Manager.
        if (!marketManager.isListed(cToken)) {
            revert SimpleZapper__Unauthorized();
        }

        // Validate target contract is an approved Zapper.
        if (!centralRegistry.isZapper(zapperCall.target)) {
            revert SimpleZapper__InvalidZapper(zapperCall.target);
        }

        SwapperLib.zap(zapperCall);

        // Enter Curvance cToken position.
        return _enterCurvance(cToken, recipient);
    }

    /// @notice Swaps then repays dToken debt inside Curvance for `recipient`.
    /// @dev Sends any excess dToken underlying to `recipient`.
    /// @param swapperData Swap instruction data to execute the repayment.
    /// @param dToken The Curvance dToken address.
    /// @param repayAmount The amount of dToken underlying to be repaid.
    /// @param recipient Address that should have its outstanding debt repaid.
    /// @return The excess amount of dToken underlying that was returned
    ///         to `recipient`.
    function swapAndRepay(
        SwapperLib.Swap memory swapperData,
        address dToken,
        uint256 repayAmount,
        address recipient
    ) external payable nonReentrant returns (uint256) {
        if (CommonLib.isETH(swapperData.inputToken)) {
            // Validate message has gas token attached.
            if (swapperData.inputAmount != msg.value) {
                revert SimpleZapper__ExecutionError();
            }
        } else {
            SafeTransferLib.safeTransferFrom(
                swapperData.inputToken,
                msg.sender,
                address(this),
                swapperData.inputAmount
            );
        }

        // Validate that `dToken` is listed inside the associated
        // Market Manager.
        if (!marketManager.isListed(dToken)) {
            revert SimpleZapper__Unauthorized();
        }

        // Validate target contract is an approved swapper.
        if (!centralRegistry.isSwapper(swapperData.target)) {
            revert SimpleZapper__InvalidZapper(swapperData.target);
        }

        SwapperLib.swap(centralRegistry, swapperData);

        return _repayDebt(dToken, repayAmount, recipient);
    }

    /// @notice Deposits cToken underlying into Curvance cToken contract.
    /// @param cToken The Curvance cToken address.
    /// @param recipient Address that should receive Curvance cTokens.
    /// @return The output amount of cTokens received.
    function _enterCurvance(
        address cToken,
        address recipient
    ) private returns (uint256) {
        address cTokenUnderlying = CTokenPrimitive(cToken).underlying();
        uint256 balance = IERC20(cTokenUnderlying).balanceOf(address(this));

        // Approve cToken to take `inputToken`.
        SwapperLib._approveTokenIfNeeded(cTokenUnderlying, cToken, balance);

        uint256 priorBalance = IERC20(cToken).balanceOf(recipient);

        // Enter Curvance cToken position and make sure `recipient` got
        // cTokens.
        if (CTokenPrimitive(cToken).deposit(balance, recipient) == 0) {
            revert SimpleZapper__ExecutionError();
        }

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(cTokenUnderlying, cToken);

        // Bubble up how many cTokens `recipient` received.
        return IERC20(cToken).balanceOf(recipient) - priorBalance;
    }

    /// @notice Repays Curvance lenders dToken underlying owed on behalf
    ///         of `recipient`.
    /// @param dToken The Curvance dToken address.
    /// @param repayAmount The amount of dToken underlying to be repaid.
    /// @param recipient Address that should have outstanding debt repaid.
    /// @return outAmount The excess amount of dToken underlying that was
    ///                   returned to `recipient`.
    function _repayDebt(
        address dToken,
        uint256 repayAmount,
        address recipient
    ) internal returns (uint256 outAmount) {
        address dTokenUnderlying = DToken(dToken).underlying();
        // We never need to worry about this capturing other peoples balances
        // since the Zapper should never be holding any dToken underlying
        // itself.
        outAmount = IERC20(dTokenUnderlying).balanceOf(address(this));
        
        // Revert if the swap experienced too much slippage.
        if (outAmount < repayAmount) {
            revert SimpleZapper__InsufficientToRepay();
        }

        // Approve `dTokenUnderlying` to dToken contract, if necessary.
        SwapperLib._approveTokenIfNeeded(
            dTokenUnderlying,
            dToken,
            repayAmount
        );

        // Execute repayment of dToken debt.
        DToken(dToken).repayFor(recipient, repayAmount);

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(dTokenUnderlying, dToken);

        outAmount -= repayAmount;

        // Transfer any remaining `dTokenUnderlying` to `recipient`.
        if (outAmount > 0) {
            _transferToRecipient(
                dTokenUnderlying, 
                recipient, 
                outAmount
            );
        }
    }

    /// @notice Helper function for efficiently transferring tokens
    ///         to desired user.
    /// @param token The token to transfer to `recipient`, 
    ///              this can be the network gas token.
    /// @param recipient The user receiving `token`.
    /// @param amount The amount of `token` to be transferred to `recipient`.
    function _transferToRecipient(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (CommonLib.isETH(token)) {
            return SafeTransferLib.forceSafeTransferETH(recipient, amount);
        }
            
        SafeTransferLib.safeTransfer(token, recipient, amount);
    }
}
