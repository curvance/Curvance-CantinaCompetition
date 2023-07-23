// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CVEAirdrop is ReentrancyGuard {

    /// EVENTS ///
    event callOptionCVEAirdropClaimed(address indexed claimer, uint256 amount);
    event RemainingCallOptionCVEWithdrawn(uint256 amount);
    event OwnerUpdated(address indexed user, address indexed newOwner);

    /// CONSTANTS ///
    ICentralRegistry public immutable centralRegistry;
    uint256 public immutable maximumClaimAmount;
    uint256 public immutable endClaimTimestamp;

    /// STORAGE ///
    bytes32 public airdropMerkleRoot;
    bool public isPaused = true;

    mapping(address => bool) public airdropClaimed;

    constructor(
        ICentralRegistry centralRegistry_,
        uint256 endTimestamp_,
        uint256 maximumClaimAmount_,
        bytes32 root_
    ) {

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "CVEAirdrop: invalid central registry"
        );

        centralRegistry = centralRegistry_;
        endClaimTimestamp = endTimestamp_;
        maximumClaimAmount = maximumClaimAmount_;
        airdropMerkleRoot = root_;
    }

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "CVEAirdrop: UNAUTHORIZED");
        _;
    }

    modifier notPaused() {
        require(!isPaused, "CVEAirdrop: Airdrop Paused");
        _;
    }

    /// @notice Claim CVE Call Option tokens for airdrop
    /// @param amount Requested CVE amount to claim for the airdrop
    /// @param proof Bytes32 array containing the merkle proof
    function claimAirdrop(
        uint256 amount,
        bytes32[] calldata proof
    ) external notPaused nonReentrant {
        // Verify that the airdrop Merkle Root has been set
        require(
            airdropMerkleRoot != bytes32(0),
            "CVEAirdrop: Airdrop Merkle Root not set"
        );

        // Verify CVE amount request is not above the maximum claim amount
        require(
            amount <= maximumClaimAmount,
            "CVEAirdrop: Amount too high"
        );

        // Verify Claim window has not passed
        require(
            block.timestamp < endClaimTimestamp,
            "CVEAirdrop: Too late to claim"
        );

        // Verify the user has not claimed their airdrop already
        require(
            !airdropClaimed[msg.sender],
            "CVEAirdrop: Already claimed"
        );

        // Compute the merkle leaf and verify the merkle proof
        require(
            verify(
                proof,
                airdropMerkleRoot,
                keccak256(abi.encodePacked(msg.sender, amount))
            ),
            "CVEAirdrop: Invalid proof provided"
        );

        // Document that airdrop has been claimed
        airdropClaimed[msg.sender] = true;

        // Transfer CVE tokens
        SafeTransferLib.safeTransfer(centralRegistry.callOptionCVE(),
            msg.sender,
            amount
        );

        emit callOptionCVEAirdropClaimed(msg.sender, amount);
    }

    /// @dev Returns whether `leaf` exists in the Merkle tree with `root`, given `proof`.
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf)
        internal
        pure
        returns (bool isValid)
    {
        /// @solidity memory-safe-assembly
        assembly {
            if mload(proof) {
                // Initialize `offset` to the offset of `proof` elements in memory.
                let offset := add(proof, 0x20)
                // Left shift by 5 is equivalent to multiplying by 0x20.
                let end := add(offset, shl(5, mload(proof)))
                // Iterate over proof elements to compute root hash.
                for {} 1 {} {
                    // Slot of `leaf` in scratch space.
                    // If the condition is true: 0x20, otherwise: 0x00.
                    let scratch := shl(5, gt(leaf, mload(offset)))
                    // Store elements to hash contiguously in scratch space.
                    // Scratch space is 64 bytes (0x00 - 0x3f) and both elements are 32 bytes.
                    mstore(scratch, leaf)
                    mstore(xor(scratch, 0x20), mload(offset))
                    // Reuse `leaf` to store the hash to reduce stack operations.
                    leaf := keccak256(0x00, 0x40)
                    offset := add(offset, 0x20)
                    if iszero(lt(offset, end)) { break }
                }
            }
            isValid := eq(leaf, root)
        }
    }

    /// @notice Check whether a user has CVE tokens to claim
    /// @param user address of the user to check
    /// @param amount amount to claim
    /// @param proof array containing the merkle proof
    function canClaimAirdrop(
        address user,
        uint256 amount,
        bytes32[] calldata proof
    ) external view returns (bool) {
        if (!airdropClaimed[user]) {
            if (block.timestamp < endClaimTimestamp) {
                // Compute the leaf and verify the merkle proof
                return
                    verify(
                        proof,
                        airdropMerkleRoot,
                        keccak256(abi.encodePacked(user, amount))
                    );
            }
        }
        return false;
    }

    /// @dev rescue any token sent by mistake
    /// @param token token to rescue
    /// @param recipient address to receive token
    /// @param amount amount of `token` to rescue, 0 indicates to rescue all
    function rescueToken(
        address token,
        address recipient,
        uint256 amount
    ) external onlyDaoPermissions {
        require(
            recipient != address(0),
            "CVEAirdrop: Invalid recipient address"
        );
        if (token == address(0)) {
            require(
                address(this).balance >= amount,
                "CVEAirdrop: Insufficient balance"
            );
            (bool success, ) = payable(recipient).call{ value: amount }("");
            require(success, "CVEAirdrop: !successful");
        } else {
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "CVEAirdrop: Insufficient balance"
            );
            SafeTransferLib.safeTransfer(token, recipient, amount);
        }
    }

    /// @notice Withdraws unclaimed airdrop tokens to contract Owner after airdrop claim period has ended
    function withdrawRemainingAirdropTokens() external onlyDaoPermissions {
        require(
            block.timestamp > endClaimTimestamp,
            "CVEAirdrop: Too early"
        );
        uint256 tokensToWithdraw = IERC20(centralRegistry.callOptionCVE())
            .balanceOf(address(this));
        SafeTransferLib.safeTransfer(centralRegistry.callOptionCVE(),
            msg.sender,
            tokensToWithdraw
        );

        emit RemainingCallOptionCVEWithdrawn(tokensToWithdraw);
    }

    /// @notice Set airdropMerkleRoot for airdrop validation
    /// @param newRoot new merkle root
    function setMerkleRoot(bytes32 newRoot) external onlyDaoPermissions {
        require(newRoot != bytes32(0), "CVEAirdrop: Invalid Parameter");
        airdropMerkleRoot = newRoot;
    }

    /// @notice Set isPaused state
    /// @param state new pause state
    function setPauseState(bool state) external onlyDaoPermissions {
        isPaused = state;
    }
}
