// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IExternalCallDataChecker {
    function checkRecipient(
        address target,
        bytes memory data,
        address recipient
    ) external;
}
