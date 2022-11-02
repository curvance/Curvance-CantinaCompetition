// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./CToken.sol";
import "./PriceOracle.sol";
import "./interfaces/IRewards.sol";
import { ComptrollerInterface } from "./interfaces/IComptroller.sol";
import "./InterestRateModel/InterestRateModel.sol";
import "./Errors.sol";

contract UnitrollerStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of Unitroller
     */
    address public comptrollerImplementation;

    /**
     * @notice Pending brains of Unitroller
     */
    address public pendingComptrollerImplementation;
}
contract MarketStorage {
    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint256 collateralFactorScaled;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        // Whether or not this market receives CVE
        bool isComped;

        /// TODO Address of rewardToken to amount of rewardToken
        // mapping(address => ) marketRewards;

        /// For supporting staking to multiple endpoints (convex, concentrator)
    }
}
contract ComptrollerStorage is UnitrollerStorage, MarketStorage {

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint256) public borrowCaps;

    /// @notice Oracle which gives the price of any given asset
    PriceOracle public oracle;

    /// @notice Allows connection to the Rewards Contract
    IReward public rewarder;

    /// @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
    uint256 public closeFactorScaled;

    /// @notice Multiplier representing the discount on collateral that a liquidator receives
    uint256 public liquidationIncentiveScaled;

    /// @notice Max number of assets a single account can participate in (borrow or use as collateral)
    uint256 public maxAssets;

    ////////// Market Storage //////////

    // struct Market {
    //     // Whether or not this market is listed
    //     bool isListed;
    //     //  Multiplier representing the most one can borrow against their collateral in this market.
    //     //  For instance, 0.9 to allow borrowing 90% of collateral value.
    //     //  Must be between 0 and 1, and stored as a mantissa.
    //     uint256 collateralFactorScaled;
    //     // Per-market mapping of "accounts in this asset"
    //     mapping(address => bool) accountMembership;
    //     // Whether or not this market receives CVE
    //     bool isComped;

    //     /// TODO Address of rewardToken to amount of rewardToken
    //     // mapping(address => ) marketRewards;

    //     /// For supporting staking to multiple endpoints (convex, concentrator)
    // }

    /**
     * @notice Official mapping of cTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /// @notice A list of all markets
    CToken[] public allMarkets;

    // struct CveMarketState {
    //     // The market's last updated compBorrowIndex or compSupplyIndex
    //     uint224 index;
    //     // The block number the index was last updated at
    //     uint32 block;
    // }

    ////////// Rewards & Yields Accounting //////////

    /// Store the rewards per market
    struct Reward {
        bool isReward;
        uint256 amount;
    }

    // /// @notice The CVE accrued but not yet transferred to each user
    // /// user address to amount accrued
    // mapping(address => uint256) public cveAccrued;

    // /// @notice The rate at which CVE is distributed to the corresponding borrow market (per block)
    // mapping(address => uint256) public cveBorrowSpeeds;

    // /// @notice The rate at which CVE is distributed to the corresponding supply market (per block)
    // mapping(address => uint256) public cveSupplySpeeds;

    // /// @notice Accounting storage mapping account addresses to how much CVE they owe the protocol.
    // mapping(address => uint256) public cveReceivable;


    // /// @notice The CVE borrow index for each market for each supplier as of the last time they accrued COMP
    // mapping(address => mapping(address => uint256)) public cveSupplierIndex;

    // /// @notice The CVE borrow index for each market for each borrower as of the last time they accrued COMP
    // mapping(address => mapping(address => uint256)) public cveBorrowerIndex;
    /// Store the accrued yields for each lending market
    // struct Yields {
    //     // More to do
    // }

    ////////// User Accounting ///////////

    struct User {
        /// All markets a user is in
        mapping(CToken => uint256) userFunds;
        /// Reward Token to accrued balance
        mapping(address => uint256) userBaseRewards;
        /// market to userIsBoosted
        mapping(CToken => bool) userIsBoosted;
    }

    /// TODO
    ///
    struct UserBoosts {
        ///
        mapping(address => uint256) boostFactor;

        /// MarketID to
        // mapping(uint => )
    }

    /// @notice Per-account mapping of "assets you are in", capped by maxAssets
    mapping(address => CToken[]) public accountAssets;

    /// TODO
    /// User address to reward token address to accrued reward amount
    mapping(address => mapping(address => uint256)) userRewards;

    /// Where the user
    // struct UserRewards {
    //     // rewardToken to accrued user rewards
    //     mapping(address => uint) userTokenRewards;
    // }
}

contract CTokenStorage is CTokenErrors {
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

contract CErc20Storage is CErc20Errors {
    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;
}

contract CDelegationStorage is CErc20DelegationErrors {
    /**
     * @notice Implementation address for this contract
     */
    address public implementation;

    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );
}

contract RewardsStorage {
    /** Storage For Rewards */
    struct CveMarketState {
        // The market's last updated compBorrowIndex or compSupplyIndex
        uint224 index;
        // The block number the index was last updated at
        uint32 block;
    }

    /// @notice Accounting storage mapping account addresses to how much COMP they owe the protocol.
    mapping(address => uint) public cveReceivable;

    // /// @notice The rate at which comp is distributed to the corresponding borrow market (per block)
    mapping(address => uint) public cveBorrowSpeeds;

    /// @notice The rate at which comp is distributed to the corresponding supply market (per block)
    mapping(address => uint) public cveSupplySpeeds;

    /// @notice The portion of COMP that each contributor receives per block
    mapping(address => uint) public cveContributorSpeeds;

    /// @notice Last block at which a contributor's COMP rewards have been allocated
    mapping(address => uint) public lastContributorBlock;

    /// @notice The rate at which the flywheel distributes CVE, per block
    uint256 public cveRate;

    /// @notice The portion of cveRate that each market currently receives
    mapping(address => uint256) public cveSpeeds;

    /// @notice The CVE market supply state for each market
    mapping(address => CveMarketState) public cveSupplyState;

    /// @notice The CVE market borrow state for each market
    mapping(address => CveMarketState) public cveBorrowState;

    /// @notice The CVE accrued but not yet transferred to each user
    /// user address to amount accrued
    mapping(address => uint256) public cveAccrued;

    /// @notice The CVE borrow index for each market for each supplier as of the last time they accrued COMP
    mapping(address => mapping(address => uint256)) public cveSupplierIndex;

    /// @notice The CVE borrow index for each market for each borrower as of the last time they accrued COMP
    mapping(address => mapping(address => uint256)) public cveBorrowerIndex;

    /// Local Constants ///
    /// The address for calling the comptroller to obtain state variables
        /**
     * @notice Contract which oversees inter-cToken operations
     */
    // ComptrollerInterface public comptroller;
    address public comptroller;

    address public admin;

    /// @notice The initial COMP index for a market
    uint224 public constant cveInitialIndex = 1e36;

    uint constant expScale = 1e18;

}
