// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBridgeAdapter {
    function bridge(address user, bytes memory bridgeData) external;
}
