// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

// Dynamically tests multiple functions in CentralRegistry that add a contract to a mapping
contract BasicAddContractsTest is TestBaseMarket {
    event NewCurvanceContract(string indexed contractType, address newAddress);

    string[] addFuncs;
    string[] maps;
    string[] expectedLogs;

    function setUp() public virtual override {
        super.setUp();

        addFuncs = [
            "addZapper(address)",
            "addSwapper(address)",
            "addVeCVELocker(address)",
            "addGaugeController(address)",
            "addHarvester(address)",
            "addEndpoint(address)"
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
    }

    function test_addFunc_fail_whenUnauthorized() public {
        uint8 length = uint8(addFuncs.length);
        for (uint256 i; i < length; i++) {
            vm.startPrank(address(0));
            bytes memory sig = abi.encodeWithSignature(addFuncs[i], user1);
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

    function test_addFunc_fail_whenParametersMisconfigured() public {
        uint8 length = uint8(addFuncs.length);
        for (uint256 i; i < length; i++) {
            bytes memory sig = abi.encodeWithSignature(addFuncs[i], user1);
            (bool success, bytes memory data) = address(centralRegistry).call(
                sig
            );

            assertTrue(success);

            (success, data) = address(centralRegistry).call(sig);
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

    function test_addFunc_success() public {
        uint8 length = uint8(addFuncs.length);
        for (uint256 i; i < length; i++) {
            vm.expectEmit(true, true, true, true);
            emit NewCurvanceContract(expectedLogs[i], user1);
            bytes memory sig = abi.encodeWithSignature(addFuncs[i], user1);
            (bool success, bytes memory data) = address(centralRegistry).call(
                sig
            );
            assertTrue(success);

            (, data) = address(centralRegistry).call(
                abi.encodeWithSignature(maps[i], user1)
            );
            assertTrue(abi.decode(data, (bool)));
        }
    }
}
