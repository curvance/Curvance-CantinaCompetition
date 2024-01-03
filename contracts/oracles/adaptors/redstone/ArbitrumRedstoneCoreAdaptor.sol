// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseRedstoneCoreAdaptor } from "contracts/oracles/adaptors/redstone/BaseRedstoneCoreAdaptor.sol";
import { PrimaryProdDataServiceConsumerBase } from "contracts/libraries/redstone/ArbitrumProdDataServiceConsumerBase.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ArbitrumRedstoneCoreAdaptor is BaseRedstoneCoreAdaptor, ArbitrumProdDataServiceConsumerBase {

    /// ERRORS ///

    error ArbitrumRedstoneCoreAdaptor__ChainIsNotSupported();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseRedstoneCoreAdaptor(centralRegistry_) {
        // `redstone-arbitrum-prod` that this oracle adaptor 
        // is configured for should only be on Arbitrum mainnet.
        if (block.chainid != 42161) {
            revert ArbitrumRedstoneCoreAdaptor__ChainIsNotSupported();
        }
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice The minimum number of signer messages to be validated 
    ///         for onchain oracle pricing to validate a price feed.
    function getUniqueSignersThreshold() public view override returns (uint8) {
        return 3;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Extracts price stored in msg.data with the transaction, 
    ///         can be called multiple times in one transaction.
    function  _extractPrice(bytes32 symbolHash) internal override view returns (uint256) {
        return getOracleNumericValueFromTxMsg(symbolHash);
    }

}
