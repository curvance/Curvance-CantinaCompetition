// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface DaiJoinLike {
    function vat() external returns (VatLike);

    function dai() external returns (GemLike);

    function join(address, uint256) external payable;

    function exit(address, uint256) external;
}
