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

    /// Errors
    error CVEPublicSale__InvalidCentralRegistry();
    error CVEPublicSale__Unauthorized();
    error CVEPublicSale__InvalidStartTime();
    error CVEPublicSale__NotStarted();
    error CVEPublicSale__AlreadyStarted();
    error CVEPublicSale__InvalidPrice();
    error CVEPublicSale__InSale();
    error CVEPublicSale__HardCap();

    /// Events
    event PublicSaleStarted(uint256 startTime);
    event Sold(uint256 wethAmount, uint256 cveAmount);

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

    /// @notice buy CVE with WETH
    function buy(
        uint256 wethAmount
    ) external returns (uint256 totalBuyAmount) {
        SafeTransferLib.safeTransferFrom(
            weth,
            msg.sender,
            address(this),
            wethAmount
        );

        totalBuyAmount = preBuy(wethAmount);
        saleCommitted += wethAmount;

        SafeTransferLib.safeTransfer(cve, msg.sender, totalBuyAmount);

        emit Sold(wethAmount, totalBuyAmount);
    }

    /// @notice pre calculation for buy
    function preBuy(
        uint256 wethAmount
    ) public view returns (uint256 totalBuyAmount) {
        if (startTime == 0 || block.timestamp < startTime) {
            revert CVEPublicSale__NotStarted();
        }

        uint256 _saleCommitted = saleCommitted;
        uint256 _softCap = softCap();
        if (_saleCommitted < _softCap) {
            // try until soft cap

            if (_saleCommitted + wethAmount <= _softCap) {
                // buy all with soft price

                totalBuyAmount += (wethAmount * 1e18) / softPrice;
                wethAmount = 0;
                _saleCommitted += wethAmount;
            } else {
                uint256 buyAmount = _softCap - _saleCommitted;
                totalBuyAmount += (buyAmount * 1e18) / softPrice;
                wethAmount -= buyAmount;
                _saleCommitted += buyAmount;
            }
        }

        if (wethAmount > 0) {
            // try until hardcap
            uint256 startPrice = _priceAt(_saleCommitted);
            uint256 endPrice = _priceAt(_saleCommitted + wethAmount);
            uint256 averagePrice = (startPrice + endPrice) / 2;

            totalBuyAmount += (wethAmount * 1e18) / averagePrice;
            wethAmount -= wethAmount;
            _saleCommitted += wethAmount;
        }

        if (_saleCommitted > hardCap()) {
            revert CVEPublicSale__HardCap();
        }
    }

    /// @notice buy CVE with WETH
    function buyExact(uint256 cveAmount) external returns (uint256 payAmount) {
        payAmount = preBuyExact(cveAmount);

        SafeTransferLib.safeTransferFrom(
            weth,
            msg.sender,
            address(this),
            payAmount
        );

        saleCommitted += payAmount;

        SafeTransferLib.safeTransfer(cve, msg.sender, cveAmount);

        emit Sold(payAmount, cveAmount);
    }

    /// @notice pre calculation for buyExact
    function preBuyExact(
        uint256 cveAmount
    ) public view returns (uint256 payAmount) {
        if (startTime == 0 || block.timestamp < startTime) {
            revert CVEPublicSale__NotStarted();
        }

        uint256 _saleCommitted = saleCommitted;
        uint256 _softCap = softCap();
        if (_saleCommitted < _softCap) {
            // try until soft cap

            if (_saleCommitted + (cveAmount * softPrice) / 1e18 <= _softCap) {
                // buy all with soft price

                payAmount += (cveAmount * softPrice) / 1e18;
                cveAmount = 0;
                _saleCommitted += payAmount;
            } else {
                uint256 buyAmount = (_softCap - _saleCommitted);
                payAmount += buyAmount;
                cveAmount -= (buyAmount * 1e18) / softPrice;
                _saleCommitted += buyAmount;
            }
        }

        if (cveAmount > 0) {
            // try until hardcap
            uint256 _cveAllocationForHardCap = cveAllocationForHardCap();

            uint256 startPrice = _priceAt(_saleCommitted);
            // this formula is from following
            // hardPrice / cveAllocationForHardCap = (endPrice - startPrice) / cveAmount
            uint256 endPrice = startPrice +
                (cveAmount * hardPrice) /
                _cveAllocationForHardCap;

            uint256 averagePrice = (startPrice + endPrice) / 2;

            uint256 buyAmount = (cveAmount * averagePrice) / 1e18;
            payAmount += buyAmount;
            cveAmount = 0;
            _saleCommitted += buyAmount;
        }

        if (_saleCommitted > hardCap()) {
            revert CVEPublicSale__HardCap();
        }
    }

    /// @notice return sale soft cap
    function softCap() public view returns (uint256) {
        return (softPrice * cveAmountForSale) / 1e18;
    }

    /// @notice return sale hard cap
    function hardCap() public view returns (uint256) {
        return (hardPrice * cveAmountForSale) / 1e18;
    }

    function cveAllocationForHardCap() public view returns (uint256) {
        uint256 _softCap = softCap();
        uint256 _hardCap = hardCap();
        // this formula is from following
        // cveAllocationForHardCap * ((hardPrice + softPrice) / 2) = _hardCap - _softCap
        return ((_hardCap - _softCap) * 2) / (hardPrice + softPrice);
    }

    /// @notice return current sale price
    /// @dev current sale price is calculated based on sale committed
    function currentPrice() external view returns (uint256) {
        return _priceAt(saleCommitted);
    }

    /// @notice withdraw remaining CVE
    /// @dev (only dao permissions)
    ///      this function is only available when the public sale is over
    function withdrawRemainingCVE() external onlyDaoPermissions {
        if (block.timestamp < startTime + SALE_PERIOD) {
            revert CVEPublicSale__InSale();
        }

        uint256 remaining = IERC20(cve).balanceOf(address(this));
        SafeTransferLib.safeTransfer(cve, msg.sender, remaining);
    }

    /// @notice return sale price from sale committed
    function _priceAt(uint256 _saleCommitted) internal view returns (uint256) {
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
}
