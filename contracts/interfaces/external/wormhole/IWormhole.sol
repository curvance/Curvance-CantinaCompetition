// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWormhole {
    function messageFee() external view returns (uint256);

    function chainId() external view returns (uint16);
}
