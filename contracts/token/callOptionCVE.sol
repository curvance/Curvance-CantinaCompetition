// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC20.sol";
import "../interfaces/ICentralRegistry.sol";

error InvalidExercise();

contract callOptionCVE is ERC20 {
    event RemainingCVEWithdrawn(uint256 amount);
    event callOptionCVEExercised(address indexed exerciser, uint256 amount);

    ICentralRegistry public immutable centralRegistry;
    IERC20 public immutable paymentToken;
    uint256 public immutable paymentTokenPricePerCVE;

    uint256 optionsStartTimestamp;
    uint256 optionsEndTimestamp;

    // USDC is 6 decimals and CVE is 18 decimals so we need to offset by 10e12 + report number in basis points
    uint256 public constant denominatorOffset = 10000000000000000;

    /**
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _paymentToken The token used for payment when exercising options.
     * @param _paymentTokenPricePerCVE The price of the payment token per CVE.
     * @param _centralRegistry The Central Registry contract address.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _paymentToken,
        uint256 _paymentTokenPricePerCVE,
        ICentralRegistry _centralRegistry
    ) ERC20(_name, _symbol) {
        paymentToken = _paymentToken;
        paymentTokenPricePerCVE = _paymentTokenPricePerCVE;
        centralRegistry = _centralRegistry;
        _mint(msg.sender, 7560001.242 ether);
    }

    modifier onlyDaoManager() {
        require(msg.sender == centralRegistry.daoAddress(), "UNAUTHORIZED");
        _;
    }

    /**
     * @notice Check if options are exercisable.
     * @return True if options are exercisable, false otherwise.
     */
    function optionsExercisable() public view returns (bool) {
        return (optionsStartTimestamp > 0 &&
            block.timestamp >= optionsStartTimestamp &&
            block.timestamp < optionsEndTimestamp);
    }

    /**
     * @notice Exercise CVE call options.
     * @param _amount The amount of options to exercise.
     */
    function exerciseOption(uint256 _amount) public {
        require(optionsExercisable(), "Options not exercisable yet");
        if (IERC20(centralRegistry.CVE()).balanceOf(address(this)) <= _amount)
            revert InvalidExercise();
        if (_amount == 0) revert InvalidExercise();

        SafeERC20.safeTransferFrom(
            paymentToken,
            msg.sender,
            address(this),
            (_amount * paymentTokenPricePerCVE) / denominatorOffset
        );
        SafeERC20.safeTransfer(
            IERC20(centralRegistry.CVE()),
            msg.sender,
            _amount
        );
        emit callOptionCVEExercised(msg.sender, _amount);
    }

    /**
     * @notice Rescue any token sent by mistake.
     * @param _token The token to rescue.
     * @param _recipient The address to receive the rescued token.
     * @param _amount The amount of tokens to rescue.
     */
    function rescueToken(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyDaoManager {
        require(
            _recipient != address(0),
            "rescueToken: Invalid recipient address"
        );
        if (_token == address(0)) {
            require(
                address(this).balance >= _amount,
                "rescueToken: Insufficient balance"
            );
            (bool success, ) = payable(_recipient).call{ value: _amount }("");
            require(success, "rescueToken: !successful");
        } else {
            require(
                IERC20(_token).balanceOf(address(this)) >= _amount,
                "rescueToken: Insufficient balance"
            );
            SafeERC20.safeTransfer(IERC20(_token), _recipient, _amount);
        }
    }

    /**
     * @notice Withdraws CVE from unexercised CVE call options to contract Owner after exercising period has ended
     */
    function withdrawRemainingAirdropTokens() external onlyDaoManager {
        require(
            block.timestamp > optionsEndTimestamp,
            "withdrawRemainingAirdropTokens: Too early"
        );
        uint256 tokensToWithdraw = IERC20(centralRegistry.callOptionCVE())
            .balanceOf(address(this));
        SafeERC20.safeTransfer(
            IERC20(centralRegistry.CVE()),
            _msgSender(),
            tokensToWithdraw
        );
        emit RemainingCVEWithdrawn(tokensToWithdraw);
    }

    /**
     * @notice Set the options expiry timestamp.
     * @param _timestampStart The start timestamp for options exercising.
     */
    function setOptionsExpiry(uint256 _timestampStart)
        external
        onlyDaoManager
    {
        require(
            paymentTokenPricePerCVE != 0 &&
                paymentToken != IERC20(address(0)) &&
                optionsStartTimestamp != 0,
            "Cannot Configure Options"
        );
        optionsStartTimestamp = _timestampStart;
        optionsEndTimestamp = optionsStartTimestamp + (4 weeks);
    }
}
