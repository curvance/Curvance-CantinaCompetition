// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface GaugeErrors {
    error InvalidAddress();
    error Unauthorized();
    error NotStarted();
    error AlreadyStarted();
    error InvalidEpoch();
    error InvalidLength();
    error InvalidToken();
    error InvalidAmount();
    error NoReward();
}
