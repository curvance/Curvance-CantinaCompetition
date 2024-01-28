// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { CommonLib } from "contracts/libraries/CommonLib.sol";
import { CurveLib } from "contracts/libraries/CurveLib.sol";
import { BalancerLib } from "contracts/libraries/BalancerLib.sol";
import { VelodromeLib } from "contracts/libraries/VelodromeLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IWETH } from "contracts/interfaces/IWETH.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";

contract Zapper is ReentrancyGuard {
    /// TYPES ///

    struct ZapperData {
        address inputToken; // Input token to Zap from
        uint256 inputAmount; // Input token amount to Zap from
        address outputToken; // Output token to Zap to
        uint256 minimumOut; // Minimum token amount acceptable
        bool depositInputAsWETH; // Only valid if input token is ETH for zap in
    }

    /// CONSTANTS ///

    IMarketManager public immutable marketManager; // MarketManager linked
    address public immutable WETH; // Address of WETH
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// ERRORS ///

    error Zapper__ExecutionError();
    error Zapper__InvalidCentralRegistry();
    error Zapper__MarketManagerIsNotLendingMarket();
    error Zapper__CTokenUnderlyingIsNotLPToken();
    error Zapper__Unauthorized();
    error Zapper__SlippageError();
    error Zapper__InvalidSwapper(uint256 index, address invalidSwapper);

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
            revert Zapper__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        if (!centralRegistry.isMarketManager(marketManager_)) {
            revert Zapper__MarketManagerIsNotLendingMarket();
        }

        marketManager = IMarketManager(marketManager_);
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @dev Deposit inputToken and enter curvance
    /// @param cToken The curvance deposit token address
    /// @param zapData Zap data containing input/output token addresses and amounts
    /// @param tokenSwaps The swap aggregation data
    /// @param lpMinter The minter address of Curve LP
    /// @param tokens The underlying coins of curve LP token
    /// @param recipient Address that should receive zapped deposit
    /// @return cTokenOutAmount The output amount received from zapping
    function curveIn(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address lpMinter,
        address[] calldata tokens,
        address recipient
    ) external payable nonReentrant returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );

        // enter curve
        uint256 lpOutAmount = CurveLib.enterCurve(
            lpMinter,
            zapData.outputToken,
            tokens,
            zapData.minimumOut
        );

        // enter curvance
        cTokenOutAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            lpOutAmount,
            recipient
        );
    }

    function curveOut(
        address lpMinter,
        ZapperData calldata zapData,
        address[] calldata tokens,
        uint256 singleAssetWithdraw,
        uint256 singleAssetIndex,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        SafeTransferLib.safeTransferFrom(
            zapData.inputToken,
            msg.sender,
            address(this),
            zapData.inputAmount
        );
        CurveLib.exitCurve(
            lpMinter,
            zapData.inputToken,
            tokens,
            zapData.inputAmount,
            singleAssetWithdraw,
            singleAssetIndex
        );

        uint256 numTokenSwaps = tokenSwaps.length;
        // prepare tokens to mint LP
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        if (outAmount < zapData.minimumOut) {
            revert Zapper__SlippageError();
        }

        // transfer token back to user
        _transferOut(zapData.outputToken, recipient, outAmount);
    }

    /// @dev Deposit inputToken and enter curvance
    /// @param cToken The curvance deposit token address
    /// @param zapData Zap data containing input/output token addresses and amounts
    /// @param tokenSwaps The swap aggregation data
    /// @param balancerVault The balancer vault address
    /// @param balancerPoolId The balancer pool ID
    /// @param tokens The underlying coins of balancer LP token
    /// @param recipient Address that should receive zapped deposit
    /// @return cTokenOutAmount The output amount received from zapping
    function balancerIn(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address balancerVault,
        bytes32 balancerPoolId,
        address[] calldata tokens,
        address recipient
    ) external payable nonReentrant returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );

        // enter balancer
        uint256 lpOutAmount = BalancerLib.enterBalancer(
            balancerVault,
            balancerPoolId,
            zapData.outputToken,
            tokens,
            zapData.minimumOut
        );

        // enter curvance
        cTokenOutAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            lpOutAmount,
            recipient
        );
    }

    function balancerOut(
        address balancerVault,
        bytes32 balancerPoolId,
        ZapperData calldata zapData,
        address[] calldata tokens,
        bool singleAssetWithdraw,
        uint256 singleAssetIndex,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        SafeTransferLib.safeTransferFrom(
            zapData.inputToken,
            msg.sender,
            address(this),
            zapData.inputAmount
        );
        BalancerLib.exitBalancer(
            balancerVault,
            balancerPoolId,
            zapData.inputToken,
            tokens,
            zapData.inputAmount,
            singleAssetWithdraw,
            singleAssetIndex
        );

        uint256 numTokenSwaps = tokenSwaps.length;
        // prepare tokens to mint LP
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        if (outAmount < zapData.minimumOut) {
            revert Zapper__SlippageError();
        }

        // transfer token back to user
        _transferOut(zapData.outputToken, recipient, outAmount);
    }

    /// @dev Deposit inputToken and enter curvance
    /// @param cToken The curvance deposit token address
    /// @param zapData Zap data containing input/output token addresses and amounts
    /// @param tokenSwaps The swap aggregation data
    /// @param router The velodrome router address
    /// @param factory The velodrome factory address
    /// @param recipient Address that should receive zapped deposit
    /// @return cTokenOutAmount The output amount received from zapping
    function velodromeIn(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address router,
        address factory,
        address recipient
    ) external payable nonReentrant returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );
        // enter velodrome
        cTokenOutAmount = VelodromeLib.enterVelodrome(
            router,
            factory,
            zapData.outputToken,
            CommonLib.getTokenBalance(IVeloPair(zapData.outputToken).token0()),
            CommonLib.getTokenBalance(IVeloPair(zapData.outputToken).token1()),
            zapData.minimumOut
        );
        // enter curvance
        cTokenOutAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            cTokenOutAmount,
            recipient
        );
    }

    function velodromeOut(
        address router,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        SafeTransferLib.safeTransferFrom(
            zapData.inputToken,
            msg.sender,
            address(this),
            zapData.inputAmount
        );
        VelodromeLib.exitVelodrome(
            router,
            zapData.inputToken,
            zapData.inputAmount
        );

        uint256 numTokenSwaps = tokenSwaps.length;
        // prepare tokens to mint LP
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        if (outAmount < zapData.minimumOut) {
            revert Zapper__SlippageError();
        }

        // transfer token back to user
        _transferOut(zapData.outputToken, recipient, outAmount);
    }

    /// @dev Deposit inputToken and enter curvance
    /// @param inputToken The input token address
    /// @param inputAmount The amount to deposit
    /// @param tokenSwaps The swap aggregation data
    /// @param depositInputAsWETH Used when `inputToken` is ether,
    ///                           indicates depositing ether into WETH9 contract
    function _swapForUnderlyings(
        address inputToken,
        uint256 inputAmount,
        SwapperLib.Swap[] calldata tokenSwaps,
        bool depositInputAsWETH
    ) private {
        if (CommonLib.isETH(inputToken)) {
            if (inputAmount != msg.value) {
                revert Zapper__ExecutionError();
            }
            if (depositInputAsWETH) {
                IWETH(WETH).deposit{ value: inputAmount }();
            }
        } else {
            SafeTransferLib.safeTransferFrom(
                inputToken,
                msg.sender,
                address(this),
                inputAmount
            );
        }

        uint256 numTokenSwaps = tokenSwaps.length;

        // prepare tokens to mint LP
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }
    }

    /// @dev Enter curvance
    /// @param cToken The curvance deposit token address
    /// @param lpToken The Curve LP token address
    /// @param amount The amount to deposit
    /// @param recipient The recipient address
    /// @return The output amount
    function _enterCurvance(
        address cToken,
        address lpToken,
        uint256 amount,
        address recipient
    ) private returns (uint256) {
        if (cToken == address(0)) {
            // transfer LP token to recipient
            SafeTransferLib.safeTransfer(lpToken, recipient, amount);
            return amount;
        }

        // check valid cToken
        if (!marketManager.isListed(cToken)) {
            revert Zapper__Unauthorized();
        }

        // check cToken underlying
        if (CTokenPrimitive(cToken).underlying() != lpToken) {
            revert Zapper__CTokenUnderlyingIsNotLPToken();
        }

        // approve lp token
        SwapperLib._approveTokenIfNeeded(lpToken, cToken, amount);

        uint256 priorBalance = IERC20(cToken).balanceOf(recipient);

        // enter curvance
        if (CTokenPrimitive(cToken).deposit(amount, recipient) == 0) {
            revert Zapper__ExecutionError();
        }

        SwapperLib._removeApprovalIfNeeded(lpToken, cToken);

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
