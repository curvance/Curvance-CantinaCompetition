// SPDX-License-Identifier: GPL-3.0-or-later

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.4.23;

import "tests/lib/DSTest.sol";
import "tests/lib/Hevm.sol";

contract DSTestPlus is DSTest {
  Hevm hevm = Hevm(HEVM_ADDRESS);

  uint256 constant ALMOST_EQ_PERCENT = 5;

  function assertAlmostEq(uint256 a, uint256 b) internal {
    uint256 delta = (a * ALMOST_EQ_PERCENT) / 100;
    if (a < b - delta || a > b + delta) {
      emit log("Error: a == b not satisfied [uint]");
      emit log_named_uint("  Expected", b);
      emit log_named_uint("    Actual", a);
      fail();
    }
  }

  function assertAlmostEq(
    uint256 a,
    uint256 b,
    string memory err
  ) internal {
    uint256 delta = (a * ALMOST_EQ_PERCENT) / 100;
    if (a < b - delta || a > b + delta) {
      emit log_named_string("Error", err);
      assertEq(a, b);
    }
  }
}
