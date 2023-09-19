// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { CommonLib } from "contracts/market/zapper/protocols/CommonLib.sol";
import { CurveLib } from "contracts/market/zapper/protocols/CurveLib.sol";
import { BalancerLib } from "contracts/market/zapper/protocols/BalancerLib.sol";
import { VelodromeLib } from "contracts/market/zapper/protocols/VelodromeLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CToken, IERC20 } from "contracts/market/collateral/CToken.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract Zapper {
    /// TYPES ///

    struct ZapperData {
        address inputToken; // Input token to Zap from
        uint256 inputAmount; // Input token amount to Zap from
        address outputToken; // Output token to Zap to
        uint256 minimumOut; // Minimum token amount acceptable
    }

    /// CONSTANTS ///

    ILendtroller public immutable lendtroller; // Lendtroller linked
    address public immutable WETH; // Address of WETH
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address lendtroller_,
        address WETH_
    ) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "Zapper: invalid central registry"
        );

        centralRegistry = centralRegistry_;

        require(
            centralRegistry.isLendingMarket(lendtroller_),
            "Zapper: lendtroller is invalid"
        );

        lendtroller = ILendtroller(lendtroller_);
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
    ) external payable returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps
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
    ) external returns (uint256 outAmount) {
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
            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }

        outAmount = IERC20(zapData.outputToken).balanceOf(address(this));
        require(
            outAmount >= zapData.minimumOut,
            "Zapper: received less than minOutAmount"
        );

        // transfer token back to user
        SafeTransferLib.safeTransfer(
            zapData.outputToken,
            recipient,
            outAmount
        );
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
    ) external payable returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps
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
    ) external returns (uint256 outAmount) {
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
            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }

        outAmount = IERC20(zapData.outputToken).balanceOf(address(this));
        require(
            outAmount >= zapData.minimumOut,
            "Zapper: received less than minOutAmount"
        );

        // transfer token back to user
        SafeTransferLib.safeTransfer(
            zapData.outputToken,
            recipient,
            outAmount
        );
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
    ) external payable returns (uint256 cTokenOutAmount) {
        // swap input token for underlyings
        _swapForUnderlyings(
            zapData.inputToken,
            zapData.inputAmount,
            tokenSwaps
        );

        // enter velodrome
        uint256 lpOutAmount = VelodromeLib.enterVelodrome(
            router,
            factory,
            zapData.outputToken,
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

    function velodromeOut(
        address router,
        ZapperData calldata zapData,
        SwapperLib.Swap[] calldata tokenSwaps,
        address recipient
    ) external returns (uint256 outAmount) {
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
            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }

        outAmount = IERC20(zapData.outputToken).balanceOf(address(this));
        require(
            outAmount >= zapData.minimumOut,
            "Zapper: received less than minOutAmount"
        );

        // transfer token back to user
        SafeTransferLib.safeTransfer(
            zapData.outputToken,
            recipient,
            outAmount
        );
    }

    /// @dev Deposit inputToken and enter curvance
    /// @param inputToken The input token address
    /// @param inputAmount The amount to deposit
    /// @param tokenSwaps The swap aggregation data
    function _swapForUnderlyings(
        address inputToken,
        uint256 inputAmount,
        SwapperLib.Swap[] calldata tokenSwaps
    ) private {
        if (CommonLib.isETH(inputToken)) {
            require(inputAmount == msg.value, "Zapper: invalid amount");
            inputToken = WETH;
            IWETH(WETH).deposit{ value: inputAmount }();
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
            unchecked {
                SwapperLib.swap(tokenSwaps[i++]);
            }
        }
    }

    /// @dev Enter curvance
    /// @param cToken The curvance deposit token address
    /// @param lpToken The Curve LP token address
    /// @param amount The amount to deposit
    /// @param recipient The recipient adress
    /// @return out The output amount
    function _enterCurvance(
        address cToken,
        address lpToken,
        uint256 amount,
        address recipient
    ) private returns (uint256 out) {
        if (cToken == address(0)) {
            // transfer LP token to recipient
            SafeTransferLib.safeTransfer(lpToken, recipient, amount);
            return amount;
        }

        // check valid cToken
        require(lendtroller.isListed(cToken), "PositionFolding: UNAUTHORIZED");
        // check cToken underlying
        require(
            CToken(cToken).underlying() == lpToken,
            "Zapper: invalid lp address"
        );

        // approve lp token
        SwapperLib.approveTokenIfNeeded(lpToken, cToken, amount);

        uint256 priorBalance = IERC20(cToken).balanceOf(recipient);

        // enter curvance
        require(
            CToken(cToken).mintFor(amount, recipient),
            "Zapper: error joining Curvance"
        );
        out = IERC20(cToken).balanceOf(recipient) - priorBalance;
    }
}
