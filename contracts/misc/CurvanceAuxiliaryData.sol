// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { WAD, DENOMINATOR } from "contracts/libraries/Constants.sol";

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { IFeeAccumulator } from "contracts/interfaces/IFeeAccumulator.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";


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

    /// EXTERNAL FUNCTIONS ///

    function getTotalTVL() external view returns (uint256) {

    }

    function getTotalBorrows() external view returns (uint256) {

    }

    function getMarketTVL(address lendingMarket) external view returns (uint256) {

    }

    function getMarketBorrows(address lendingMarket) external view returns (uint256) {

    }

    function getMarketAssets(address lendingMarket) external view returns (address[] memory) {
        
    }

    function getMarketCollateralAssets(address lendingMarket) external view returns (address[] memory) {
        
    }

    function getMarketDebtAssets(address lendingMarket) external view returns (address[] memory) {
        
    }

    function getTokenTVL(address token) external view returns (uint256) {

    }

    function getTokenBorrows(address token) external view returns (uint256) {

    }

    function getBaseRewards(address token) external view returns (uint256) {

    }

    function getCVERewards(address token) external view returns (uint256) {

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

    /// INTERNAL FUNCTIONS ///

    function _getCVELocker() internal view returns (ICVELocker) {
        return ICVELocker(centralRegistry.cveLocker());
    }

    function _getPriceRouter() internal view returns (IPriceRouter) {
        return IPriceRouter(centralRegistry.priceRouter());
    }

    function _isLendingMarket(address market) internal view returns (bool) {
        return centralRegistry.isLendingMarket(market);
    }

    function _getTokenPrice(address mToken, bool getLower) internal view returns (uint256 price) {
        uint256 errorCode;
        (price, errorCode) = _getPriceRouter().getPrice(mToken, true, getLower);
        // If we could not price the asset, bubble up a price of 0.
        if  (errorCode == 2) {
            price = 0;
            return price;
        }
    }

}
