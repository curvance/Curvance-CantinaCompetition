// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { FixedPointMathLib } from "contracts/libraries/external/FixedPointMathLib.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract OCVE is ERC20 {
    /// CONSTANTS ///

    /// @notice CVE contract address
    address public immutable cve;

    /// @notice Token exercisers pay in
    address public immutable paymentToken;

    uint8 public paymentTokenDecimals;

    /// @notice token name metadata
    bytes32 private immutable _name;

    /// @notice token symbol metadata
    bytes32 private immutable _symbol;

    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Ratio between payment token and CVE
    uint256 public paymentTokenPerCVE;

    /// @notice When options holders can begin exercising
    uint256 public optionsStartTimestamp;

    /// @notice When options holders have until to exercise
    uint256 public optionsEndTimestamp;

    /// EVENTS ///

    event RemainingCVEWithdrawn(uint256 amount);
    event OptionsExercised(address indexed exerciser, uint256 amount);

    /// ERRORS ///

    error OCVE__ParametersAreInvalid();
    error OCVE__ConfigurationError();
    error OCVE__CannotExercise();
    error OCVE__TransferError();
    error OCVE__Unauthorized();

    /// CONSTRUCTOR ///

    /// @param paymentToken_ The token used for payment when exercising options.
    /// @param centralRegistry_ The Central Registry contract address.
    constructor(ICentralRegistry centralRegistry_, address paymentToken_) {
        _name = "CVE Options";
        _symbol = "oCVE";

        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert OCVE__ParametersAreInvalid();
        }

        if (paymentToken_ == address(0)) {
            revert OCVE__ParametersAreInvalid();
        }

        centralRegistry = centralRegistry_;
        paymentToken = paymentToken_;
        if (paymentToken_ == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            paymentTokenDecimals = 18;
        } else {
            paymentTokenDecimals = ERC20(paymentToken_).decimals();
        }
        cve = centralRegistry.cve();

        // total call option allocation for airdrops
        _mint(msg.sender, 15750002.59 ether);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Rescue any token sent by mistake
    /// @param token token to rescue
    /// @param amount amount of `token` to rescue, 0 indicates to rescue all
    function rescueToken(address token, uint256 amount) external {
        _checkDaoPermissions();
        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (amount == 0) {
                amount = address(this).balance;
            }

            SafeTransferLib.forceSafeTransferETH(daoOperator, amount);
        } else {
            if (token == cve) {
                revert OCVE__TransferError();
            }

            if (amount == 0) {
                amount = IERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// @notice Withdraws CVE from unexercised CVE call options to DAO
    ///         after exercising period has ended
    function withdrawRemainingAirdropTokens() external {
        _checkDaoPermissions();

        if (block.timestamp < optionsEndTimestamp) {
            revert OCVE__TransferError();
        }

        uint256 tokensToWithdraw = IERC20(cve).balanceOf(address(this));
        SafeTransferLib.safeTransfer(
            cve,
            centralRegistry.daoAddress(),
            tokensToWithdraw
        );

        emit RemainingCVEWithdrawn(tokensToWithdraw);
    }

    /// @notice Set the options expiry timestamp.
    /// @param timestampStart The start timestamp for options exercising.
    /// @param strikePrice The price in USD of CVE in 1e36 format.
    function setOptionsTerms(
        uint256 timestampStart,
        uint256 strikePrice
    ) external {
        _checkDaoPermissions();

        if (timestampStart < block.timestamp) {
            revert OCVE__ParametersAreInvalid();
        }

        if (strikePrice == 0) {
            revert OCVE__ParametersAreInvalid();
        }

        // If the option are exercisable do not allow reconfiguration of the terms
        if (
            optionsStartTimestamp > 0 &&
            optionsStartTimestamp < block.timestamp
        ) {
            revert OCVE__ConfigurationError();
        }

        optionsStartTimestamp = timestampStart;

        // Give them 4 weeks to exercise their options before they expire
        optionsEndTimestamp = optionsStartTimestamp + (4 weeks);

        // Get the current price of the payment token from the price router
        // in USD and multiply it by the Strike Price to see how much per CVE
        // they must pay
        (uint256 currentPrice, uint256 error) = IOracleRouter(
            centralRegistry.oracleRouter()
        ).getPrice(paymentToken, true, true);

        // Make sure that we didnt have a catastrophic error when pricing
        // the payment token
        if (error == 2) {
            revert OCVE__ConfigurationError();
        }

        // The strike price should always be greater than the token price
        // since it will be in 1e36 format offset,
        // whereas currentPrice will be 1e18 so the price should
        // always be larger
        if (strikePrice <= currentPrice) {
            revert OCVE__ParametersAreInvalid();
        }

        paymentTokenPerCVE = strikePrice / currentPrice;
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
        if (amount == 0) {
            revert OCVE__ParametersAreInvalid();
        }

        if (!optionsExercisable()) {
            revert OCVE__CannotExercise();
        }

        if (IERC20(cve).balanceOf(address(this)) < amount) {
            revert OCVE__CannotExercise();
        }

        if (balanceOf(msg.sender) < amount) {
            revert OCVE__CannotExercise();
        }

        uint256 optionExerciseCost = (amount * paymentTokenPerCVE) / WAD;

        // Take their strike price payment
        if (paymentToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            if (msg.value < optionExerciseCost) {
                revert OCVE__CannotExercise();
            }
        } else {
            // Adjust decimals between paymentTokenDecimals,
            // and default 18 decimals of optionExerciseCost. 
            uint256 amount = _adjustDecimals(
                optionExerciseCost, 
                paymentTokenDecimals, 
                18
            );

            /// Equivalent to `(optionExerciseCost * amount) / WAD` rounded up.
            amount = FixedPointMathLib.mulWadUp(optionExerciseCost, amount)

            if (amount == 0) {
                revert OCVE__CannotExercise();
            }

            SafeTransferLib.safeTransferFrom(
                paymentToken,
                msg.sender,
                address(this),
                amount
            );
        }

        // Burn the call options
        _burn(msg.sender, amount);

        // Transfer them corresponding CVE
        SafeTransferLib.safeTransfer(cve, msg.sender, amount);

        emit OptionsExercised(msg.sender, amount);
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert OCVE__Unauthorized();
        }
    }

    function _adjustDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * 10 **(toDecimals - fromDecimals);
        } else {
            return amount / 10 **(fromDecimals - toDecimals);
        }
    }
}
