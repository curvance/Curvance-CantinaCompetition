// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { IERC20 } from "./IERC20.sol";

interface IGelatoOneBalance {
    function depositToken(
        address sponsor,
        IERC20 token,
        uint256 amount
    ) external;
}
