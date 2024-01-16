// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Zapper } from "contracts/market/zapper/Zapper.sol";
import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { CommonLib } from "contracts/libraries/CommonLib.sol";
import { CurveLib } from "contracts/libraries/CurveLib.sol";
import { BalancerLib } from "contracts/libraries/BalancerLib.sol";
import { VelodromeLib } from "contracts/libraries/VelodromeLib.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/external/ReentrancyGuard.sol";

import { IWETH } from "contracts/interfaces/IWETH.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IBridgeAdapter } from "contracts/interfaces/IBridgeAdapter.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";

contract ZapperBorrow is ReentrancyGuard {
    /// CONSTANTS ///
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// ERRORS ///

    error ZapperBorrow__InvalidSwapper(address invalidSwapper);

    /// CONSTRUCTOR ///

    receive() external payable {}

    constructor(ICentralRegistry centralRegistry_) {
        centralRegistry = centralRegistry_;
    }

    /// EXTERNAL FUNCTIONS ///

    function borrowAndBridge(
        address dToken,
        uint256 borrowAmount,
        SwapperLib.Swap memory swapCall,
        address bridgeAdapter,
        bytes memory bridgeData
    ) external {
        // borrow
        DToken(dToken).borrowFor(msg.sender, address(this), borrowAmount);

        // swap
        if (swapCall.target != address(0)) {
            if (!centralRegistry.isSwapper(swapCall.target)) {
                revert ZapperBorrow__InvalidSwapper(swapCall.target);
            }
            unchecked {
                SwapperLib.swap(swapCall);
            }
        }

        IBridgeAdapter(bridgeAdapter).bridge(msg.sender, bridgeData);
    }
}
