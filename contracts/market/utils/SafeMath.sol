// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// From https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/Math.sol
// Subject to the MIT license.

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    error NumberTooLarge();
    error AdditionOverflow();
    error SubtractionUnderflow();
    error ModuloByZero();

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert ModuloByZero();
        }
        return a % b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a <= b) {
            return a;
        } else {
            return b;
        }
    }

    function safe32(uint256 n) internal pure returns (uint32) {
        if (n >= 2**32) {
            revert NumberTooLarge();
        }
        return uint32(n);
    }

    function safe96(uint256 n) internal pure returns (uint96) {
        if (n >= 2**96) {
            revert NumberTooLarge();
        }
        return uint96(n);
    }

    function safe224(uint256 n) internal pure returns (uint224) {
        if (n >= 2**224) {
            revert NumberTooLarge();
        }
        return uint224(n);
    }

    function add96(uint96 a, uint96 b) internal pure returns (uint96) {
        uint96 c = a + b;
        if (c < a) {
            revert AdditionOverflow();
        }
        return c;
    }

    function sub96(uint96 a, uint96 b) internal pure returns (uint96) {
        if (b > a) {
            revert SubtractionUnderflow();
        }
        return a - b;
    }
}
