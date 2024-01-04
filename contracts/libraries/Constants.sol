// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Scalar for math.
uint256 constant WAD = 1e18;

/// @dev Scalar for math.
uint256 constant DENOMINATOR = 1e4;

/// @dev Return value indicating no price error.
uint256 constant NO_ERROR = 0;

/// @dev Return value indicating price divergence or 1 missing price.
uint256 constant CAUTION = 1;

/// @dev Return value indicating no price returned at all.
uint256 constant BAD_SOURCE = 2;
