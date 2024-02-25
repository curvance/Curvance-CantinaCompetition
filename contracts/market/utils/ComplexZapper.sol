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

contract ComplexZapper is ReentrancyGuard {
    /// TYPES ///

    /// @param inputToken Address of input token to Zap from.
    /// @param inputAmount The amount of `inputToken` to Zap.
    /// @param outputToken Address of token Zapped into.
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

    /// @param cToken The address of the cToken corresponding to Curve lp
    ///               token to be exited.
    /// @param shares The amount of shares to redeemed.
    /// @param forceRedeemCollateral Whether the collateral should be always
    ///                              reduced from callers collateralPosted.
    struct RedemptionData {
        address cToken;
        uint256 shares;
        bool forceRedeemCollateral;
    }

    /// @param balancerVault The Balancer vault address.
    /// @param balancerPoolId The BPT pool ID.
    /// @param singleAssetWithdraw Whether BPT should be unwrapped to a single
    ///                            token or not. 
    ///                            false = all tokens.
    ///                            true = single token.
    /// @param singleAssetIndex Used if `singleAssetWithdraw` = true,
    ///                         indicates the coin index inside the Balancer
    ///                         BPT to withdraw as.
    struct BPTRedemption {
        address balancerVault;
        bytes32 balancerPoolId;
        bool singleAssetWithdraw;
        uint256 singleAssetIndex;
    }

    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Address of the Market Manager linked to this contract.
    IMarketManager public immutable marketManager;
    /// @notice The address of WETH on this chain.
    address public immutable WETH;

    /// ERRORS ///

    error ComplexZapper__ExecutionError();
    error ComplexZapper__InvalidCentralRegistry();
    error ComplexZapper__InvalidMarketManager();
    error ComplexZapper__CTokenUnderlyingIsNotInputToken();
    error ComplexZapper__Unauthorized();
    error ComplexZapper__SlippageError();
    error ComplexZapper__InvalidSwapper(uint256 index, address invalidSwapper);

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
            revert ComplexZapper__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        // Validate that `marketManager_` is configured as a market manager
        // inside the Central Registry.
        if (!centralRegistry.isMarketManager(marketManager_)) {
            revert ComplexZapper__InvalidMarketManager();
        }

        marketManager = IMarketManager(marketManager_);
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Swaps then deposits `zapData.inputToken` into Curve lp token,
    ///         and enters into Curvance position.
    /// @param cToken The Curvance cToken address.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param tokens The underlying coins of the Curve lp token.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return outAmount The output amount received from Zapping.
    function enterCurve(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address lpMinter,
        address[] calldata tokens,
        address recipient
    ) external payable nonReentrant returns (uint256 outAmount) {
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
        outAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            lpOutAmount,
            recipient
        );
    }

    /// @notice Exits a Curve lp, and zaps it into desired
    ///         token (zapData.outputToken).
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokens The underlying token addresses of the Curve lp token.
    /// @param singleAssetWithdraw Whether lp should be unwrapped to a single
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
    function exitCurve(
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
        outAmount = _exitCurve(
            lpMinter,
            zapData,
            tokens,
            singleAssetWithdraw,
            singleAssetIndex,
            tokenSwaps,
            recipient
        );
    }

    /// @notice Withdraws a Curvance Curve lp position, and zaps it into
    ///         desired token (zapData.outputToken).
    /// @param redemptionData Struct containing information on redemption action
    ///                       to execute. Containing values:
    ///                       1. The address of the cToken corresponding to Curve lp
    ///                          token to be exited.
    ///                       2. The amount of shares to redeemed.
    ///                       3. Whether the collateral should be always
    ///                          reduced from callers collateralPosted.
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokens The underlying token addresses of the Curve lp token.
    /// @param singleAssetWithdraw Whether lp should be unwrapped to a single
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
    function redeemAndExitCurve(
        RedemptionData calldata redemptionData,
        address lpMinter,
        ZapperData calldata zapData,
        address[] calldata tokens,
        uint256 singleAssetWithdraw,
        uint256 singleAssetIndex,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        // Exit Curvance position.
        _exitCurvance(
            redemptionData.cToken,
            redemptionData.shares,
            redemptionData.forceRedeemCollateral,
            zapData.inputToken,
            zapData.inputAmount
        );
    
        // Exit Curve lp position.
        outAmount = _exitCurve(
            lpMinter,
            zapData,
            tokens,
            singleAssetWithdraw,
            singleAssetIndex,
            tokenSwaps,
            recipient
        );
    }

    /// @notice Swaps then deposits `zapData.inputToken` into a BPT, and
    ///         enters into Curvance position.
    /// @param cToken The Curvance cToken address.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param balancerVault The Balancer vault address.
    /// @param balancerPoolId The BPT pool ID.
    /// @param tokens The underlying coins of the BPT.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return outAmount The output amount received from Zapping.
    function enterBalancer(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address balancerVault,
        bytes32 balancerPoolId,
        address[] calldata tokens,
        address recipient
    ) external payable nonReentrant returns (uint256 outAmount) {
        // Swap input token for underlyings.
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );

        // Enter BPT position.
        uint256 lpOutAmount = BalancerLib.enterBalancer(
            balancerVault,
            balancerPoolId,
            zapData.outputToken,
            tokens,
            zapData.minimumOut
        );

        // Enter Curvance cToken position.
        outAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            lpOutAmount,
            recipient
        );
    }

    /// @notice Exits a BPT, and zaps it into desired
    ///         token (zapData.outputToken).
    /// @param balancerData Struct containing information on BPT redemption
    ///                       to execute. Containing values:
    ///                       1. The Balancer vault address.
    ///                       2. The BPT pool ID.
    ///                       3. Whether BPT should be unwrapped to a single
    ///                          token or not. 
    ///                          false = all tokens.
    ///                          true = single token.
    ///                       4. Used if `singleAssetWithdraw` = true,
    ///                          indicates the coin index inside the Balancer
    ///                          BPT to withdraw as. 
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokens The underlying token addresses of the BPT.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function exitBalancer(
        BPTRedemption calldata balancerData,
        ZapperData calldata zapData,
        address[] calldata tokens,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        // Transfer the BPT to the Zapper.
        SafeTransferLib.safeTransferFrom(
            zapData.inputToken,
            msg.sender,
            address(this),
            zapData.inputAmount
        );

        // Exit Balancer lp position.
        outAmount = _exitBalancer(
            balancerData.balancerVault,
            balancerData.balancerPoolId,
            balancerData.singleAssetWithdraw,
            balancerData.singleAssetIndex,
            zapData,
            tokens,
            tokenSwaps,
            recipient
        );
    }

    /// @notice Withdraws a Curvance BPT position, and zaps it into
    ///         desired token (zapData.outputToken).
    /// @param redemptionData Struct containing information on redemption action
    ///                       to execute. Containing values:
    ///                       1. The address of the cToken corresponding to Curve lp
    ///                          token to be exited.
    ///                       2. The amount of shares to redeemed.
    ///                       3. Whether the collateral should be always
    ///                          reduced from callers collateralPosted.
    /// @param balancerData Struct containing information on BPT redemption
    ///                       to execute. Containing values:
    ///                       1. The Balancer vault address.
    ///                       2. The BPT pool ID.
    ///                       3. Whether BPT should be unwrapped to a single
    ///                          token or not. 
    ///                          false = all tokens.
    ///                          true = single token.
    ///                       4. Used if `singleAssetWithdraw` = true,
    ///                          indicates the coin index inside the Balancer
    ///                          BPT to withdraw as. 
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokens The underlying token addresses of the BPT.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function redeemAndExitBalancer(
        RedemptionData calldata redemptionData,
        BPTRedemption calldata balancerData,
        ZapperData calldata zapData,
        address[] calldata tokens,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        // Exit Curvance position.
        _exitCurvance(
            redemptionData.cToken,
            redemptionData.shares,
            redemptionData.forceRedeemCollateral,
            zapData.inputToken,
            zapData.inputAmount
        );
    
        // Exit Balancer lp position.
        outAmount = _exitBalancer(
            balancerData.balancerVault,
            balancerData.balancerPoolId,
            balancerData.singleAssetWithdraw,
            balancerData.singleAssetIndex,
            zapData,
            tokens,
            tokenSwaps,
            recipient
        );
    }

    /// @notice Swaps then deposits `zapData.inputToken` into Velodrome
    ///         sAMM/vAMM, and enters into Curvance position.
    /// @param cToken The Curvance cToken address.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param router The Velodrome router address.
    /// @param factory The Velodrome factory address.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return outAmount The output amount received from Zapping.
    function enterVelodrome(
        address cToken,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address router,
        address factory,
        address recipient
    ) external payable nonReentrant returns (uint256 outAmount) {
        // Swap input token for underlyings.
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps,
            zapData.depositInputAsWETH
        );

        // Enter Velodrome sAMM/vAMM position.
        outAmount = VelodromeLib.enterVelodrome(
            router,
            factory,
            zapData.outputToken,
            CommonLib.getTokenBalance(IVeloPair(zapData.outputToken).token0()),
            CommonLib.getTokenBalance(IVeloPair(zapData.outputToken).token1()),
            zapData.minimumOut
        );

        // Enter Curvance cToken position.
        outAmount = _enterCurvance(
            cToken,
            zapData.outputToken,
            outAmount,
            recipient
        );
    }

    /// @notice Exits a Velodrome sAMM/vAMM, and zaps it into desired
    ///         token (zapData.outputToken).
    /// @param router The Velodrome router address.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function exitVelodrome(
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

        // Exit Velodrome lp position.
        outAmount = _exitVelodrome(
            router,
            zapData,
            tokenSwaps,
            recipient
        );
    }

    /// @notice Withdraws a Curvance Velodrome sAMM/vAMM position, and zaps it
    ///         into desired token (zapData.outputToken).
    /// @param redemptionData Struct containing information on redemption action
    ///                       to execute. Containing values:
    ///                       1. The address of the cToken corresponding to Curve lp
    ///                          token to be exited.
    ///                       2. The amount of shares to redeemed.
    ///                       3. Whether the collateral should be always
    ///                          reduced from callers collateralPosted.
    /// @param router The Velodrome router address.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function redeemAndExitVelodrome(
        RedemptionData calldata redemptionData,
        address router,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        // Exit Curvance position.
        _exitCurvance(
            redemptionData.cToken,
            redemptionData.shares,
            redemptionData.forceRedeemCollateral,
            zapData.inputToken,
            zapData.inputAmount
        );

        // Exit Velodrome lp position.
        outAmount = _exitVelodrome(
            router,
            zapData,
            tokenSwaps,
            recipient
        );
    }

    /// INTERNAL FUNCTIONS ///

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
    ) internal returns (uint256) {
        // cToken not configured so transfer their token back and return.
        if (cToken == address(0)) {
            SafeTransferLib.safeTransfer(inputToken, recipient, amount);
            return amount;
        }

        // Validate that `cToken` is listed inside the associated
        // Market Manager.
        if (!marketManager.isListed(cToken)) {
            revert ComplexZapper__Unauthorized();
        }

        // Validate inputToken matches underlying token of cToken contract.
        if (CTokenPrimitive(cToken).underlying() != inputToken) {
            revert ComplexZapper__CTokenUnderlyingIsNotInputToken();
        }

        // Approve cToken to take `inputToken`.
        SwapperLib._approveTokenIfNeeded(inputToken, cToken, amount);

        uint256 priorBalance = IERC20(cToken).balanceOf(recipient);

        // Enter Curvance cToken position and make sure `recipient` got
        // cTokens.
        if (CTokenPrimitive(cToken).deposit(amount, recipient) == 0) {
            revert ComplexZapper__ExecutionError();
        }

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(inputToken, cToken);

        // Bubble up how many cTokens `recipient` received.
        return IERC20(cToken).balanceOf(recipient) - priorBalance;
    }

    /// @notice Exits a Curvance position.
    /// @param cToken The address of the cToken to be exited.
    /// @param shares The amount of shares to redeemed.
    /// @param forceRedeemCollateral Whether the collateral should be always
    ///                              reduced from callers collateralPosted.
    /// @param underlying The expected underlying token of `cToken`.
    /// @param expectedAssets The amount of assets expected to be redeemed
    ///                       on exiting Curvance position.
    function _exitCurvance(
        address cToken,
        uint256 shares,
        bool forceRedeemCollateral,
        address underlying,
        uint256 expectedAssets
    ) internal {
        if (CTokenPrimitive(cToken).underlying() != underlying) {
            revert ComplexZapper__ExecutionError();
        }

        uint256 assets;

        // Transfer Curve lp token to the Zapper.
        if (forceRedeemCollateral) {
            assets = CTokenPrimitive(cToken).redeemCollateralFor(
                shares,
                address(this),
                msg.sender
            );
        } else {
            assets = CTokenPrimitive(cToken).redeemFor(
                shares,
                address(this),
                msg.sender
            );
        }

        // Validate that output of redemption equals expectation.
        if (assets != expectedAssets) {
            revert ComplexZapper__ExecutionError();
        }
    }

    /// @notice Withdraws a Curvance Curve lp position, and zaps it into
    ///         desired token (zapData.outputToken).
    /// @param lpMinter The minter address of the Curve lp token.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokens The underlying token addresses of the Curve lp token.
    /// @param singleAssetWithdraw Whether lp should be unwrapped to a single
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
    function _exitCurve(
        address lpMinter,
        ZapperData calldata zapData,
        address[] calldata tokens,
        uint256 singleAssetWithdraw,
        uint256 singleAssetIndex,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) internal returns (uint256 outAmount){
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
            // Validate target contract is an approved swapper.
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert ComplexZapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            // Execute swap(s) into `zapData.outputToken`.
            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        // Validate zap output is sufficient.
        if (outAmount < zapData.minimumOut) {
            revert ComplexZapper__SlippageError();
        }

        // Transfer output tokens to `recipient`.
        _transferToRecipient(zapData.outputToken, recipient, outAmount);
    }

    /// @notice Withdraws a Curvance BPT position, and zaps it into
    ///         desired token (zapData.outputToken).
    /// @param balancerVault The Balancer vault address.
    /// @param balancerPoolId The BPT pool ID.
    /// @param singleAssetWithdraw Whether BPT should be unwrapped to a single
    ///                            token or not. 
    ///                            false = all tokens.
    ///                            true = single token.
    /// @param singleAssetIndex Used if `singleAssetWithdraw` = true,
    ///                         indicates the coin index inside the Balancer
    ///                         BPT to withdraw as.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokens The underlying token addresses of the BPT.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function _exitBalancer(
        address balancerVault,
        bytes32 balancerPoolId,
        bool singleAssetWithdraw,
        uint256 singleAssetIndex,
        ZapperData calldata zapData,
        address[] calldata tokens,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) internal returns (uint256 outAmount){
        // Exit BPT position.
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
            // Validate target contract is an approved swapper.
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert ComplexZapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            // Execute swap(s) into `zapData.outputToken`.
            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        // Validate zap output is sufficient.
        if (outAmount < zapData.minimumOut) {
            revert ComplexZapper__SlippageError();
        }

        // Transfer output tokens to `recipient`.
        _transferToRecipient(zapData.outputToken, recipient, outAmount);
    }

    /// @notice Withdraws a Curvance Velodrome sAMM/vAMM position, and zaps it
    ///         into desired token (zapData.outputToken).
    /// @param router The Velodrome router address.
    /// @param zapData Zap instruction data to execute the Zap.
    /// @param tokenSwaps Array of swap instruction data to execute the Zap.
    /// @param recipient Address that should receive Zapped withdrawal.
    /// @return outAmount The output amount received from Zapping.
    function _exitVelodrome(
        address router,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) internal returns (uint256 outAmount){
        // Exit Velodrome sAMM/vAMM position.
        VelodromeLib.exitVelodrome(
            router,
            zapData.inputToken,
            zapData.inputAmount
        );

        uint256 numTokenSwaps = tokenSwaps.length;
        // Swap unwrapped tokens into `zapData.outputToken`.
        for (uint256 i; i < numTokenSwaps; ) {
            // Validate target contract is an approved swapper.
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert ComplexZapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            // Execute swap(s) into `zapData.outputToken`.
            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
        }

        outAmount = CommonLib.getTokenBalance(zapData.outputToken);
        // Validate zap output is sufficient.
        if (outAmount < zapData.minimumOut) {
            revert ComplexZapper__SlippageError();
        }

        // Transfer output tokens to `recipient`.
        _transferToRecipient(zapData.outputToken, recipient, outAmount);
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
    ) internal {
        // If the input token is chain gas token, check if it should be
        // wrapped.
        if (CommonLib.isETH(inputToken)) {
            // Validate message has gas token attached.
            if (inputAmount != msg.value) {
                revert ComplexZapper__ExecutionError();
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
            // Validate target contract is an approved swapper.
            if (!centralRegistry.isSwapper(tokenSwaps[i].target)) {
                revert ComplexZapper__InvalidSwapper(i, tokenSwaps[i].target);
            }

            // Execute swap into underlying(s).
            unchecked {
                SwapperLib.swap(centralRegistry, tokenSwaps[i++]);
            }
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
