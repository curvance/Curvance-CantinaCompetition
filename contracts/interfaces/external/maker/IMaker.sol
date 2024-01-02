// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface DaiJoinLike {
    function vat() external returns (VatLike);

    function dai() external returns (GemLike);

    function join(address, uint256) external payable;

    function exit(address, uint256) external;
}

interface GemLike {
    function approve(address, uint256) external;

    function balanceOf(address) external view returns (uint256);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}

interface VatLike {
    function dai(address) external view returns (uint256);

    function hope(address) external;
}
