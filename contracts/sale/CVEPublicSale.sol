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
    uint256 public softPrice; // price in WETH (18 decimals)
    uint256 public hardPrice; // price in WETH (18 decimals)
    uint256 public cveAmountForSale;
    address public weth;

    uint256 public saleCommitted;
    mapping(address => uint256) public userCommitted;

    /// Errors
    error CVEPublicSale__InvalidCentralRegistry();
    error CVEPublicSale__Unauthorized();
    error CVEPublicSale__InvalidStartTime();
    error CVEPublicSale__NotStarted();
    error CVEPublicSale__AlreadyStarted();
    error CVEPublicSale__InSale();
    error CVEPublicSale__Ended();
    error CVEPublicSale__InvalidPrice();

    /// Events
    event PublicSaleStarted(uint256 startTime);
    event Committed(address user, uint256 wethAmount);
    event Claimed(address user, uint256 cveAmount);

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

    /// @notice start public sale
    /// @param _startTime public sale start timestamp (in seconds)
    /// @param _softPrice public sale base token price (in payToken)
    /// @param _hardPrice public sale hard token price (in payToken)
    /// @param _cveAmountForSale public sale CVE amount base cap
    /// @param _weth public sale pay token address
    function start(
        uint256 _startTime,
        uint256 _softPrice,
        uint256 _hardPrice,
        uint256 _cveAmountForSale,
        address _weth
    ) external onlyDaoPermissions {
        if (startTime != 0) {
            revert CVEPublicSale__AlreadyStarted();
        }

        if (_startTime < block.timestamp) {
            revert CVEPublicSale__InvalidStartTime();
        }

        if (softPrice >= hardPrice) {
            revert CVEPublicSale__InvalidPrice();
        }

        startTime = _startTime;
        softPrice = _softPrice;
        hardPrice = _hardPrice;
        cveAmountForSale = _cveAmountForSale;
        weth = _weth;

        emit PublicSaleStarted(_startTime);
    }

    function commit(uint256 wethAmount) external {
        if (startTime == 0 || block.timestamp < startTime) {
            revert CVEPublicSale__NotStarted();
        }

        uint256 remaining = hardCap() - saleCommitted;

        if (remaining == 0) {
            revert CVEPublicSale__Ended();
        }

        if (wethAmount > remaining) {
            // users can commit for only remaining amount
            wethAmount = remaining;
        }

        SafeTransferLib.safeTransferFrom(
            weth,
            msg.sender,
            address(this),
            wethAmount
        );

        userCommitted[msg.sender] += wethAmount;

        emit Committed(msg.sender, wethAmount);
    }

    function claim() external returns (uint256 cveAmount) {
        if (startTime == 0 || block.timestamp < startTime) {
            revert CVEPublicSale__NotStarted();
        }
        if (block.timestamp < startTime + SALE_PERIOD) {
            revert CVEPublicSale__InSale();
        }

        uint256 wethAmount = userCommitted[msg.sender];
        userCommitted[msg.sender] = 0;

        uint256 price = currentPrice();
        cveAmount = (wethAmount * 1e18) / price;

        SafeTransferLib.safeTransfer(weth, msg.sender, wethAmount);

        emit Claimed(msg.sender, cveAmount);
    }

    /// @notice return sale soft cap
    function softCap() public view returns (uint256) {
        return (softPrice * cveAmountForSale) / 1e18;
    }

    /// @notice return sale hard cap
    function hardCap() public view returns (uint256) {
        return (hardPrice * cveAmountForSale) / 1e18;
    }

    /// @notice return sale price from sale committed
    function priceAt(uint256 _saleCommitted) public view returns (uint256) {
        uint256 _softCap = softCap();
        if (_saleCommitted < _softCap) {
            return softPrice;
        }
        uint256 _hardCap = hardCap();
        if (_saleCommitted >= _hardCap) {
            return hardPrice;
        }

        return softPrice + (_saleCommitted - _softCap) / cveAmountForSale;
    }

    /// @notice return current sale price
    /// @dev current sale price is calculated based on sale committed
    function currentPrice() public view returns (uint256) {
        return priceAt(saleCommitted);
    }

    function inSale() public view returns (bool) {
        return
            startTime != 0 &&
            startTime < block.timestamp &&
            block.timestamp < startTime + SALE_PERIOD;
    }

    /// @notice withdraw remaining CVE
    /// @dev (only dao permissions)
    ///      this function is only available when the public sale is over
    function withdrawRemainingCVE() external onlyDaoPermissions {
        if (startTime == 0 || block.timestamp < startTime) {
            revert CVEPublicSale__NotStarted();
        }
        if (block.timestamp < startTime + SALE_PERIOD) {
            revert CVEPublicSale__InSale();
        }

        uint256 remaining = IERC20(cve).balanceOf(address(this));
        SafeTransferLib.safeTransfer(cve, msg.sender, remaining);
    }
}
