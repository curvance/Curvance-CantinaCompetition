// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

interface IOracleRouter {
    /// @notice Queries price from the Oracle Router.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view returns (uint256, uint256);

    /// @notice Queries multiple prices from the Oracle Router.
    function getPrices(
        address[] calldata assets,
        bool[] calldata inUSD,
        bool[] calldata getLower
    ) external view returns (uint256[] memory, uint256[] memory);

    /// @notice Queries multiple prices from the Oracle Router
    ///         for a Curvance market.
    function getPricesForMarket(
        address account,
        IMToken[] calldata assets,
        uint256 errorCodeBreakpoint
    )
        external
        view
        returns (AccountSnapshot[] memory, uint256[] memory, uint256);

    /// @notice Notifies the Oracle Router that an asset has been removed
    ///         from the adaptor calling the function.
    function notifyFeedRemoval(address asset) external;

    /// @notice Checks if a given asset is supported by the Oracle Router.
    /// @param asset The address of the asset to check.
    function isSupportedAsset(address asset) external view returns (bool);

    /// @notice Check whether sequencer is valid or down.
    /// @return True if sequencer is valid.
    function isSequencerValid() external view returns (bool);
}
