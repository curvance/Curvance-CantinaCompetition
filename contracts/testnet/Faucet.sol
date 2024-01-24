// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract Faucet is Ownable {

    /// user => token => last claimed timestamp
    mapping(address => mapping(address => uint256)) public userLastClaimed;

    constructor() Ownable() {}

    function claim(
        address user,
        address token,
        uint256 amount
    ) external {
        require(
            userLastClaimed[user][token] + 24 hours <= block.timestamp,
            "Wait 24 hours"
        );
        if (token == address(0)) {
            require(address(this).balance >= amount, "Not enough ETH");
            SafeTransferLib.safeTransferETH(user, amount);
        } else {
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "Not enough Token"
            );
            SafeTransferLib.safeTransfer(token, user, amount);
        }

        userLastClaimed[user][token] = block.timestamp;
    }
}
