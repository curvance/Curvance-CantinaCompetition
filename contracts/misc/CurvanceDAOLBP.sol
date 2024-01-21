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
    /// TYPES ///

    enum SaleStatus {
        NotStarted,
        InSale,
        Closed
    }

    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// @notice CVE contract address.
    address public immutable cve;

    /// PUBLIC SALE CONFIGURATIONS

    /// @notice The duration of the LBP.
    uint256 public constant SALE_PERIOD = 3 days;

    /// STORAGE ///

    /// @notice The starting timestamp of the LBP, in unix time.
    uint256 public startTime;
    /// @notice The number of CVE tokens up for grabs from the DAO.
    uint256 public cveAmountForSale;
    /// @notice Initial soft cap price, in `paymentToken`.
    uint256 public softPriceInpaymentToken;
    /// @notice Payment token can be any ERC20, but never gas tokens.
    address public paymentToken;
    /// @notice Decimals for `paymentToken`.
    uint8 public paymentTokenDecimals;
    /// @notice Cached price of paymentToken, locked in during start() call.
    uint256 public paymentTokenPrice;
    /// @notice The amount of decimals to adjust between paymentToken and CVE.
    uint256 public saleDecimalAdjustment; 
    /// @notice The number of `paymentToken` committed to the LBP.
    uint256 public saleCommitted;

    /// @notice User => paymentTokens committed.
    mapping(address => uint256) public userCommitted;

    /// ERRORS ///

    error CurvanceDAOLBP__InvalidCentralRegistry();
    error CurvanceDAOLBP__Unauthorized();
    error CurvanceDAOLBP__InvalidStartTime();
    error CurvanceDAOLBP__InvalidPrice();
    error CurvanceDAOLBP__InvalidPriceSource();
    error CurvanceDAOLBP__NotStarted();
    error CurvanceDAOLBP__AlreadyStarted();
    error CurvanceDAOLBP__InSale();
    error CurvanceDAOLBP__Closed();

    /// EVENTS ///

    event LBPStarted(uint256 startTime);
    event Committed(address user, uint256 payAmount);
    event Claimed(address user, uint256 cveAmount);

    /// CONSTRUCTOR ///

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

    /// EXTERNAL FUNCTIONS ///

    /// @notice Starts the configuration of the LBP.
    /// @param startTimestamp LBP start timestamp, in unix time.
    /// @param softPriceInUSD LBP base token price, in USD.
    /// @param cveAmountInLBP CVE amount included in LBP.
    /// @param paymentTokenAddress The address of the payment token.
    function start(
        uint256 startTimestamp,
        uint256 softPriceInUSD,
        uint256 cveAmountInLBP,
        address paymentTokenAddress
    ) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert CurvanceDAOLBP__Unauthorized();
        }

        if (startTime != 0) {
            revert CurvanceDAOLBP__AlreadyStarted();
        }

        if (startTimestamp < block.timestamp) {
            revert CurvanceDAOLBP__InvalidStartTime();
        }

        uint256 errorCode;
        (paymentTokenPrice, errorCode) = IOracleRouter(centralRegistry.oracleRouter())
            .getPrice(paymentTokenAddress, true, true);

        // Make sure that we didnt have a catastrophic error when pricing
        // the payment token.
        if (errorCode == 2) {
            revert CurvanceDAOLBP__InvalidPriceSource();
        }

        startTime = startTimestamp;
        softPriceInpaymentToken = (softPriceInUSD * WAD) / paymentTokenPrice;
        cveAmountForSale = cveAmountInLBP;
        paymentToken = paymentTokenAddress;
        paymentTokenDecimals = IERC20(paymentTokenAddress).decimals();

        emit LBPStarted(startTimestamp);
    }

    /// @notice Processes a LBP conmmitment, a caller can commit
    ///         `paymentToken` for the caller to receive a proportional
    ///         share of CVE from Curvance DAO.
    /// @param amount The amount of `paymentToken` to commit.
    function commit(uint256 amount) external {
        // Validate that LBP is active.
        _canCommit();

        // Take commitment.
        SafeTransferLib.safeTransferFrom(
            paymentToken,
            msg.sender,
            address(this),
            amount
        );

        // Document commitment for caller.
        _commit(amount, msg.sender);
    }

    /// @notice Processes a LBP conmmitment, a caller can commit
    ///         `paymentToken` for `recipient` to receive a proportional
    ///         share of CVE from Curvance DAO.
    /// @param amount The amount of `paymentToken` to commit.
    /// @param recipient The address of the user who should benefit from
    ///                  the commitment.
    function commitFor(uint256 amount, address recipient) external {
        // Validate that LBP is active.
        _canCommit();

        // Take commitment.
        SafeTransferLib.safeTransferFrom(
            paymentToken,
            msg.sender,
            address(this),
            amount
        );

        // Document commitment for `recipient`.
        _commit(amount, recipient);
    }

    /// @notice Distributes a callers CVE owed from prior commitments.
    /// @dev Only callable after the conclusion of the LBP.
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

    /// PERMISSIONED EXTERNAL FUNCTIONS ///

    /// @notice Withdraws LBP funds to DAO address.
    /// @dev Only callable on the conclusion of the LBP.
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

    /// PUBLIC FUNCTIONS ///

    /// @notice Returns the current soft cap limit, in `paymentToken`.
    function softCap() public view returns (uint256) {
        return (softPriceInpaymentToken * cveAmountForSale) / WAD;
    }

    /// @notice Returns the current LBP price based on current commitments.
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

    /// @notice Returns the current price based on current commitments.
    function currentPrice() public view returns (uint256) {
        return priceAt(saleCommitted);
    }

    /// @notice Returns the current status of the Curvance DAO LBP.
    function currentStatus() public view returns (SaleStatus) {
        if (startTime == 0 || block.timestamp < startTime) {
            return SaleStatus.NotStarted;
        }

        if (block.timestamp < startTime + SALE_PERIOD) {
            return SaleStatus.InSale;
        }

        return SaleStatus.Closed;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Preconditional check to determine whether the LBP is active.
    function _canCommit() internal {
        SaleStatus saleStatus = currentStatus();
        if (saleStatus == SaleStatus.NotStarted) {
            revert CurvanceDAOLBP__NotStarted();
        }

        if (saleStatus == SaleStatus.Closed) {
            revert CurvanceDAOLBP__Closed();
        }
    }

    /// @notice Documents a commitment of `amount` for `recipient`.
    /// @param amount The amount of `paymentToken` committed.
    /// @param recipient The address of the user who should benefit from
    ///                  the commitment.
    function _commit(uint256 amount, address recipient) internal {
        userCommitted[recipient] += amount;
        saleCommitted += amount;

        emit Committed(recipient, amount);
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
