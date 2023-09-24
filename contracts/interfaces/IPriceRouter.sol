// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

interface IPriceRouter {
    /// @notice queries price from an oracle adaptor
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view returns (uint256, uint256);

    function getPricesForMarket(
        address account,
        IMToken[] calldata assets, 
        uint256 errorCodeBreakpoint
    ) external view returns (AccountSnapshot [] memory, uint256[] memory, uint256);

    /// @notice Notifies the price router that an asset has been removed
    ///         from the adaptor calling the function
    function notifyAssetPriceFeedRemoval(address asset) external;

    function isSupportedAsset(address asset) external view returns (bool);
}
