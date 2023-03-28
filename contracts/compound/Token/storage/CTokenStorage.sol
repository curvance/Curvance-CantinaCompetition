// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../InterestRateModel/InterestRateModel.sol";
import "../../Comptroller/ComptrollerInterface.sol";
import "./CommonError.sol";

abstract contract CTokenStorage is CommonError {
    ////////// ERRORS //////////
    error FailedFreshnessCheck();
    error CannotEqualZero();
    error ExcessiveValue();
    error TransferNotAllowed();
    error PreviouslyInitialized();
    error RedeemTransferOutNotPossible();
    error BorrowCashNotAvailable();
    error SelfLiquidiationNotAllowed();
    error ComptrollerMismatch();
    error ValidationFailed();
    error ReduceReservesCashNotAvailable();
    error ReduceReservesCashValidation();

    // Scaler for preserving floating point math precision
    uint256 internal constant expScale = 1e18;

    /**
     * @notice Indicator that this is a CToken contract (for inspection)
     */
    bool public constant isCToken = true;

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public decimals;

    // Maximum borrow rate that can ever be applied (.0005% / block)
    uint256 internal constant borrowRateMaxScaled = 0.0005e16;

    // Maximum fraction of interest that can be set aside for reserves
    uint256 internal constant reserveFactorMaxScaled = 1e18;

    /**
     * @notice Administrator for this contract
     */
    address payable public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address payable public pendingAdmin;

    /**
     * @notice Contract which oversees inter-cToken operations
     */
    ComptrollerInterface public comptroller;

    /**
     * @notice Gauge contract address
     */
    address public gaugePool;

    /**
     * @notice Model which tells what the current interest rate should be
     */
    InterestRateModel public interestRateModel;

    // Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
    uint256 internal initialExchangeRateScaled;

    /**
     * @notice Fraction of interest currently set aside for reserves
     */
    uint256 public reserveFactorScaled;

    /**
     * @notice Block number that interest was last accrued at
     */
    uint256 public accrualBlockNumber;

    /**
     * @notice Accumulator of the total earned interest rate since the opening of the market
     */
    uint256 public borrowIndex;

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    uint256 public totalBorrows;

    /**
     * @notice Total amount of reserves of the underlying held in this market
     */
    uint256 public totalReserves;

    /**
     * @notice Total number of tokens in circulation
     */
    uint256 public totalSupply;

    // Official record of token balances for each account
    mapping(address => uint256) internal accountTokens;

    // Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint256)) internal transferAllowances;

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    // Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /**
     * @notice Share of seized collateral that is added to reserves
     */
    uint256 public constant protocolSeizeShareScaled = 2.8e16; //2.8%
}
