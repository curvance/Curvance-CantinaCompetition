// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CVEPublicSale {
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// @notice CVE contract address
    address public immutable cve;

    /// @notice Public sale configurations
    uint256 public constant SALE_PERIOD = 3 days;
    uint256 public startTime;
    uint256 public softPrice; // price in ETH (18 decimals)
    uint256 public hardPrice; // price in ETH (18 decimals)
    uint256 public cveAmount;
    address public payToken; // ideally WETH

    /// Errors
    error CVEPublicSale__InvalidCentralRegistry();
    error CVEPublicSale__Unauthorized();
    error CVEPublicSale__InvalidStartTime();
    error CVEPublicSale__AlreadyStarted();
    error CVEPublicSale__InvalidPrice();

    /// Events
    event PublicSaleStarted(uint256 startTime);

    constructor(ICentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CVEPublicSale__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;
        cve = centralRegistry.CVE();
    }

    modifier onlyDaoPermissions() {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert CVEPublicSale__Unauthorized();
        }
        _;
    }

    function start(
        uint256 _startTime,
        uint256 _softPrice,
        uint256 _hardPrice,
        uint256 _cveAmount
    ) external onlyDaoPermissions {
        if (startTime != 0) {
            revert CVEPublicSale__AlreadyStarted();
        }

        if (_startTime < block.timestamp) {
            revert CVEPublicSale__InvalidStartTime();
        }

        if (softPrice >= hardPrice) {
            revert();
        }

        startTime = _startTime;
        softPrice = _softPrice;
        hardPrice = _hardPrice;
        cveAmount = _cveAmount;

        emit PublicSaleStarted(_startTime);
    }

    function buy(uint256 amount) external {}

    function withdrawRemainingCVE() external onlyDaoPermissions {
        if (block.timestamp < startTime + SALE_PERIOD) {
            revert();
        }

        uint256 remaining = IERC20(cve).balanceOf(address(this));
        SafeTransferLib.safeTransfer(cve, msg.sender, remaining);
    }
}
