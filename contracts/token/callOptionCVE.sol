// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract callOptionCVE is ERC20 {
    event RemainingCVEWithdrawn(uint256 amount);
    event callOptionCVEExercised(address indexed exerciser, uint256 amount);

    string private _name;
    string private _symbol;

    ICentralRegistry public immutable centralRegistry;
    address public immutable cve;
    address public immutable paymentToken;
    uint256 public paymentTokenPerCVE;

    uint256 optionsStartTimestamp;
    uint256 optionsEndTimestamp;

    // Will need to offset to match differential in decimals between strike price vs oracle pricing
    uint256 public constant denominatorOffset = 1e18;

    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    /// @param _paymentToken The token used for payment when exercising options.
    /// @param _centralRegistry The Central Registry contract address.
    constructor(
        string memory name_,
        string memory symbol_,
        ICentralRegistry _centralRegistry,
        address _paymentToken
    ) {
        _name = name_;
        _symbol = symbol_;

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "callOptionCVE: invalid central registry"
        );

        centralRegistry = _centralRegistry;
        paymentToken = _paymentToken;
        cve = centralRegistry.CVE();

        _mint(msg.sender, 7560001.242 ether);// total call option allocation for airdrops
    }

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "callOptionCVE: UNAUTHORIZED");
        _;
    }

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Check if options are exercisable.
    /// @return True if options are exercisable, false otherwise.
    function optionsExercisable() public view returns (bool) {
        return (optionsStartTimestamp > 0 &&
            block.timestamp >= optionsStartTimestamp &&
            block.timestamp < optionsEndTimestamp);
    }

    /// @notice Exercise CVE call options.
    /// @param _amount The amount of options to exercise.
    function exerciseOption(uint256 _amount) public payable {
        require(optionsExercisable(), "callOptionCVE: Options not exercisable yet");
        require(IERC20(cve).balanceOf(address(this)) >= _amount, "callOptionCVE: not enough CVE remaining");
        require(_amount > 0, "callOptionCVE: invalid amount");
        require(balanceOf(msg.sender) >= _amount, "callOptionCVE: not enough call options to exercise");

        uint256 optionExerciseCost = _amount * paymentTokenPerCVE;

        /// Take their strike price payment
        if (paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            require(msg.value >= optionExerciseCost, "callOptionCVE: invalid msg value");
        } else {
            SafeTransferLib.safeTransferFrom(
                paymentToken,
                msg.sender,
                address(this),
                optionExerciseCost
            );
        }

        /// Burn the call options
        _burn(msg.sender, _amount);
        
        /// Transfer them corresponding CVE 
        SafeTransferLib.safeTransfer(
            cve,
            msg.sender,
            _amount
        );

        emit callOptionCVEExercised(msg.sender, _amount);
    }

    /// @notice Rescue any token sent by mistake, also used for removing .
    /// @param _token The token to rescue.
    /// @param _recipient The address to receive the rescued token.
    /// @param _amount The amount of tokens to rescue.
    function rescueToken(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyDaoPermissions {
        require(
            _recipient != address(0),
            "callOptionCVE: invalid recipient address"
        );
        
        if (_token == address(0)) {
            require(
                address(this).balance >= _amount,
                "callOptionCVE: insufficient balance"
            );
            (bool success, ) = payable(_recipient).call{ value: _amount }("");
            require(success, "callOptionCVE: !successful");
        } else {
            require(_token != cve, "callOptionCVE: cannot withdraw CVE");
            require(
                IERC20(_token).balanceOf(address(this)) >= _amount,
                "callOptionCVE: insufficient balance"
            );
            SafeTransferLib.safeTransfer(_token, _recipient, _amount);
        }
    }

    /// @notice Withdraws CVE from unexercised CVE call options to DAO after exercising period has ended
    function withdrawRemainingAirdropTokens() external onlyDaoPermissions {
        require(
            block.timestamp > optionsEndTimestamp,
            "callOptionCVE: Too early"
        );
        uint256 tokensToWithdraw = IERC20(cve).balanceOf(address(this));
        SafeTransferLib.safeTransfer(
            cve,
            msg.sender,
            tokensToWithdraw
        );
        emit RemainingCVEWithdrawn(tokensToWithdraw);
    }

    /// @notice Set the options expiry timestamp.
    /// @param _timestampStart The start timestamp for options exercising.
    /// @param _strikePrice The price in USD of CVE in 1e36 format.
    function setOptionsTerms(
        uint256 _timestampStart,
        uint256 _strikePrice
    ) external onlyDaoPermissions {
        require(
            _strikePrice != 0 &&
                paymentToken != address(0) &&
                _timestampStart != 0,
            "callOptionCVE: Cannot Configure Options"
        );

        if (optionsStartTimestamp > 0) {
            require(optionsStartTimestamp > block.timestamp, "callOptionCVE: Options exercising already active");
        }

        optionsStartTimestamp = _timestampStart;

        /// Give them 4 weeks to exercise their options before they expire
        optionsEndTimestamp = optionsStartTimestamp + (4 weeks);

        /// Get the current price of the payment token from the price router in USD and multiply it by the Strike Price to see how much per CVE they must pay
        (uint256 paymentTokenCurrentPrice, uint256 error) = IPriceRouter(centralRegistry.priceRouter()).getPrice(paymentToken, true, true);

        /// Make sure that we didnt have a catastrophic error when pricing the payment token 
        require(error < 2, "callOptionCVE: error pulling paymentToken price");

        /// The strike price should always be greater than the strike price since it will be in 1e36 format offset,
        /// whereas paymentTokenCurrentPrice will be 1e18 so the price should always be larger 
        require(_strikePrice > paymentTokenCurrentPrice, "callOptionCVE: invalid strike price configuration");

        paymentTokenPerCVE = (_strikePrice / paymentTokenCurrentPrice) / denominatorOffset;

    }
}
