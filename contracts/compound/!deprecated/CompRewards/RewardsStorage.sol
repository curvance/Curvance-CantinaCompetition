// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

abstract contract RewardsStorage {
    /** Storage For Rewards */
    struct CveMarketState {
        // The market's last updated cveBorrowIndex or cveSupplyIndex
        uint224 index;
        // The block number the index was last updated at
        uint32 block;
    }

    /// @notice Accounting storage mapping account addresses to how much CVE they owe the protocol.
    mapping(address => uint256) public cveReceivable;

    // /// @notice The rate at which cve is distributed to the corresponding borrow market (per block)
    mapping(address => uint256) public cveBorrowSpeeds;

    /// @notice The rate at which cve is distributed to the corresponding supply market (per block)
    mapping(address => uint256) public cveSupplySpeeds;

    /// @notice The portion of CVE that each contributor receives per block
    mapping(address => uint256) public cveContributorSpeeds;

    /// @notice Last block at which a contributor's CVE rewards have been allocated
    mapping(address => uint256) public lastContributorBlock;

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

    /// @notice The CVE borrow index for each market for each supplier as of the last time they accrued CVE
    mapping(address => mapping(address => uint256)) public cveSupplierIndex;

    /// @notice The CVE borrow index for each market for each borrower as of the last time they accrued CVE
    mapping(address => mapping(address => uint256)) public cveBorrowerIndex;

    address public comptroller;

    address public admin;

    /// @notice The initial CVE index for a market
    uint224 public constant cveInitialIndex = 1e36;

    uint256 public constant expScale = 1e18;
}
