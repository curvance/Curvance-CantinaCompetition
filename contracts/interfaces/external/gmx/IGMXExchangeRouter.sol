//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGMXExchangeRouter {
    /// TYPES ///

    // @dev CreateDepositParams struct used in createDeposit.
    // @param receiver the address to send the market tokens to.
    // @param callbackContract the callback contract.
    // @param uiFeeReceiver the ui fee receiver.
    // @param market the market to deposit into.
    // @param minMarketTokens the minimum acceptable number of liquidity tokens.
    // @param shouldUnwrapNativeToken whether to unwrap the native token when.
    // sending funds back to the user in case the deposit gets cancelled.
    // @param executionFee the execution fee for keepers.
    // @param callbackGasLimit the gas limit for the callbackContract.
    struct CreateDepositParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minMarketTokens;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    /// FUNCTIONS ///

    /// @dev Wraps the specified amount of native tokens into WNT
    ///      then sends the WNT to the specified address.
    function sendWnt(address receiver, uint256 amount) external payable;

    /// @dev Sends the given amount of tokens to the given address.
    function sendTokens(
        address token,
        address receiver,
        uint256 amount
    ) external payable;

    /// @dev Creates a new deposit with the given long token, short token,
    ///      long token amount, short token amount, and deposit parameters.
    /// @param params The deposit parameters.
    /// @return The unique ID of the newly created deposit.
    function createDeposit(
        CreateDepositParams calldata params
    ) external payable returns (bytes32);

    /// @dev Claims funding fees for the given markets and tokens on behalf of
    ///      the caller, and sends the fees to the specified receiver.
    /// @param markets An array of market addresses
    /// @param tokens An array of token addresses, corresponding to the given markets
    /// @param receiver The address to which the claimed fees should be sent
    function claimFundingFees(
        address[] memory markets,
        address[] memory tokens,
        address receiver
    ) external payable returns (uint256[] memory);

    /// @dev Receives and executes a batch of function calls on this contract.
    function multicall(
        bytes[] calldata data
    ) external payable returns (bytes[] memory results);
}
