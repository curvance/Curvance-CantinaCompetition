// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { Delegable } from "contracts/libraries/Delegable.sol";
import { DENOMINATOR, WAD } from "contracts/libraries/Constants.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { IPositionFolding } from "contracts/interfaces/market/IPositionFolding.sol";

/// @dev The Curvance Position Folding contract enshrines actions that
///      usually would require multiple looped actions to facilitate,
///      namely leveraging a position up or deleveraging it for withdrawal.
///
///      CToken and DToken contracts facilitate these operations through
///      integration with Position Foldings callback functions. 
contract PositionFolding is IPositionFolding, Delegable, ERC165, ReentrancyGuard {
    /// TYPES ///

    /// @param borrowToken Address of dToken that will be borrowed from.
    /// @param borrowAmount The amount of underlying tokens from dToken
    ///                     that will be borrowed.
    /// @param collateralToken Address of cToken that will borrowed funds
    ///                        will be routed into.
    /// @param swapData Swapperlib swapping struct containing instructions
    ///                 on how to handle the necessary dToken swap
    ///                 to facilitate leveraging.
    /// @param zapperCall Swapperlib zapping struct containing instructions
    ///                   on how to handle the necessary cToken zap
    ///                   to facilitate leveraging.
    struct LeverageStruct {
        DToken borrowToken;
        uint256 borrowAmount;
        CTokenPrimitive collateralToken;
        SwapperLib.Swap swapData;
        SwapperLib.ZapperCall zapperCall;
    }

    /// @param collateralToken Address of cToken that will be routed into
    ///                        dToken underlying to repay debt.
    /// @param collateralAmount The amount of cTokens that will be
    ///                         deleveraged.
    /// @param borrowToken Address of dToken that will have its underlying
    ///                    token debt repaid.
    /// @param zapperCall Swapperlib zapping struct containing instructions
    ///                   on how to handle the necessary cToken outward zap
    ///                   to a single token (e.g. dToken underlying) to
    ///                   facilitate deleveraging.
    /// @param swapData Optional Swapperlib swapping struct containing
    ///                 instructions on how to handle zapping into dToken
    ///                 underlying to facilitate deleveraging.
    /// @param repayAmount The amount of underlying tokens from dToken that
    ///                    will be repaid.
    struct DeleverageStruct {
        CTokenPrimitive collateralToken;
        uint256 collateralAmount;
        DToken borrowToken;
        SwapperLib.ZapperCall zapperCall;
        SwapperLib.Swap swapData;
        uint256 repayAmount;
    }

    /// CONSTANTS ///

    /// @notice Maximum desired leverage output, we choose 99% of what is
    ///         possible to minimize reversion from things like price
    ///         fluctuations, swap fees, and oracle vs pool price divergence,
    ///         in basis points.
    /// @dev 9900 = 99% = 0.99.
    uint256 public constant MAX_LEVERAGE = 9900;

    /// @dev `bytes4(keccak256(bytes("PositionFolding__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x1d52945b;

    /// @notice Address of the Market Manager linked to this contract.
    IMarketManager public immutable marketManager;

    /// ERRORS ///

    error PositionFolding__Unauthorized();
    error PositionFolding__InvalidSlippage();
    error PositionFolding__InvalidCentralRegistry();
    error PositionFolding__InvalidMarketManager();
    error PositionFolding__InvalidSwapper(address invalidSwapper);
    error PositionFolding__InvalidParam();
    error PositionFolding__InvalidAmount();
    error PositionFolding__InvalidZapper(address invalidZapper);
    error PositionFolding__InvalidZapperParam();
    error PositionFolding__InvalidTokenPrice();
    error PositionFolding__ExceedsMaximumBorrowAmount(
        uint256 amount,
        uint256 maximum
    );

    /// MODIFIERS ///

    /// @dev Checks slippage on position folding prior and after
    ///      leverage/deleverage action, works similar to reentryguard
    ///      with pre and post checks.
    modifier checkSlippage(address account, uint256 slippage) {
        (uint256 collateralBefore, uint256 debtBefore) = marketManager
            .solvencyOf(account);
        uint256 liquidityBefore = collateralBefore - debtBefore;

        _;

        (uint256 sumCollateral, uint256 sumDebt) = marketManager.solvencyOf(
            account
        );

        uint256 liquidityAfter = sumCollateral - sumDebt;
        // If there was slippage, make sure its within slippage tolerance.
        if (liquidityBefore > liquidityAfter) {
            if (
                liquidityBefore - liquidityAfter >=
                (liquidityBefore * slippage) / DENOMINATOR
            ) {
                revert PositionFolding__InvalidSlippage();
            }
        }
    }

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address marketManager_
    ) Delegable(centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert PositionFolding__InvalidCentralRegistry();
        }

        // Validate that `marketManager_` is configured as a market manager
        // inside the Central Registry.
        if (!centralRegistry_.isMarketManager(marketManager_)) {
            revert PositionFolding__InvalidMarketManager();
        }

        marketManager = IMarketManager(marketManager_);
    }

    /// @notice Lightweight getter for any associated leverage fee.
    function getProtocolLeverageFee() public view returns (uint256) {
        return centralRegistry.protocolLeverageFee();
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Leverages an active Curvance position in favor of increasing
    ///         both collateral and debt inside the system.
    /// @dev Measures slippage through pre/post conditional slippage check
    ///      in `checkSlippage` modifier.
    /// @param leverageData Struct containing instructions on desired
    ///                     leverage action.
    /// @param slippage Slippage accepted by the user for execution of
    ///                 `leverageData` leverage action, in basis points.
    function leverage(
        LeverageStruct calldata leverageData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        _leverage(leverageData, msg.sender);
    }

    /// @notice Leverages an active Curvance position in favor of increasing
    ///         both collateral and debt inside the system, via delegation.
    /// @dev Measures slippage through pre/post conditional slippage check
    ///      in `checkSlippage` modifier.
    ///      NOTE: Be careful who you approve here!
    ///      The caller can select slippage, potentially causing loss of funds
    ///      if delegation is provided to a malicious party.
    /// @param leverageData Struct containing instructions on desired
    ///                     leverage action.
    /// @param account The account to leverage an active Curvance position
    ///                for.
    /// @param slippage Slippage accepted by the user for execution of
    ///                 `leverageData` leverage action, in basis points.
    function leverageFor(
        LeverageStruct calldata leverageData,
        address account,
        uint256 slippage
    ) external checkSlippage(account, slippage) nonReentrant {
        if (!_checkIsDelegate(account, msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _leverage(leverageData, account);
    }

    /// @notice Deleverages an active Curvance position in favor of decreasing
    ///         both collateral and debt inside the system.
    /// @dev Measures slippage through pre/post conditional slippage check
    ///      in `checkSlippage` modifier.
    ///      NOTE: Be careful who you approve here!
    ///      The caller can select slippage, potentially causing loss of funds
    ///      if delegation is provided to a malicious party.
    /// @param deleverageData Struct containing instructions on desired
    ///                       deleverage action.
    /// @param slippage Slippage accepted by the user for execution of
    ///                 `deleverageData` deleverage action, in basis points.
    function deleverage(
        DeleverageStruct calldata deleverageData,
        uint256 slippage
    ) external checkSlippage(msg.sender, slippage) nonReentrant {
        _deleverage(deleverageData, msg.sender);
    }

    /// @notice Deleverages an active Curvance position in favor of decreasing
    ///         both collateral and debt inside the system, via delegation.
    /// @dev Measures slippage through pre/post conditional slippage check
    ///      in `checkSlippage` modifier.
    /// @param deleverageData Struct containing instructions on desired
    ///                       deleverage action.
    /// @param account The account to deleverage an active Curvance position
    ///                for.
    /// @param slippage Slippage accepted by the user for execution of
    ///                 `deleverageData` deleverage action, in basis points.
    function deleverageFor(
        DeleverageStruct calldata deleverageData,
        address account,
        uint256 slippage
    ) external checkSlippage(account, slippage) nonReentrant {
        if (!_checkIsDelegate(account, msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _deleverage(deleverageData, account);
    }

    /// @notice Callback function to execute post borrow of
    ///         `borrowToken`'s underlying and swap it to deposit
    ///         new collateral for `borrower`.
    /// @dev Measures slippage after this callback validating that `borrower`
    ///      is still within acceptable liquidity requirements.
    /// @param borrowToken The borrow token borrowed from.
    /// @param borrower The account borrowing that will be swapped into
    ///                 collateral assets deposited into Curvance.
    /// @param borrowAmount The amount of `borrowToken`'s underlying borrowed.
    /// @param params Swap and deposit instructions.
    function onBorrow(
        address borrowToken,
        address borrower,
        uint256 borrowAmount,
        bytes calldata params
    ) external override {
        // Validate that the debt token itself is executing
        // the callback.
        if (msg.sender != borrowToken) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Validate the debt token is actually listed to this
        // Market Manager.
        if (!marketManager.isListed(borrowToken)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        LeverageStruct memory leverageData = abi.decode(
            params,
            (LeverageStruct)
        );

        if (
            borrowToken != address(leverageData.borrowToken) ||
            borrowAmount != leverageData.borrowAmount
        ) {
            revert PositionFolding__InvalidParam();
        }

        address borrowUnderlying = CTokenPrimitive(borrowToken).underlying();

        if (IERC20(borrowUnderlying).balanceOf(address(this)) < borrowAmount) {
            revert PositionFolding__InvalidAmount();
        }

        // Take protocol fee, if any.
        uint256 fee = (borrowAmount * getProtocolLeverageFee()) / WAD;
        if (fee > 0) {
            SafeTransferLib.safeTransfer(
                borrowUnderlying,
                centralRegistry.daoAddress(),
                fee
            );
        }

        // Check to make sure there is calldata attached to execute the swap.
        if (leverageData.swapData.call.length > 0) {
            // Validate that the target Swapper is approved inside Curvance.
            if (!centralRegistry.isSwapper(leverageData.swapData.target)) {
                revert PositionFolding__InvalidSwapper(
                    leverageData.swapData.target
                );
            }

            // Swap borrow underlying to Zapper input token.
            SwapperLib.swap(centralRegistry, leverageData.swapData);
        }

        // Prepare cToken underlying.
        SwapperLib.ZapperCall memory zapperCall = leverageData.zapperCall;

        // Check to make sure there is calldata attached to execute the zap.
        if (zapperCall.call.length > 0) {
            // Validate that the target Zapper is approved inside Curvance.
            if (!centralRegistry.isZapper(leverageData.zapperCall.target)) {
                revert PositionFolding__InvalidZapper(
                    leverageData.zapperCall.target
                );
            }

            // Execute Zap from `borrowToken` underlying into cToken
            // underlying.
            SwapperLib.zap(zapperCall);
        }

        // We do not need to check whether collateralToken is listed
        // or not as even if they found a way to input a malicious
        // token here the post conditional solvency check will revert
        // the whole operation.
        CTokenPrimitive collateralToken = leverageData.collateralToken;
        
        // Unwrap leverage instructions for collateral deposit.
        address collateralUnderlying = collateralToken.underlying();
        uint256 amount = IERC20(collateralUnderlying).balanceOf(address(this));

        // Approve `amount` of `collateralUnderlying` to cToken contract.
        SwapperLib._approveTokenIfNeeded(
            collateralUnderlying,
            address(collateralToken),
            amount
        );

        // Enter Curvance.
        collateralToken.depositAsCollateral(amount, borrower);

        uint256 remaining = IERC20(zapperCall.inputToken).balanceOf(
            address(this)
        );

        // Transfer remaining Zapper input token back to the user.
        if (remaining > 0) {
            SafeTransferLib.safeTransfer(
                zapperCall.inputToken,
                borrower,
                remaining
            );
        }

        remaining = IERC20(borrowUnderlying).balanceOf(address(this));

        // Transfer remaining borrow underlying back to the user.
        if (remaining > 0) {
            SafeTransferLib.safeTransfer(
                borrowUnderlying,
                borrower,
                remaining
            );
        }

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(
            borrowUnderlying,
            address(borrowToken)
        );
    }

    /// @notice Callback function to execute post redemption of
    ///         `collateralToken`'s underlying and swap it to repay
    ///         active debt for `redeemer`.
    /// @dev Measures slippage after this callback validating that `redeemer`
    ///      is still within acceptable liquidity requirements.
    /// @param collateralToken The cToken redeemed for its underlying.
    /// @param redeemer The account redeeming collateral that will be used to
    ///                 repay their active debt.
    /// @param collateralAmount The amount of `collateralToken` underlying
    ///                         redeemed.
    /// @param params Swap and repayment instructions.
    function onRedeem(
        address collateralToken,
        address redeemer,
        uint256 collateralAmount,
        bytes calldata params
    ) external override {
        // Validate that the collateral token itself is executing
        // the callback.
        if (msg.sender != collateralToken) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Validate the collateral token is actually listed to this
        // Market Manager.
        if (!marketManager.isListed(collateralToken)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        DeleverageStruct memory deleverageData = abi.decode(
            params,
            (DeleverageStruct)
        );

        if (
            collateralToken != address(deleverageData.collateralToken) ||
            collateralAmount != deleverageData.collateralAmount
        ) {
            revert PositionFolding__InvalidParam();
        }

        // Swap collateral token (cToken underlying) to
        // borrow token (dToken underlying).
        address collateralUnderlying = CTokenPrimitive(collateralToken)
            .underlying();

        if (
            IERC20(collateralUnderlying).balanceOf(address(this)) <
            collateralAmount
        ) {
            revert PositionFolding__InvalidAmount();
        }

        // Take protocol fee, if any.
        uint256 fee = (collateralAmount * getProtocolLeverageFee()) / 10000;
        if (fee > 0) {
            collateralAmount -= fee;
            SafeTransferLib.safeTransfer(
                collateralUnderlying,
                centralRegistry.daoAddress(),
                fee
            );
        }

        SwapperLib.ZapperCall memory zapperCall = deleverageData.zapperCall;

        // Check to make sure there is calldata attached to execute the swap.
        if (zapperCall.call.length > 0) {
            if (collateralUnderlying != zapperCall.inputToken) {
                revert PositionFolding__InvalidZapperParam();
            }

            // Validate that the target Zapper is approved inside Curvance.
            if (!centralRegistry.isZapper(deleverageData.zapperCall.target)) {
                revert PositionFolding__InvalidZapper(
                    deleverageData.zapperCall.target
                );
            }

            // Execute Zap from cToken underlying into unwrapped assets.
            SwapperLib.zap(zapperCall);
        }

        // Check to make sure there is calldata attached to execute the swap.
        if (deleverageData.swapData.call.length > 0) {
            // Validate that the target Swapper is approved inside Curvance.
            if (!centralRegistry.isSwapper(deleverageData.swapData.target)) {
                revert PositionFolding__InvalidSwapper(
                    deleverageData.swapData.target
                );
            }

            // Swap Swapper input token for borrow underlying.
            SwapperLib.swap(centralRegistry, deleverageData.swapData);
        }

        // We do not need to check whether borrowToken is listed
        // or not as even if they found a way to input a malicious
        // token here the post conditional solvency check will revert
        // the whole operation.
        DToken borrowToken = deleverageData.borrowToken;

        // Unwrap deleverage instructions for debt repayment.
        address borrowUnderlying = borrowToken.underlying();
        uint256 repayAmount = deleverageData.repayAmount;
        uint256 remaining = IERC20(borrowUnderlying).balanceOf(address(this)) -
            repayAmount;

        // Approve `repayAmount` of `borrowUnderlying` to dToken contract.
        SwapperLib._approveTokenIfNeeded(
            borrowUnderlying,
            address(borrowToken),
            repayAmount
        );

        // Repay debt.
        borrowToken.repayFor(redeemer, repayAmount);

        // Transfer remaining borrow underlying back to user.
        if (remaining > 0) {
            SafeTransferLib.safeTransfer(
                borrowUnderlying,
                redeemer,
                remaining
            );
        }

        remaining = IERC20(collateralUnderlying).balanceOf(address(this));

        // Transfer remaining collateral underlying back to the user.
        if (remaining > 0) {
            SafeTransferLib.safeTransfer(
                collateralUnderlying,
                redeemer,
                remaining
            );
        }

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(
            borrowUnderlying,
            address(borrowToken)
        );
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Calculates the maximum amount of `borrowToken` `account` can
    ///         borrow for maximum leverage.
    /// @dev Applies a minor dampening effect to calculated maximum leverage
    ///      via `MAX_LEVERAGE`.
    /// @param account The account to query maximum borrow amount for.
    /// @param borrowToken The dToken that `account` will borrow from
    ///                    to achieve leverage.
    /// @return The maximum borrow amount allowed from dToken, measured in
    ///         underlying token amount.
    function queryAmountToBorrowForLeverageMax(
        address account,
        address borrowToken
    ) public view returns (uint256) {
        (
            uint256 sumCollateral,
            uint256 maxDebt,
            uint256 sumDebt
        ) = marketManager.statusOf(account);

        // We can calculate terminal leverage by calculating the infinite
        // series of swapping to maximum LTV over and over, which results
        // in the equation 1 / (1 - LTV). 
        // 
        // For example, 80% LTV will result in terminal maximum leverage of:
        // 1 / (1 - .8) -> (1 / 0.2) -> 5x leverage. 
        // The equation below is equal to this equation,
        // just extrapolated for an account's collateral vs debt.
        //
        // We also embed a `MAX_LEVERAGE` dampening effect to minimize
        // transaction failure from imperfect execution due to things
        // such as price fluctuations, and AMM fees. 
        uint256 maxLeverage = ((sumCollateral - sumDebt) *
            MAX_LEVERAGE *
            sumCollateral) /
            (sumCollateral - maxDebt) /
            DENOMINATOR -
            sumCollateral;

        (uint256 price, uint256 errorCode) = IOracleRouter(
            ICentralRegistry(centralRegistry).oracleRouter()
        ).getPrice(address(borrowToken), true, false);

        // Validate we got a price for `borrowToken`.
        if (errorCode != 0) {
            revert PositionFolding__InvalidTokenPrice();
        }

        return ((maxLeverage - sumDebt) * 1e18) / price;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IPositionFolding).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Leverages an active Curvance position in favor of increasing
    ///         both collateral and debt inside the system.
    /// @param leverageData Struct containing instructions on desired
    ///                     leverage action.
    /// @param account The account to leverage an active Curvance position
    ///                for.
    function _leverage(
        LeverageStruct memory leverageData,
        address account
    ) internal {
        DToken borrowToken = leverageData.borrowToken;
        uint256 borrowAmount = leverageData.borrowAmount;
        uint256 maxBorrowAmount = queryAmountToBorrowForLeverageMax(
            account,
            address(borrowToken)
        );

        // Validate that the desired borrow amount is within bounds of what
        // will be allowed by the Market Manager.
        if (borrowAmount > maxBorrowAmount) {
            revert PositionFolding__ExceedsMaximumBorrowAmount(
                borrowAmount,
                maxBorrowAmount
            );
        }

        borrowToken.borrowForPositionFolding(
            account,
            borrowAmount,
            abi.encode(leverageData)
        );
    }

    /// @notice Deleverages an active Curvance position in favor of decreasing
    ///         both collateral and debt inside the system.
    /// @param deleverageData Struct containing instructions on desired
    ///                       deleverage action.
    /// @param account The account to deleverage an active Curvance position
    ///                for.
    function _deleverage(
        DeleverageStruct memory deleverageData,
        address account
    ) internal {
        deleverageData.collateralToken.withdrawByPositionFolding(
            account,
            deleverageData.collateralAmount,
            abi.encode(deleverageData)
        );
    }

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }
}
