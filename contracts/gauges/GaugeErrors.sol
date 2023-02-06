//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface GaugeErrors {
    error AlreadyStarted();
    error InvalidEpoch();
    error InvalidLength();
    error InvalidToken();
    error InvalidAmount();
    error NoRewards();
}
