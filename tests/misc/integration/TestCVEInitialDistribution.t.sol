// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { CVEInitialDistribution } from "contracts/misc/CVEInitialDistribution.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import "tests/market/TestBaseMarket.sol";

contract TestCVEInitialDistribution is TestBaseMarket {
    CVEInitialDistribution public distributor;

    uint256 maxClaimAmount = 3000000e18;
    address[5] users;
    uint256[5] amounts;
    bytes32[5] leafs;
    bytes32[][5] proofs;
    bytes32 root;

    function setUp() public override {
        super.setUp();

        distributor = new CVEInitialDistribution(
            ICentralRegistry(address(centralRegistry)),
            maxClaimAmount
        );

        cve.transfer(address(distributor), cve.balanceOf(address(this)));

        root = 0xf96db03ea9b4228ecd84e1075b6ec596a28c803672d4fbf96507b47017ac46af;
        users[0] = 0x0109492Ee14ACD69Cb15cc2E13d96829d7bba73A;
        amounts[0] = 123e18;
        leafs[
            0
        ] = 0xeb0c590fe8e7d235364648d1c45efd3a86d208693de20ef6cf6024ce39be75a0;
        proofs[0].push(
            0xba39399a0b074595a1d0dbc0fdb9c1c0c2b832ee7c01a7c6832025679ceffde5
        );

        users[1] = 0x70DcC0995908eA307764e7a22B6C531e1926597A;
        amounts[1] = 321e18;
        leafs[
            1
        ] = 0xa6d8b5ae2cc05998ca5007426f480240909768d7d4abf32aceb44f56ba33436e;
        proofs[1].push(
            0x6702a39cc50c6597803f84396c63d98ecf83bf49f5d2802269483b894bdcb2b3
        );
        proofs[1].push(
            0xc338281c0937d7bdbac619b7be7f571f5dd634c6b4919df3fdabfc9c999501ca
        );
        proofs[1].push(
            0xeb0c590fe8e7d235364648d1c45efd3a86d208693de20ef6cf6024ce39be75a0
        );

        users[2] = 0x4f46b417e07b513Db5eeeFA97a2A09219006c01E;
        amounts[2] = 567e18;
        leafs[
            2
        ] = 0xcd010d8360f8899772664ecff9de1ec4bfcc7352f0a76c31dac8279e1cee5c57;
        proofs[2].push(
            0xd6c4e93904326459e486e52c5408055ef2f7e67c9b2a1a820e559cda07b18fd5
        );
        proofs[2].push(
            0x1a003448966f4b0f9b65b21b97a4e35229de3104c0e81cbd8597496f6a776d8c
        );
        proofs[2].push(
            0xeb0c590fe8e7d235364648d1c45efd3a86d208693de20ef6cf6024ce39be75a0
        );

        users[3] = 0x8f389F310797885209b3dd69708efade53cAb50e;
        amounts[3] = 765e18;
        leafs[
            3
        ] = 0x6702a39cc50c6597803f84396c63d98ecf83bf49f5d2802269483b894bdcb2b3;
        proofs[3].push(
            0xa6d8b5ae2cc05998ca5007426f480240909768d7d4abf32aceb44f56ba33436e
        );
        proofs[3].push(
            0xc338281c0937d7bdbac619b7be7f571f5dd634c6b4919df3fdabfc9c999501ca
        );
        proofs[3].push(
            0xeb0c590fe8e7d235364648d1c45efd3a86d208693de20ef6cf6024ce39be75a0
        );

        users[4] = 0xF3d356Ec267AB90f6c2210247309627439c1B9f7;
        amounts[4] = 912e18;
        leafs[
            4
        ] = 0xd6c4e93904326459e486e52c5408055ef2f7e67c9b2a1a820e559cda07b18fd5;
        proofs[4].push(
            0xcd010d8360f8899772664ecff9de1ec4bfcc7352f0a76c31dac8279e1cee5c57
        );
        proofs[4].push(
            0x1a003448966f4b0f9b65b21b97a4e35229de3104c0e81cbd8597496f6a776d8c
        );
        proofs[4].push(
            0xeb0c590fe8e7d235364648d1c45efd3a86d208693de20ef6cf6024ce39be75a0
        );
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

        for (uint256 i = 0; i < 5; i++) {
            assertEq(
                distributor.canClaim(users[i], amounts[i], proofs[i]),
                true
            );
        }
    }
}
