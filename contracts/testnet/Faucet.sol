// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract Faucet is Ownable {

    /// Maximum faucet erc20 claim amount
    uint256 public maxClaim = 10 ether;
    /// /// Maximum faucet sepETH claim amount
    uint256 public maxSepETHClaim = 0.1 ether;
    /// user => token => last claimed timestamp
    mapping(address => mapping(address => uint256)) public userLastClaimed;

    constructor() Ownable() {}

    function setMaxClaimAmounts(
        uint256 amountERC20, 
        uint256 amountSepETH
    ) external onlyOwner {
        maxClaim = amountERC20;
        maxSepETHClaim = amountSepETH;
    }

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
            require(amount < maxSepETHClaim, "Excessive desired claim amount");
            require(address(this).balance >= amount, "Not enough ETH");
            SafeTransferLib.safeTransferETH(user, amount);
        } else {
            require(amount < maxClaim, "Excessive desired claim amount");
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "Not enough Token"
            );
            SafeTransferLib.safeTransfer(token, user, amount);
        }

        userLastClaimed[user][token] = block.timestamp;
    }
}
