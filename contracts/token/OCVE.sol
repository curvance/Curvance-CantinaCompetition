// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract OCVE is ERC20 {
    /// CONSTANTS ///

    /// @notice Scalar for math
    uint256 public constant expScale = 1e18;

    /// @notice CVE contract address
    address public immutable cve;

    /// @notice Token exercisers pay in
    address public immutable paymentToken;

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

    error OCVE__ConstructorParametersareInvalid();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "OCVE: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR ///

    /// @param paymentToken_ The token used for payment when exercising options.
    /// @param centralRegistry_ The Central Registry contract address.
    constructor(ICentralRegistry centralRegistry_, address paymentToken_) {
        _name = "CVE Options";
        _symbol = "oCVE";

        if (!ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )) {
                revert OCVE__ConstructorParametersareInvalid();
            }

        if (paymentToken_ == address(0)) {
            revert OCVE__ConstructorParametersareInvalid();
        }

        centralRegistry = centralRegistry_;
        paymentToken = paymentToken_;
        cve = centralRegistry.CVE();

        // total call option allocation for airdrops
        _mint(msg.sender, 7560001.242 ether);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Rescue any token sent by mistake, also used for removing.
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
            "OCVE: invalid recipient address"
        );

        if (token == address(0)) {
            require(
                address(this).balance >= amount,
                "OCVE: insufficient balance"
            );
            (bool success, ) = payable(recipient).call{ value: amount }("");
            require(success, "OCVE: !successful");
        } else {
            require(token != cve, "OCVE: cannot withdraw CVE");
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "OCVE: insufficient balance"
            );
            SafeTransferLib.safeTransfer(token, recipient, amount);
        }
    }

    /// @notice Withdraws CVE from unexercised CVE call options to DAO
    ///         after exercising period has ended
    function withdrawRemainingAirdropTokens() external onlyDaoPermissions {
        require(
            block.timestamp > optionsEndTimestamp,
            "OCVE: Too early"
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
            timestampStart >= block.timestamp,
            "OCVE: Start timestamp is invalid"
        );
        require(strikePrice != 0, "OCVE: Strike price is invalid");

        if (optionsStartTimestamp > 0) {
            require(
                optionsStartTimestamp > block.timestamp,
                "OCVE: Options exercising already active"
            );
        }

        optionsStartTimestamp = timestampStart;

        // Give them 4 weeks to exercise their options before they expire
        optionsEndTimestamp = optionsStartTimestamp + (4 weeks);

        // Get the current price of the payment token from the price router
        // in USD and multiply it by the Strike Price to see how much per CVE
        // they must pay
        (uint256 paymentTokenCurrentPrice, uint256 error) = IPriceRouter(
            centralRegistry.priceRouter()
        ).getPrice(paymentToken, true, true);

        // Make sure that we didnt have a catastrophic error when pricing
        // the payment token
        require(error < 2, "OCVE: error pulling paymentToken price");

        // The strike price should always be greater than the token price
        // since it will be in 1e36 format offset,
        // whereas paymentTokenCurrentPrice will be 1e18 so the price should
        // always be larger
        require(
            strikePrice > paymentTokenCurrentPrice,
            "OCVE: invalid strike price configuration"
        );

        paymentTokenPerCVE = strikePrice / paymentTokenCurrentPrice;
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
        require(amount > 0, "OCVE: invalid amount");
        require(
            optionsExercisable(),
            "OCVE: Options not exercisable yet"
        );
        require(
            IERC20(cve).balanceOf(address(this)) >= amount,
            "OCVE: not enough CVE remaining"
        );
        require(
            balanceOf(msg.sender) >= amount,
            "OCVE: not enough call options to exercise"
        );

        uint256 optionExerciseCost = amount * paymentTokenPerCVE;

        // Take their strike price payment
        if (paymentToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            require(
                msg.value >= optionExerciseCost,
                "OCVE: invalid msg value"
            );
        } else {
            SafeTransferLib.safeTransferFrom(
                paymentToken,
                msg.sender,
                address(this),
                optionExerciseCost
            );
        }

        // Burn the call options
        _burn(msg.sender, amount);

        // Transfer them corresponding CVE
        SafeTransferLib.safeTransfer(cve, msg.sender, amount);

        emit OptionsExercised(msg.sender, amount);
    }
}
