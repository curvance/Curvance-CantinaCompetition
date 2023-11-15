//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGMXDeposit {
    /// TYPES ///

    // @param account the account depositing liquidity
    // @param receiver the address to send the liquidity tokens to
    // @param callbackContract the callback contract
    // @param uiFeeReceiver the ui fee receiver
    // @param market the market to deposit to
    struct Addresses {
        address account;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
    }

    // @param initialLongTokenAmount the amount of long tokens to deposit
    // @param initialShortTokenAmount the amount of short tokens to deposit
    // @param minMarketTokens the minimum acceptable number of liquidity tokens
    // @param updatedAtBlock the block that the deposit was last updated at
    // sending funds back to the user in case the deposit gets cancelled
    // @param executionFee the execution fee for keepers
    // @param callbackGasLimit the gas limit for the callbackContract
    struct Numbers {
        uint256 initialLongTokenAmount;
        uint256 initialShortTokenAmount;
        uint256 minMarketTokens;
        uint256 updatedAtBlock;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    // @param shouldUnwrapNativeToken whether to unwrap the native token when
    struct Flags {
        bool shouldUnwrapNativeToken;
    }

    // @param addresses address values
    // @param numbers number values
    // @param flags boolean values
    struct Props {
        Addresses addresses;
        Numbers numbers;
        Flags flags;
    }
}
