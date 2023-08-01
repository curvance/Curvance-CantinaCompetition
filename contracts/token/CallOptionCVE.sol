// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CallOptionCVE is ERC20 {
    /// CONSTANTS ///

    /// @notice Will need to offset to match differential in decimals between
    ///         strike price vs oracle pricing
    uint256 public constant denominatorOffset = 1e18;

    ICentralRegistry public immutable centralRegistry;
    address public immutable cve;
    address public immutable paymentToken;
    bytes32 private immutable _name;
    bytes32 private immutable _symbol;

    /// STORAGE ///

    uint256 public paymentTokenPerCVE;

    uint256 optionsStartTimestamp;
    uint256 optionsEndTimestamp;

    /// EVENTS ///

    event RemainingCVEWithdrawn(uint256 amount);
    event CallOptionCVEExercised(address indexed exerciser, uint256 amount);

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "CallOptionCVE: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR ///

    /// @param paymentToken_ The token used for payment when exercising options.
    /// @param centralRegistry_ The Central Registry contract address.
    constructor(
        ICentralRegistry centralRegistry_,
        address paymentToken_
    ) {
        _name = "CVE Options";
        _symbol = "optCVE";

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "CallOptionCVE: invalid central registry"
        );

        centralRegistry = centralRegistry_;
        paymentToken = paymentToken_;
        cve = centralRegistry.CVE();

        // total call option allocation for airdrops
        _mint(msg.sender, 7560001.242 ether);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Rescue any token sent by mistake, also used for removing .
    /// @param token The token to rescue.
    /// @param recipient The address to receive the rescued token.
    /// @param amount The amount of tokens to rescue.
    function rescueToken(
        address token,
        address recipient,
        uint256 amount
    ) external onlyDaoPermissions {
        require(
            recipient != address(0),
            "CallOptionCVE: invalid recipient address"
        );

        if (token == address(0)) {
            require(
                address(this).balance >= amount,
                "CallOptionCVE: insufficient balance"
            );
            (bool success, ) = payable(recipient).call{ value: amount }("");
            require(success, "CallOptionCVE: !successful");
        } else {
            require(token != cve, "CallOptionCVE: cannot withdraw CVE");
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "CallOptionCVE: insufficient balance"
            );
            SafeTransferLib.safeTransfer(token, recipient, amount);
        }
    }

    /// @notice Withdraws CVE from unexercised CVE call options to DAO after exercising period has ended
    function withdrawRemainingAirdropTokens() external onlyDaoPermissions {
        require(
            block.timestamp > optionsEndTimestamp,
            "CallOptionCVE: Too early"
        );
        uint256 tokensToWithdraw = IERC20(cve).balanceOf(address(this));
        SafeTransferLib.safeTransfer(cve, msg.sender, tokensToWithdraw);
        emit RemainingCVEWithdrawn(tokensToWithdraw);
    }

    /// @notice Set the options expiry timestamp.
    /// @param timestampStart The start timestamp for options exercising.
    /// @param strikePrice The price in USD of CVE in 1e36 format.
    function setOptionsTerms(
        uint256 timestampStart,
        uint256 strikePrice
    ) external onlyDaoPermissions {
        require(
            strikePrice != 0 &&
                paymentToken != address(0) &&
                timestampStart != 0,
            "CallOptionCVE: Cannot Configure Options"
        );

        if (optionsStartTimestamp > 0) {
            require(
                optionsStartTimestamp > block.timestamp,
                "CallOptionCVE: Options exercising already active"
            );
        }

        optionsStartTimestamp = timestampStart;

        /// Give them 4 weeks to exercise their options before they expire
        optionsEndTimestamp = optionsStartTimestamp + (4 weeks);

        /// Get the current price of the payment token from the price router in USD and multiply it by the Strike Price to see how much per CVE they must pay
        (uint256 paymentTokenCurrentPrice, uint256 error) = IPriceRouter(
            centralRegistry.priceRouter()
        ).getPrice(paymentToken, true, true);

        /// Make sure that we didnt have a catastrophic error when pricing the payment token
        require(error < 2, "CallOptionCVE: error pulling paymentToken price");

        /// The strike price should always be greater than the strike price since it will be in 1e36 format offset,
        /// whereas paymentTokenCurrentPrice will be 1e18 so the price should always be larger
        require(
            strikePrice > paymentTokenCurrentPrice,
            "CallOptionCVE: invalid strike price configuration"
        );

        paymentTokenPerCVE =
            (strikePrice / paymentTokenCurrentPrice) /
            denominatorOffset;
    }

    /// PUBLIC FUNCTIONS ///

    /// @dev Returns the name of the token
    function name() public view override returns (string memory) {
        return string(abi.encodePacked(_name));
    }

    /// @dev Returns the symbol of the token
    function symbol() public view override returns (string memory) {
        return string(abi.encodePacked(_symbol));
    }

    /// @notice Check if options are exercisable.
    /// @return True if options are exercisable, false otherwise.
    function optionsExercisable() public view returns (bool) {
        return (optionsStartTimestamp > 0 &&
            block.timestamp >= optionsStartTimestamp &&
            block.timestamp < optionsEndTimestamp);
    }

    /// @notice Exercise CVE call options.
    /// @param amount The amount of options to exercise.
    function exerciseOption(uint256 amount) public payable {
        require(amount > 0, "CallOptionCVE: invalid amount");
        require(
            optionsExercisable(),
            "CallOptionCVE: Options not exercisable yet"
        );
        require(
            IERC20(cve).balanceOf(address(this)) >= amount,
            "CallOptionCVE: not enough CVE remaining"
        );
        require(
            balanceOf(msg.sender) >= amount,
            "CallOptionCVE: not enough call options to exercise"
        );

        uint256 optionExerciseCost = amount * paymentTokenPerCVE;

        /// Take their strike price payment
        if (
            paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            require(
                msg.value >= optionExerciseCost,
                "CallOptionCVE: invalid msg value"
            );
        } else {
            SafeTransferLib.safeTransferFrom(
                paymentToken,
                msg.sender,
                address(this),
                optionExerciseCost
            );
        }

        /// Burn the call options
        _burn(msg.sender, amount);

        /// Transfer them corresponding CVE
        SafeTransferLib.safeTransfer(cve, msg.sender, amount);

        emit CallOptionCVEExercised(msg.sender, amount);
    }
}
