// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IFeeAccumulator } from "contracts/interfaces/IFeeAccumulator.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";
import { WAD, DENOMINATOR } from "contracts/libraries/Constants.sol";

/// @notice An auxiliary contract for querying nuanced data 
///         inside the Curvance ecosystem.
contract CurvanceAuxiliaryData {

    /// STORAGE ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// ERRORS ///

    error CurvanceAuxiliaryData__ParametersMisconfigured();
    error CurvanceAuxiliaryData__InvalidCentralRegistry();
    error CurvanceAuxiliaryData__Unauthorized();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CurvanceAuxiliaryData__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_; 
    }

    function getPrices(
        address[] calldata assets,
        bool[] calldata inUSD,
        bool[] calldata getLower
    ) external view returns (uint256[] memory, uint256[] memory) {
        return _getPriceRouter().getPrices(assets, inUSD, getLower);
    }

    function hasRewards(address user) external view returns (bool) {
        return _getCVELocker().hasRewardsToClaim(user);
    }

    function _getCVELocker() internal view returns (ICVELocker) {
        return ICVELocker(centralRegistry.cveLocker());
    }

    function _getPriceRouter() internal view returns (IPriceRouter) {
        return IPriceRouter(centralRegistry.priceRouter());
    }

    function _isLendingMarket(address market) internal view returns (bool) {
        return centralRegistry.isLendingMarket(market);
    }

}
