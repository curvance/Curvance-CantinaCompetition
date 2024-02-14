// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOneBalanceFeeManager } from "../TestBaseOneBalanceFeeManager.sol";
import { OneBalanceFeeManager } from "contracts/architecture/OneBalanceFeeManager.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract OneBalanceFeeManagerReceiveWormholeMessagesTest is
    TestBaseOneBalanceFeeManager
{
    function setUp() public override {
        _fork("ETH_NODE_URI_POLYGON");

        _USDC_ADDRESS = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

        usdc = IERC20(_USDC_ADDRESS);

        _deployBaseContracts();
    }

    function test_oneBalanceFeeManagerReceiveWormholeMessages_fail_whenCallerIsNotWormholeRelayer()
        public
    {
        vm.expectRevert(
            OneBalanceFeeManager.OneBalanceFeeManager__Unauthorized.selector
        );
        oneBalanceFeeManager.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS)))),
            new bytes[](0),
            "",
            23,
            ""
        );
    }

    function test_oneBalanceFeeManagerReceiveWormholeMessages_fail_whenNotReceivedToken()
        public
    {
        vm.expectRevert();

        vm.prank(_WORMHOLE_RELAYER);
        oneBalanceFeeManager.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS)))),
            new bytes[](0),
            "",
            23,
            ""
        );
    }

    function test_oneBalanceFeeManagerReceiveWormholeMessages_success_notOnPolygon()
        public
    {
        _fork();

        _USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        usdc = IERC20(_USDC_ADDRESS);

        _deployBaseContracts();

        deal(_USDC_ADDRESS, address(oneBalanceFeeManager), 100e6);

        uint256 balance = usdc.balanceOf(_GELATO_ONE_BALANCE);

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);

        vm.prank(_WORMHOLE_RELAYER);
        oneBalanceFeeManager.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS)))),
            new bytes[](0),
            "",
            23,
            ""
        );

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);
        assertEq(usdc.balanceOf(_GELATO_ONE_BALANCE), balance);
    }

    function test_oneBalanceFeeManagerReceiveWormholeMessages_success_whenPayloadIdIsNotOne()
        public
    {
        deal(_USDC_ADDRESS, address(oneBalanceFeeManager), 100e6);

        uint256 balance = usdc.balanceOf(_GELATO_ONE_BALANCE);

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);

        vm.prank(_WORMHOLE_RELAYER);
        oneBalanceFeeManager.receiveWormholeMessages(
            abi.encode(2, bytes32(uint256(uint160(_USDC_ADDRESS)))),
            new bytes[](0),
            "",
            23,
            ""
        );

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);
        assertEq(usdc.balanceOf(_GELATO_ONE_BALANCE), balance);
    }

    function test_oneBalanceFeeManagerReceiveWormholeMessages_success_whenPayloadIdIsOne()
        public
    {
        deal(_USDC_ADDRESS, address(oneBalanceFeeManager), 100e6);

        uint256 balance = usdc.balanceOf(_GELATO_ONE_BALANCE);

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);

        vm.prank(_WORMHOLE_RELAYER);
        oneBalanceFeeManager.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS)))),
            new bytes[](0),
            "",
            23,
            ""
        );

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 0);
        assertEq(usdc.balanceOf(_GELATO_ONE_BALANCE), balance + 100e6);
    }
}
