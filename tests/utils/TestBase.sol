// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

contract TestBase is Test {
    uint256 internal constant _ONE = 1e18;
    address internal constant _ZERO_ADDRESS = address(0);

    function _fork() internal {
        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"));
    }

    function _fork(string memory rpc) internal {
        vm.createSelectFork(vm.envString(rpc));
    }

    function _fork(uint256 blocknumber) internal {
        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), blocknumber);
    }

    function _fork(string memory rpc, uint256 blocknumber) internal {
        vm.createSelectFork(vm.envString(rpc), blocknumber);
    }
}
