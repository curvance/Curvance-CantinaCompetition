// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { FixedPointMathLib } from "contracts/libraries/external/FixedPointMathLib.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";

contract CurvanceDAOLBP {
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
    uint256 public cveAmountForSale;
    address public paymentToken; // ideally WETH
    uint8 public paymentTokenDecimals; // ideally WETH
    uint256 public paymentTokenPrice;
    uint256 public saleDecimalAdjustment; 

    uint256 public saleCommitted;
    mapping(address => uint256) public userCommitted;

    /// Errors
    error CurvanceDAOLBP__InvalidCentralRegistry();
    error CurvanceDAOLBP__Unauthorized();
    error CurvanceDAOLBP__InvalidStartTime();
    error CurvanceDAOLBP__InvalidPrice();
    error CurvanceDAOLBP__InvalidPriceSource();
    error CurvanceDAOLBP__NotStarted();
    error CurvanceDAOLBP__AlreadyStarted();
    error CurvanceDAOLBP__InSale();
    error CurvanceDAOLBP__Closed();

    /// Events
    event LBPStarted(uint256 startTime);
    event Committed(address user, uint256 payAmount);
    event Claimed(address user, uint256 cveAmount);

    constructor(ICentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CurvanceDAOLBP__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;
        cve = centralRegistry.cve();
    }

    /// @notice start public sale
    /// @param _startTime public sale start timestamp (in seconds)
    /// @param _softPriceInUSD public sale base token price (in USD)
    /// @param _cveAmountForSale public sale CVE amount base cap
    /// @param _paymentToken public sale pay token address
    function start(
        uint256 _startTime,
        uint256 _softPriceInUSD,
        uint256 _cveAmountForSale,
        address _paymentToken
    ) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert CurvanceDAOLBP__Unauthorized();
        }

        if (startTime != 0) {
            revert CurvanceDAOLBP__AlreadyStarted();
        }

        if (_startTime < block.timestamp) {
            revert CurvanceDAOLBP__InvalidStartTime();
        }

        uint256 err;
        (paymentTokenPrice, err) = IOracleRouter(centralRegistry.oracleRouter())
            .getPrice(_paymentToken, true, true);

        // Make sure that we didnt have a catastrophic error when pricing
        // the payment token
        if (err == 2) {
            revert CurvanceDAOLBP__InvalidPriceSource();
        }

        startTime = _startTime;
        softPriceInpaymentToken = (_softPriceInUSD * WAD) / paymentTokenPrice;
        cveAmountForSale = _cveAmountForSale;
        paymentToken = _paymentToken;
        if (_paymentToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            paymentTokenDecimals = 18;
        } else {
            paymentTokenDecimals = IERC20(_paymentToken).decimals();
        }

        emit LBPStarted(_startTime);
    }

    function commit(uint256 amount) external {
        SaleStatus saleStatus = currentStatus();
        if (saleStatus == SaleStatus.NotStarted) {
            revert CurvanceDAOLBP__NotStarted();
        }

        if (saleStatus == SaleStatus.Closed) {
            revert CurvanceDAOLBP__Closed();
        }

        SafeTransferLib.safeTransferFrom(
            paymentToken,
            msg.sender,
            address(this),
            amount
        );

        userCommitted[msg.sender] += amount;
        saleCommitted += amount;

        emit Committed(msg.sender, amount);
    }

    function claim() external returns (uint256 amount) {
        SaleStatus saleStatus = currentStatus();
        if (saleStatus == SaleStatus.NotStarted) {
            revert CurvanceDAOLBP__NotStarted();
        }
        if (saleStatus == SaleStatus.InSale) {
            revert CurvanceDAOLBP__InSale();
        }

        uint256 payAmount = userCommitted[msg.sender];
        userCommitted[msg.sender] = 0;

        uint256 price = currentPrice();
        amount = (payAmount * WAD) / price;

        SafeTransferLib.safeTransfer(cve, msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    /// @notice return sale soft cap
    function softCap() public view returns (uint256) {
        return (softPriceInpaymentToken * cveAmountForSale) / WAD;
    }

    /// @notice return sale price from sale committed
    function priceAt(
        uint256 amount
    ) public view returns (uint256 price) {
        uint256 _softCap = softCap();
        if (amount < _softCap) {
            return softPriceInpaymentToken;
        }

        // Adjust decimals between paymentTokenDecimals,
        // and default 18 decimals of softCap(). 
        amount = _adjustDecimals(amount, paymentTokenDecimals, 18);

        // Equivalent to (amount * WAD) / cveAmountForSale rounded up.
        return FixedPointMathLib.divWadUp(amount, cveAmountForSale);
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

        if (block.timestamp < startTime + SALE_PERIOD) {
            return SaleStatus.InSale;
        }

        return SaleStatus.Closed;
    }

    /// @notice withdraw funds
    /// @dev (only dao permissions)
    ///      this function is only available when the public sale is over
    function withdrawFunds() external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert CurvanceDAOLBP__Unauthorized();
        }

        SaleStatus saleStatus = currentStatus();
        if (saleStatus == SaleStatus.NotStarted) {
            revert CurvanceDAOLBP__NotStarted();
        }
        if (saleStatus == SaleStatus.InSale) {
            revert CurvanceDAOLBP__InSale();
        }

        uint256 balance = IERC20(paymentToken).balanceOf(address(this));
        SafeTransferLib.safeTransfer(
            paymentToken,
            centralRegistry.daoAddress(),
            balance
        );
    }

    /// @dev Converting `amount` into proper form between potentially two
    ///      different decimal forms.
    function _adjustDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * 10 ** (toDecimals - fromDecimals);
        } else {
            return amount / 10 ** (fromDecimals - toDecimals);
        }
    }
}
