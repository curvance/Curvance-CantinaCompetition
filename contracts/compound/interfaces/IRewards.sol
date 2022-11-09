// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../Token/CToken.sol";

abstract contract IReward { //is ComptrollerStorage {

    
    ////////// EVENTS //////////
    /// @notice Emitted when a new COMP speed is calculated for a market
    event CveSpeedUpdated(CToken indexed cToken, uint newSpeed);
    /// @notice Emitted when a new COMP speed is set for a contributor
    event ContributorCveSpeedUpdated(address indexed contributor, uint newSpeed);
    /// @notice Emitted when COMP is distributed to a supplier
    event DistributedSupplierCve(CToken indexed cToken, address indexed supplier, uint cveDelta, uint cveSupplyIndex);
    /// @notice Emitted when COMP is distributed to a borrower
    event DistributedBorrowerCve(CToken indexed cToken, address indexed borrower, uint cveDelta, uint cveBorrowIndex);
    /// @notice Emitted when COMP is granted by admin
    event CveGranted(address recipient, uint amount); /// changed recipient type CToken to address for error in `_grantComp` function

    function updateCveSupplyIndexExternal(address cTokenCollateral) virtual external;
    function distributeSupplierCveExternal(address cTokenCollateral, address claimer) virtual external;

    // function getCveAddress() virtual external pure returns (address);
    // function getBlockNumber() virtual external view returns (uint);
    // function getAllMarkets() virtual external view returns (CToken[] memory); 
    // function cveSupplySpeeds(address cToken) public view virtual returns(uint);
    // function cveBorrowSpeeds(address cToken) public view virtual returns(uint);
    // function cveSpeeds(address cToken) public view virtual returns(uint);
    // function markets(address cToken) public virtual returns(uint);
}