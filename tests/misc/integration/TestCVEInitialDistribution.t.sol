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
        distributor.setPauseState(false);
        assertEq(distributor.isPaused(), 1);
        assertEq(distributor.endClaimTimestamp(), block.timestamp + 6 weeks);
        distributor.setPauseState(true);
        assertEq(distributor.isPaused(), 2);
    }

    function testCanClaim() public {
        distributor.setMerkleRoot(root);
        distributor.setPauseState(false);

        for (uint256 i = 0; i < USER_LENGTH; i++) {
            bytes32[] memory proof = merkle.getProof(leafs, i);
            assertEq(distributor.canClaim(users[i], amounts[i], proof), true);
        }
    }

    function testClaimWithoutLock() public {
        distributor.setMerkleRoot(root);
        distributor.setPauseState(false);

        for (uint256 i = 0; i < USER_LENGTH; i++) {
            bytes32[] memory proof = merkle.getProof(leafs, i);

            vm.startPrank(users[i]);
            distributor.claim(amounts[i], false, proof);
            vm.stopPrank();

            assertEq(cve.balanceOf(users[i]), amounts[i]);
        }
    }

    function testClaimWithLock() public {
        distributor.setMerkleRoot(root);
        distributor.setPauseState(false);

        centralRegistry.addVeCVELocker(address(distributor));

        for (uint256 i = 0; i < USER_LENGTH; i++) {
            bytes32[] memory proof = merkle.getProof(leafs, i);

            vm.startPrank(users[i]);
            distributor.claim(amounts[i], true, proof);
            vm.stopPrank();

            assertEq(
                veCVE.balanceOf(users[i]),
                amounts[i] * distributor.lockedClaimMultiplier()
            );
        }
    }

    function testClaimRevert__Paused() public {
        distributor.setMerkleRoot(root);

        bytes32[] memory proof = merkle.getProof(leafs, 0);

        vm.expectRevert(
            CVEInitialDistribution.CVEInitialDistribution__Paused.selector
        );
        vm.startPrank(users[0]);
        distributor.claim(amounts[0], false, proof);
        vm.stopPrank();
    }

    function testClaimRevert__ParametersAreInvalid() public {
        distributor.setMerkleRoot(root);
        distributor.setPauseState(false);

        bytes32[] memory proof = merkle.getProof(leafs, 0);

        vm.expectRevert(
            CVEInitialDistribution
                .CVEInitialDistribution__ParametersAreInvalid
                .selector
        );
        vm.startPrank(users[0]);
        distributor.claim(maxClaimAmount + 1, false, proof);
        vm.stopPrank();
    }

    function testClaimRevert__Unauthorized() public {
        distributor.setPauseState(false);

        bytes32[] memory proof = merkle.getProof(leafs, 0);
        vm.expectRevert(
            CVEInitialDistribution
                .CVEInitialDistribution__Unauthorized
                .selector
        );
        vm.startPrank(users[0]);
        distributor.claim(amounts[0], false, proof);
        vm.stopPrank();
    }

    function testClaimRevert__NotEligible() public {
        distributor.setMerkleRoot(root);
        distributor.setPauseState(false);

        bytes32[] memory proof = merkle.getProof(leafs, 0);
        vm.startPrank(users[0]);
        distributor.claim(amounts[0], false, proof);
        vm.stopPrank();

        vm.expectRevert(
            CVEInitialDistribution.CVEInitialDistribution__NotEligible.selector
        );
        vm.startPrank(users[0]);
        distributor.claim(amounts[0], false, proof);
        vm.stopPrank();

        skip(7 weeks);

        vm.expectRevert(
            CVEInitialDistribution.CVEInitialDistribution__NotEligible.selector
        );
        vm.startPrank(users[0]);
        distributor.claim(amounts[0], false, proof);
        vm.stopPrank();
    }
}
