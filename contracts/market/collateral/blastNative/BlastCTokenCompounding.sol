// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, ICentralRegistry, IERC20 } from "contracts/market/collateral/CTokenCompounding.sol";

import { IBlastNativeYieldManager } from "contracts/interfaces/blast/IBlastNativeYieldManager.sol";
import { IBlastCentralRegistry } from "contracts/interfaces/blast/IBlastCentralRegistry.sol";
import { IBlast } from "contracts/interfaces/external/blast/IBlast.sol";
import { IERC20Rebasing } from "contracts/interfaces/external/blast/IERC20Rebasing.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";

contract BlastCTokenCompounding is CTokenCompounding {

    /// CONSTANTS ///

    
    /// @notice The address of Curvance's native Yield Manager.
    address public immutable nativeYieldManager;
    /// @notice The address managing ETH/Gas yield.
    IBlast public constant CHAIN_YIELD_MANAGER = IBlast(0x4300000000000000000000000000000000000002);
    /// @notice The address managing WETH yield, also the token itself.
    /// @dev Will change when deploying to mainnet.
    IERC20Rebasing public constant WETH_YIELD_MANAGER = IERC20Rebasing(0x4200000000000000000000000000000000000023);

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_
    ) CTokenCompounding(
        centralRegistry_,
        asset_,
        marketManager_
    ) {
        nativeYieldManager = IBlastCentralRegistry(address(centralRegistry_)).nativeYieldManager();
    }

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards.
    /// @dev NOTE: Needs to be overridden in each BlastCTokenCompounding
    ///      composable asset, this needs to be asset to asset so Gelato
    ///      can swap into proper underlyings.
    /// @return yield The amount of new assets acquired from compounding
    ///               vault yield.
    function harvest(
        bytes calldata
    ) external virtual override returns (uint256 yield) {
        yield = CHAIN_YIELD_MANAGER.claimMaxGas(
            address(this),
            address(this)
        );

        if (yield > 0) {
            IWETH(address(WETH_YIELD_MANAGER)).deposit{ value: yield }();
        }

        IBlastNativeYieldManager(nativeYieldManager).claimYieldForAutoCompounding(
            address(marketManager),
            true,
            true
        );
    }
}
