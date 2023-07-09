// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ERC4626, SafeTransferLib, ERC20 } from "contracts/libraries/ERC4626.sol";
import { Math } from "contracts/libraries/Math.sol";

/// @title Curvance Deposit Router
/// @notice Provides a universal interface allowing Curvance contracts
///         to deposit and withdraw assets from Convex
/// @author crispymangoes
// TODO add events
contract DepositRouterV2 is Ownable {
    using Math for uint256;

    // TODO should probs make a lib that helps with managing this array.
    ERC4626[] public positions;

    function getPositions() external view returns (ERC4626[] memory) {
        return positions;
    }

    mapping(ERC4626 => bool) public isPositionUsed;

    mapping(ERC4626 => address) public positionOperator;

    modifier isOperator(ERC4626 _position) {
        if (positionOperator[_position] != msg.sender)
            revert("Not the operator");
        _;
    }

    constructor() {}

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows `owner` to add new positions to this contract.
    /// @dev see `Position` struct for description of inputs.
    function addPosition(
        ERC4626 _position,
        address _operator
    ) external onlyOwner {
        if (isPositionUsed[_position]) revert("Position already used");
        positionOperator[_position] = _operator;
        positions.push(_position);
    }

    /*//////////////////////////////////////////////////////////////
                              USER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// Takes underlying token and deposits it into the underlying protocol
    /// returns the amount of shares
    function deposit(
        uint256 amount,
        ERC4626 _position
    ) public isOperator(_position) returns (uint256) {
        if (!isPositionUsed[_position]) revert("Position not used");
        // transfer asset in.
        SafeTransferLib.safeTransferFrom(
            _position.asset(),
            msg.sender,
            address(this),
            amount
        );

        // deposit it into ERC4626 vault.
        _position.deposit(amount, msg.sender);

        return amount;
    }

    function withdraw(
        uint256 amount,
        ERC4626 _position
    ) public isOperator(_position) returns (uint256) {
        // TODO transfer shares in?

        // TODO could send the assets here or direclty to caller.
        _position.withdraw(amount, msg.sender, msg.sender);

        return amount;
    }

    /*//////////////////////////////////////////////////////////////
                              BALANCE OF LOGIC
    //////////////////////////////////////////////////////////////*/

    // CToken `getCashPrior` should call this.
    // Returns the balance in terms of `_position`s underlying.
    function balanceOf(ERC4626 _position) public view returns (uint256) {
        return _position.maxWithdraw(address(this));
    }
}
