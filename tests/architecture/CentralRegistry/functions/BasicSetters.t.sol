// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract BasicSettersTest is TestBaseMarket {
    event CoreContractSet(string indexed contractType, address newAddress);

    string[] setters;
    string[] getters;
    string[] expectedLogs;

    function setUp() public virtual override {
        super.setUp();

        setters = [
            "setCVE(address)",
            "setVeCVE(address)",
            "setOCVE(address)",
            "setCVELocker(address)",
            "setProtocolMessagingHub(address)",
            "setPriceRouter(address)",
            "setZroAddress(address)",
            "setFeeAccumulator(address)"
        ];
        getters = [
            "cve()",
            "veCVE()",
            "oCVE()",
            "cveLocker()",
            "protocolMessagingHub()",
            "priceRouter()",
            "zroAddress()",
            "feeAccumulator()"
        ];
        expectedLogs = [
            "CVE",
            "VeCVE",
            "oCVE",
            "CVE Locker",
            "Protocol Messaging Hub",
            "Price Router",
            "ZRO",
            "Fee Accumulator"
        ];
    }

    function test_setter_fail_whenUnauthorized() public {
        uint8 length = uint8(setters.length);
        for (uint256 i; i < length; i++) {
            vm.startPrank(address(0));
            bytes memory sig = abi.encodeWithSignature(setters[i], user1);
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

    function test_setter_success() public {
        uint8 length = uint8(setters.length);
        for (uint256 i; i < length; i++) {
            address newAddr = user1;

            vm.expectEmit(true, true, true, true);
            emit CoreContractSet(expectedLogs[i], newAddr);

            bytes memory setterSig = abi.encodeWithSignature(
                setters[i],
                user1
            );
            (bool success, ) = address(centralRegistry).call(setterSig);
            assertTrue(success);

            bytes memory getterSig = abi.encodeWithSignature(
                getters[i],
                user1
            );
            (, bytes memory result) = address(centralRegistry).call(getterSig);
            address resultAddr = abi.decode(result, (address));

            assertEq(resultAddr, newAddr);
        }
    }
}
