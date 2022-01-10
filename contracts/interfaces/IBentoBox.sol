// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IBentoBox {
    function toAmount(
        address _token,
        uint256 _share,
        bool _roundUp
    ) external view returns (uint256);
}
