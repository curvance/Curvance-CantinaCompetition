// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BaseWrappedAggregator } from "./BaseWrappedAggregator.sol";
import { IPotLike } from "contracts/interfaces/external/maker/IPotLike.sol";

contract SavingsDaiAggregator is BaseWrappedAggregator {
    address public sDai;
    address public dai;
    address public daiAggregator;

    constructor(address _sDai, address _dai, address _daiAggregator) {
        sDai = _sDai;
        dai = _dai;
        daiAggregator = _daiAggregator;
    }

    /// @notice Returns the underlying aggregator address.
    function underlyingAssetAggregator()
        public
        view
        override
        returns (address)
    {
        return daiAggregator;
    }

    /// @notice Returns the current exchange rate between the wrapped asset
    ///         and the underlying aggregator, in `WAD`.
    function getWrappedAssetWeight() public view override returns (int256) {
        // We divide by 1e9 since chi returns in 1e27 format,
        // so we need to offset by 1e9 to get to standard 1e18 format.
        return SafeCast.toInt256(IPotLike(sDai).chi()) / 1e9;
    }
}
