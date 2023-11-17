// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";

contract CVEPublicSale {
    enum SaleStatus {
        NotStarted,
        InSale,
        Closed
    }

    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// @notice CVE contract address
    address public immutable cve;

    /// @notice Public sale configurations
    uint256 public constant SALE_PERIOD = 3 days;
    uint256 public startTime;
    uint256 public softPriceInpaymentToken; // price in WETH (18 decimals)
    uint256 public hardPriceInpaymentToken; // price in WETH (18 decimals)
    uint256 public cveAmountForSale;
    address public paymentToken; // ideally WETH
    uint256 public paymentTokenPrice;

    uint256 public saleCommitted;
    mapping(address => uint256) public userCommitted;

    /// Errors
    error CVEPublicSale__InvalidCentralRegistry();
    error CVEPublicSale__Unauthorized();
    error CVEPublicSale__InvalidStartTime();
    error CVEPublicSale__InvalidPrice();
    error CVEPublicSale__InvalidPriceSource();
    error CVEPublicSale__NotStarted();
    error CVEPublicSale__AlreadyStarted();
    error CVEPublicSale__InSale();
    error CVEPublicSale__Closed();

    /// Events
    event PublicSaleStarted(uint256 startTime);
    event Committed(address user, uint256 payAmount);
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
    /// @param _softPriceInUSD public sale base token price (in USD)
    /// @param _hardPriceInUSD public sale hard token price (in USD)
    /// @param _cveAmountForSale public sale CVE amount base cap
    /// @param _paymentToken public sale pay token address
    function start(
        uint256 _startTime,
        uint256 _softPriceInUSD,
        uint256 _hardPriceInUSD,
        uint256 _cveAmountForSale,
        address _paymentToken
    ) external onlyDaoPermissions {
        if (startTime != 0) {
            revert CVEPublicSale__AlreadyStarted();
        }

        if (_startTime < block.timestamp) {
            revert CVEPublicSale__InvalidStartTime();
        }

        if (_softPriceInUSD >= _hardPriceInUSD) {
            revert CVEPublicSale__InvalidPrice();
        }

        uint256 err;
        (paymentTokenPrice, err) = IPriceRouter(centralRegistry.priceRouter())
            .getPrice(_paymentToken, true, true);

        // Make sure that we didnt have a catastrophic error when pricing
        // the payment token
        if (err == 2) {
            revert CVEPublicSale__InvalidPriceSource();
        }

        startTime = _startTime;
        softPriceInpaymentToken = (_softPriceInUSD * 1e18) / paymentTokenPrice;
        hardPriceInpaymentToken = (_hardPriceInUSD * 1e18) / paymentTokenPrice;
        cveAmountForSale = _cveAmountForSale;
        paymentToken = _paymentToken;

        emit PublicSaleStarted(_startTime);
    }

    function commit(uint256 payAmount) external {
        SaleStatus saleStatus = currentStatus();
        if (saleStatus == SaleStatus.NotStarted) {
            revert CVEPublicSale__NotStarted();
        }

        if (saleStatus == SaleStatus.Closed) {
            revert CVEPublicSale__Closed();
        }

        uint256 remaining = hardCap() - saleCommitted;

        if (payAmount > remaining) {
            // users can commit for only remaining amount
            payAmount = remaining;
        }

        SafeTransferLib.safeTransferFrom(
            paymentToken,
            msg.sender,
            address(this),
            payAmount
        );

        userCommitted[msg.sender] += payAmount;
        saleCommitted += payAmount;

        emit Committed(msg.sender, payAmount);
    }

    function claim() external returns (uint256 cveAmount) {
        SaleStatus saleStatus = currentStatus();
        if (saleStatus == SaleStatus.NotStarted) {
            revert CVEPublicSale__NotStarted();
        }
        if (saleStatus == SaleStatus.InSale) {
            revert CVEPublicSale__InSale();
        }

        uint256 payAmount = userCommitted[msg.sender];
        userCommitted[msg.sender] = 0;

        uint256 price = currentPrice();
        cveAmount = (payAmount * 1e18) / price;

        SafeTransferLib.safeTransfer(cve, msg.sender, cveAmount);

        emit Claimed(msg.sender, cveAmount);
    }

    /// @notice return sale soft cap
    function softCap() public view returns (uint256) {
        return (softPriceInpaymentToken * cveAmountForSale) / 1e18;
    }

    /// @notice return sale hard cap
    function hardCap() public view returns (uint256) {
        return (hardPriceInpaymentToken * cveAmountForSale) / 1e18;
    }

    /// @notice return sale price from sale committed
    function priceAt(uint256 _saleCommitted) public view returns (uint256) {
        uint256 _softCap = softCap();
        if (_saleCommitted < _softCap) {
            return softPriceInpaymentToken;
        }
        uint256 _hardCap = hardCap();
        if (_saleCommitted >= _hardCap) {
            return hardPriceInpaymentToken;
        }

        return (_saleCommitted * 1e18) / cveAmountForSale;
    }

    /// @notice return current sale price
    /// @dev current sale price is calculated based on sale committed
    function currentPrice() public view returns (uint256) {
        return priceAt(saleCommitted);
    }

    function currentStatus() public view returns (SaleStatus) {
        if (startTime == 0 || block.timestamp < startTime) {
            return SaleStatus.NotStarted;
        }

        if (
            block.timestamp < startTime + SALE_PERIOD &&
            saleCommitted < hardCap()
        ) {
            return SaleStatus.InSale;
        }

        return SaleStatus.Closed;
    }

    /// @notice withdraw funds
    /// @dev (only dao permissions)
    ///      this function is only available when the public sale is over
    function withdrawFunds() external onlyDaoPermissions {
        SaleStatus saleStatus = currentStatus();
        if (saleStatus == SaleStatus.NotStarted) {
            revert CVEPublicSale__NotStarted();
        }
        if (saleStatus == SaleStatus.InSale) {
            revert CVEPublicSale__InSale();
        }

        uint256 balance = IERC20(paymentToken).balanceOf(address(this));
        SafeTransferLib.safeTransfer(paymentToken, centralRegistry.daoAddress(), balance);
    }
}
