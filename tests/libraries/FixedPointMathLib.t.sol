// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SoladyTest.sol";
import {FixedPointMathLib} from "../../contracts/libraries/FixedPointMathLib.sol";

contract FixedPointMathLibTest is SoladyTest {
    function testFullMulDiv() public {
        assertEq(FixedPointMathLib.fullMulDiv(0, 0, 1), 0);
        assertEq(FixedPointMathLib.fullMulDiv(4, 4, 2), 8);
        assertEq(FixedPointMathLib.fullMulDiv(2 ** 200, 2 ** 200, 2 ** 200), 2 ** 200);
    }

    function testFullMulDivUpRevertsIfRoundedUpResultOverflowsCase1() public {
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        FixedPointMathLib.fullMulDivUp(
            535006138814359, 432862656469423142931042426214547535783388063929571229938474969, 2
        );
    }

    function testFullMulDivUpRevertsIfRoundedUpResultOverflowsCase2() public {
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        FixedPointMathLib.fullMulDivUp(
            115792089237316195423570985008687907853269984659341747863450311749907997002549,
            115792089237316195423570985008687907853269984659341747863450311749907997002550,
            115792089237316195423570985008687907853269984653042931687443039491902864365164
        );
    }

    function testFullMulDiv(uint256 a, uint256 b, uint256 d) public returns (uint256 result) {
        if (d == 0) {
            vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
            FixedPointMathLib.fullMulDiv(a, b, d);
            return 0;
        }

        // Compute a * b in Chinese Remainder Basis
        uint256 expectedA;
        uint256 expectedB;
        unchecked {
            expectedA = a * b;
            expectedB = mulmod(a, b, 2 ** 256 - 1);
        }

        // Construct a * b
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        /// @solidity memory-safe-assembly
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        if (prod1 >= d) {
            vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
            FixedPointMathLib.fullMulDiv(a, b, d);
            return 0;
        }

        uint256 q = FixedPointMathLib.fullMulDiv(a, b, d);
        uint256 r = mulmod(a, b, d);

        // Compute q * d + r in Chinese Remainder Basis
        uint256 actualA;
        uint256 actualB;
        unchecked {
            actualA = q * d + r;
            actualB = addmod(mulmod(q, d, 2 ** 256 - 1), r, 2 ** 256 - 1);
        }

        assertEq(actualA, expectedA);
        assertEq(actualB, expectedB);
        return q;
    }

    function testFullMulDivUp(uint256 a, uint256 b, uint256 d) public {
        uint256 fullMulDivResult = testFullMulDiv(a, b, d);
        if (fullMulDivResult != 0) {
            uint256 expectedResult = fullMulDivResult;
            if (mulmod(a, b, d) > 0) {
                if (!(fullMulDivResult < type(uint256).max)) {
                    vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
                    FixedPointMathLib.fullMulDivUp(a, b, d);
                    return;
                }
                expectedResult++;
            }
            assertEq(FixedPointMathLib.fullMulDivUp(a, b, d), expectedResult);
        }
    }

    function testMulDiv(uint256 x, uint256 y, uint256 denominator) public {
        // Ignore cases where x * y overflows or denominator is 0.
        unchecked {
            if (denominator == 0 || (x != 0 && (x * y) / x != y)) return;
        }

        assertEq(FixedPointMathLib.mulDiv(x, y, denominator), (x * y) / denominator);
    }

    function testMulDivOverflowReverts(uint256 x, uint256 y, uint256 denominator) public {
        unchecked {
            vm.assume(denominator != 0 && x != 0 && (x * y) / x != y);
        }
        vm.expectRevert(FixedPointMathLib.MulDivFailed.selector);
        FixedPointMathLib.mulDiv(x, y, denominator);
    }

    function testMulDivZeroDenominatorReverts(uint256 x, uint256 y) public {
        vm.expectRevert(FixedPointMathLib.MulDivFailed.selector);
        FixedPointMathLib.mulDiv(x, y, 0);
    }

    function testMulDivUp(uint256 x, uint256 y, uint256 denominator) public {
        // Ignore cases where x * y overflows or denominator is 0.
        unchecked {
            if (denominator == 0 || (x != 0 && (x * y) / x != y)) return;
        }

        assertEq(
            FixedPointMathLib.mulDivUp(x, y, denominator),
            x * y == 0 ? 0 : (x * y - 1) / denominator + 1
        );
    }

    function testMulDivUpOverflowReverts(uint256 x, uint256 y, uint256 denominator) public {
        unchecked {
            vm.assume(denominator != 0 && x != 0 && (x * y) / x != y);
        }
        vm.expectRevert(FixedPointMathLib.MulDivFailed.selector);
        FixedPointMathLib.mulDivUp(x, y, denominator);
    }

    function testMulDivUpZeroDenominatorReverts(uint256 x, uint256 y) public {
        vm.expectRevert(FixedPointMathLib.MulDivFailed.selector);
        FixedPointMathLib.mulDivUp(x, y, 0);
    }

    function testSqrt(uint256 x) public {
        uint256 root = FixedPointMathLib.sqrt(x);
        uint256 next = root + 1;

        // Ignore cases where `next * next` overflows.
        unchecked {
            if (next * next < next) return;
        }

        assertTrue(root * root <= x && next * next > x);
    }

    function testSqrtBack(uint256 x) public {
        unchecked {
            x >>= 128;
            while (x != 0) {
                assertEq(FixedPointMathLib.sqrt(x * x), x);
                x >>= 1;
            }
        }
    }
}
