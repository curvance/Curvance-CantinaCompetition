// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

// Dynamically tests multiple functions in CentralRegistry that remove a contract from a mapping
contract BasicRemoveContractsTest is TestBaseMarket {
    event RemovedCurvanceContract(
        string indexed contractType,
        address removedAddress
    );

    string[] removeFuncs;
    string[] maps;
    string[] expectedLogs;
    string[] addFuncs;

    function setUp() public virtual override {
        super.setUp();

        removeFuncs = [
            "removeZapper(address)",
            "removeSwapper(address)",
            "removeVeCVELocker(address)",
            "removeGaugeController(address)",
            "removeHarvester(address)",
            "removeEndpoint(address)"
        ];
        maps = [
            "isZapper(address)",
            "isSwapper(address)",
            "isVeCVELocker(address)",
            "isGaugeController(address)",
            "isHarvester(address)",
            "isEndpoint(address)"
        ];
        expectedLogs = [
            "Zapper",
            "Swapper",
            "VeCVELocker",
            "Gauge Controller",
            "Harvestor",
            "Endpoint"
        ];
        addFuncs = [
            "addZapper(address)",
            "addSwapper(address)",
            "addVeCVELocker(address)",
            "addGaugeController(address)",
            "addHarvester(address)",
            "addEndpoint(address)"
        ];
    }

    function test_removeFunc_fail_whenUnauthorized() public {
        uint8 length = uint8(removeFuncs.length);
        for (uint256 i; i < length; i++) {
            vm.startPrank(address(0));
            bytes memory sig = abi.encodeWithSignature(removeFuncs[i], user1);
            (bool success, bytes memory data) = address(centralRegistry).call(
                sig
            );

            assertFalse(success);
            assertEq(
                bytes32(data),
                bytes32(CentralRegistry.CentralRegistry__Unauthorized.selector)
            );
            vm.stopPrank();
        }
    }

    function test_removeFunc_fail_whenParametersMisconfigured() public {
        uint8 length = uint8(removeFuncs.length);
        for (uint256 i; i < length; i++) {
            bytes memory sig = abi.encodeWithSignature(removeFuncs[i], user1);
            (bool success, bytes memory data) = address(centralRegistry).call(
                sig
            );

            assertFalse(success);
            assertEq(
                bytes32(data),
                bytes32(
                    CentralRegistry
                        .CentralRegistry__ParametersMisconfigured
                        .selector
                )
            );
        }
    }

    function test_removeFunc_success() public {
        uint8 length = uint8(removeFuncs.length);
        for (uint256 i; i < length; i++) {
            bytes memory sig = abi.encodeWithSignature(addFuncs[i], user1);
            (bool success, bytes memory data) = address(centralRegistry).call(
                sig
            );
            assertTrue(success);

            vm.expectEmit(true, true, true, true);
            emit RemovedCurvanceContract(expectedLogs[i], user1);
            sig = abi.encodeWithSignature(removeFuncs[i], user1);
            (success, ) = address(centralRegistry).call(sig);
            assertTrue(success);

            (, data) = address(centralRegistry).call(
                abi.encodeWithSignature(maps[i], user1)
            );
            assertFalse(abi.decode(data, (bool)));
        }
    }
}
