// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../PriceOracle.sol";
import "../Unitroller/UnitrollerStorage.sol";
import "../CompRewards/RewardsInterface.sol";

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
    RewardsInterface public rewarder;

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
