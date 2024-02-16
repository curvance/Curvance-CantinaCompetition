// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { CVEInitialDistribution } from "contracts/misc/CVEInitialDistribution.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import "tests/market/TestBaseMarket.sol";
import "tests/utils/merkle/Merkle.sol";

contract TestCVEInitialDistribution is TestBaseMarket {
    uint256 constant USER_LENGTH = 10;

    CVEInitialDistribution public distributor;
    Merkle public merkle;

    uint256 maxClaimAmount = 3000000 ether;
    address[] users;
    uint256[] amounts;
    bytes32[] leafs;
    bytes32 root;

    function setUp() public override {
        super.setUp();

        distributor = new CVEInitialDistribution(
            ICentralRegistry(address(centralRegistry)),
            maxClaimAmount
        );

        cve.transfer(address(distributor), cve.balanceOf(address(this)));

        for (uint256 i = 0; i < USER_LENGTH; i++) {
            users.push(address(uint160(10000000 + i)));
            amounts.push(100 ether * (i + 1));
            leafs.push(keccak256(abi.encodePacked(users[i], amounts[i])));
        }

        merkle = new Merkle();
        root = merkle.getRoot(leafs);
    }

    function testInitialize() public {
        assertEq(distributor.cve(), address(cve));
    }

    function testSetMerkleRoot() public {
        vm.expectRevert(
            CVEInitialDistribution
                .CVEInitialDistribution__ParametersAreInvalid
                .selector
        );
        distributor.setMerkleRoot(bytes32(0));

        assertEq(distributor.merkleRoot(), bytes32(0));
        distributor.setMerkleRoot(root);
        assertEq(distributor.merkleRoot(), root);
    }

    function testSetPauseState() public {
        assertEq(distributor.isPaused(), 2);
        distributor.setPauseState(true);
        assertEq(distributor.isPaused(), 1);
        assertEq(distributor.endClaimTimestamp(), block.timestamp + 6 weeks);
        distributor.setPauseState(false);
        assertEq(distributor.isPaused(), 2);
    }

    function testClaim() public {
        // for (uint256 i = 0; i < USER_LENGTH; i++) {
        //     bytes32[] memory proof = merkle.getProof(leafs, i);
        //     assertEq(distributor.canClaim(users[i], amounts[i], proof), true);
        // }
    }
}
