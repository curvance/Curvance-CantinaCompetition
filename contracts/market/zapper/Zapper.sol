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

    /// @param inputToken Address of input token to Zap from.
    /// @param inputAmount The amount of `inputToken` to Zap.
    /// @param outputToken Address of token to Zap into.
    /// @param minimumOut The minimum amount of `outputToken` acceptable
    ///                   from the Zap.
    /// @param depositInputAsWETH Used only if `inputToken` is ETH, indicates
    ///                           whether ETH should be input at ETH or WETH.
    struct ZapperData {
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        uint256 minimumOut;
        bool depositInputAsWETH;
    }

    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Address of the Market Manager linked to this Position Folding
    ///         contract.
    IMarketManager public immutable marketManager;
    /// @notice The address of WETH on this chain.
    address public immutable WETH;

    /// ERRORS ///

    error Zapper__ExecutionError();
    error Zapper__InvalidCentralRegistry();
    error Zapper__MarketManagerIsNotLendingMarket();
    error Zapper__CTokenUnderlyingIsNotInputToken();
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

        // Validate that `marketManager_` is configured as a market manager
        // inside the Central Registry.
        if (!centralRegistry.isMarketManager(marketManager_)) {
            revert Zapper__MarketManagerIsNotLendingMarket();
        }

        marketManager = IMarketManager(marketManager_);
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Deposits `zapData.inputToken` into Curve lp token and
    ///         enters into Curvance position.
    /// @param cToken The Curvance cToken address.
    /// @param zapData Zap instruction data containing instruction data to
    ///                execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param tokens The underlying coins of the Curve lp token.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return cTokenOutAmount The output amount received from Zapping.
    function curveIn(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address lpMinter,
        address[] calldata tokens,
        address recipient
    ) external payable nonReentrant returns (uint256 cTokenOutAmount) {
        // Swap input token for underlyings.
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );

        // Enter Curve lp position.
        uint256 lpOutAmount = CurveLib.enterCurve(
            lpMinter,
            zapData.outputToken,
            tokens,
            zapData.minimumOut
        );

        // Enter Curvance cToken position.
        cTokenOutAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            lpOutAmount,
            recipient
        );
    }

    /// @notice Withdraws a Curvance Curve lp position and zaps it into
    ///         desired token (zapData.outputToken).
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param zapData Zap instruction data containing instruction data to
    ///                execute the Zap.
    /// @param tokens The underlying token addresses of the Curve lp token.
    /// @param singleAssetWithdraw Whether LP should be unwrapped to a single
    ///                            token or not. 
    ///                            0 = all tokens.
    ///                            1 = single token; uint256 interface.
    ///                            2+ = single token; int128 interface.
    /// @param singleAssetIndex Used if `singleAssetWithdraw` != 0, indicates
    ///                         the coin index inside the Curve lp
    ///                         to withdraw as.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function curveOut(
        address lpMinter,
        ZapperData calldata zapData,
        address[] calldata tokens,
        uint256 singleAssetWithdraw,
        uint256 singleAssetIndex,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        // Transfer Curve lp token to the Zapper.
        SafeTransferLib.safeTransferFrom(
            zapData.inputToken,
            msg.sender,
            address(this),
            zapData.inputAmount
        );

        // Exit Curve lp position.
        CurveLib.exitCurve(
            lpMinter,
            zapData.inputToken,
            tokens,
            zapData.inputAmount,
            singleAssetWithdraw,
            singleAssetIndex
        );

        uint256 numTokenSwaps = tokenSwaps.length;
        // Swap unwrapped token(s) into `zapData.outputToken`.
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        if (outAmount < zapData.minimumOut) {
            revert Zapper__SlippageError();
        }

        // Transfer output tokens to `recipient`.
        _transferToUser(zapData.outputToken, recipient, outAmount);
    }

    /// @notice Deposits `zapData.inputToken` into Balancer BPT and
    ///         enters into Curvance position.
    /// @param cToken The Curvance cToken address.
    /// @param zapData Zap instruction data containing instruction data to
    ///                execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param balancerVault The Balancer vault address.
    /// @param balancerPoolId The Balancer BPT pool ID.
    /// @param tokens The underlying coins of the Curve lp token.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return cTokenOutAmount The output amount received from Zapping.
    function balancerIn(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address balancerVault,
        bytes32 balancerPoolId,
        address[] calldata tokens,
        address recipient
    ) external payable nonReentrant returns (uint256 cTokenOutAmount) {
        // Swap input token for underlyings.
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );

        // Enter Balancer BPT position.
        uint256 lpOutAmount = BalancerLib.enterBalancer(
            balancerVault,
            balancerPoolId,
            zapData.outputToken,
            tokens,
            zapData.minimumOut
        );

        // Enter Curvance cToken position.
        cTokenOutAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            lpOutAmount,
            recipient
        );
    }

    /// @notice Withdraws a Curvance Balancer BPT position and zaps it into
    ///         desired token (zapData.outputToken).
    /// @param balancerVault The Balancer vault address.
    /// @param balancerPoolId The Balancer BPT pool ID.
    /// @param zapData Zap instruction data containing instruction data to
    ///                execute the Zap.
    /// @param tokens The underlying token addresses of the Curve lp token.
    /// @param singleAssetWithdraw Whether BPT should be unwrapped to a single
    ///                            token or not. 
    ///                            false = all tokens.
    ///                            true = single token.
    /// @param singleAssetIndex Used if `singleAssetWithdraw` = true,
    ///                         indicates the coin index inside the Balancer
    ///                         BPT to withdraw as.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
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
        // Transfer the Balancer BPT to the Zapper.
        SafeTransferLib.safeTransferFrom(
            zapData.inputToken,
            msg.sender,
            address(this),
            zapData.inputAmount
        );

        // Exit Balancer BPT position.
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
        // Swap unwrapped token(s) into `zapData.outputToken`.
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        if (outAmount < zapData.minimumOut) {
            revert Zapper__SlippageError();
        }

        // Transfer output tokens to `recipient`.
        _transferToUser(zapData.outputToken, recipient, outAmount);
    }

    /// @notice Deposits `zapData.inputToken` into Velodrome sAMM/vAMM and
    ///         enters into Curvance position.
    /// @param cToken The Curvance cToken address.
    /// @param zapData Zap instruction data containing instruction data to
    ///                execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param router The Velodrome router address.
    /// @param factory The Velodrome factory address.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return cTokenOutAmount The output amount received from Zapping.
    function velodromeIn(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address router,
        address factory,
        address recipient
    ) external payable nonReentrant returns (uint256 cTokenOutAmount) {
        // Swap input token for underlyings.
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );

        // Enter Velodrome sAMM/vAMM position.
        cTokenOutAmount = VelodromeLib.enterVelodrome(
            router,
            factory,
            zapData.outputToken,
            CommonLib.getTokenBalance(IVeloPair(zapData.outputToken).token0()),
            CommonLib.getTokenBalance(IVeloPair(zapData.outputToken).token1()),
            zapData.minimumOut
        );

        // Enter Curvance cToken position.
        cTokenOutAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            cTokenOutAmount,
            recipient
        );
    }

    /// @notice Withdraws a Curvance Velodrome sAMM/vAMM position and zaps it
    ///         into desired token (zapData.outputToken).
    /// @param router The Velodrome router address.
    /// @param zapData Zap instruction data containing instruction data to
    ///                execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function velodromeOut(
        address router,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        // Transfer the Velodrome sAMM/vAMM to the Zapper.
        SafeTransferLib.safeTransferFrom(
            zapData.inputToken,
            msg.sender,
            address(this),
            zapData.inputAmount
        );

        // Exit Velodrome sAMM/vAMM position.
        VelodromeLib.exitVelodrome(
            router,
            zapData.inputToken,
            zapData.inputAmount
        );

        uint256 numTokenSwaps = tokenSwaps.length;
        // Swap unwrapped tokens into `zapData.outputToken`.
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        if (outAmount < zapData.minimumOut) {
            revert Zapper__SlippageError();
        }

        // Transfer output tokens to `recipient`.
        _transferToUser(zapData.outputToken, recipient, outAmount);
    }

    /// @notice Swap `inputToken` into desired cToken underlying tokens.
    /// @param inputToken The input token address.
    /// @param inputAmount The amount of `inputToken` to swap for underlying
    ///                    tokens.
    /// @param tokenSwaps Array of swap instruction data
    /// @param depositInputAsWETH Used when `inputToken` is chain gas token,
    ///                           indicates depositing gas token into wrapper
    ///                           contract.
    function _swapForUnderlyings(
        address inputToken,
        uint256 inputAmount,
        SwapperLib.Swap[] calldata tokenSwaps,
        bool depositInputAsWETH
    ) private {
        // If the input token is chain gas token, check if it should be
        // wrapped.
        if (CommonLib.isETH(inputToken)) {
            // Validate message has gas token attached.
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
        // Swap `inputToken` into desired cToken underlying tokens.
        for (uint256 i; i < numTokenSwaps; ) {
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert Zapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
        }
    }

    /// @notice Routes lp/BPT into Curvance cToken contract.
    /// @param cToken The Curvance cToken address.
    /// @param inputToken The input token address, should match
    ///                   cToken.underlying().
    /// @param amount The amount of `inputToken` to deposit into cToken
    ///               position.
    /// @param recipient Address that should receive Curvance cTokens.
    /// @return The output amount of cTokens received.
    function _enterCurvance(
        address cToken,
        address inputToken,
        uint256 amount,
        address recipient
    ) private returns (uint256) {
        // cToken not configured so transfer their token back and return.
        if (cToken == address(0)) {
            SafeTransferLib.safeTransfer(inputToken, recipient, amount);
            return amount;
        }

        // Validate that `cToken` is listed inside the associated
        // Market Manager.
        if (!marketManager.isListed(cToken)) {
            revert Zapper__Unauthorized();
        }

        // Validate inputToken matches underlying token of cToken contract.
        if (CTokenPrimitive(cToken).underlying() != inputToken) {
            revert Zapper__CTokenUnderlyingIsNotInputToken();
        }

        // Approve cToken to take `inputToken`.
        SwapperLib._approveTokenIfNeeded(inputToken, cToken, amount);

        uint256 priorBalance = IERC20(cToken).balanceOf(recipient);

        // Enter Curvance cToken position and make sure `recipient` got
        // cTokens.
        if (CTokenPrimitive(cToken).deposit(amount, recipient) == 0) {
            revert Zapper__ExecutionError();
        }

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(inputToken, cToken);

        // Bubble up how many cTokens `recipient` received.
        return IERC20(cToken).balanceOf(recipient) - priorBalance;
    }

    /// @notice Helper function for efficiently transferring tokens
    ///         to desired user.
    /// @param token The token to transfer to `recipient`, 
    ///              this can be the network gas token.
    /// @param recipient The user receiving `token`.
    /// @param amount The amount of `token` to be transferred to `recipient`.
    function _transferToUser(
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
