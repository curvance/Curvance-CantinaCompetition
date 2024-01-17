// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/external/ReentrancyGuard.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

contract CVEAirdrop is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice CVE claim boost for choosing a locked distribution.
    uint256 public constant lockedClaimMultiplier = 5;

    /// @notice CVE contract address.
    address public immutable cve;
    /// @notice VeCVE contract address.
    IVeCVE public immutable veCVE;
    /// @notice Maximum claim size anyone can receive.
    uint256 public immutable maximumClaimAmount;
    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Airdrop Merkle Root to validate claims.
    bytes32 public merkleRoot;
    /// @notice Airdrop claim state; 1 = unpaused; 2 = paused.
    uint256 public isPaused = 2;
    /// @notice Time by which users must submit a claim by.
    uint256 public endClaimTimestamp;

    /// @notice User => has claimed.
    mapping(address => bool) public airdropClaimed;

    /// EVENTS ///

    event AirdropClaimed(address indexed claimer, uint256 amount);
    event RemainingTokensWithdrawn(uint256 amount);

    /// ERRORS ///

    error CVEAirdrop__Paused();
    error CVEAirdrop__InvalidCentralRegistry();
    error CVEAirdrop__ParametersAreInvalid();
    error CVEAirdrop__Unauthorized();
    error CVEAirdrop__TransferError();
    error CVEAirdrop__NotEligible();
    error CVEAirdrop__InvalidlockedClaimMultiplier();

    constructor(
        ICentralRegistry centralRegistry_, 
        uint256 maximumClaimAmount_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CVEAirdrop__InvalidCentralRegistry();
        }
        centralRegistry = centralRegistry_;

        // Sanity check that maximumClaimAmount and lockedClaimMultiplier
        // are not horribly misconfigured. A single claim taking the entire
        // community incentive airdrop would not make any sense, 
        // in practice the values should be significantly smaller.
        if (maximumClaimAmount * lockedClaimMultiplier > 1575000259e16) {
            revert CVEAirdrop__InvalidlockedClaimMultiplier();
        }

        cve = centralRegistry.cve();
        veCVE = IVeCVE(centralRegistry.veCVE());
        maximumClaimAmount = maximumClaimAmount_;
    }

    /// @notice Claim allocated CVE.
    /// @param amount Requested amount to claim.
    /// @param locked Whether the claim should be claimed in boosted lock
    ///               form or not.
    /// @param proof Bytes32 array containing the merkle proof.
    function claimAirdrop(
        uint256 amount,
        bool locked,
        bytes32[] calldata proof
    ) external nonReentrant {
        if (isPaused == 2) {
            revert CVEAirdrop__Paused();
        }

        // Verify `amount` is not above the maximum claim amount.
        if (amount > maximumClaimAmount) {
            revert CVEAirdrop__ParametersAreInvalid();
        }

        // Verify that the claim merkle root has been configured.
        if (merkleRoot == bytes32(0)) {
            revert CVEAirdrop__Unauthorized();
        }

        // Verify claim window has not passed.
        if (block.timestamp >= endClaimTimestamp) {
            revert CVEAirdrop__NotEligible();
        }

        // Verify the caller has not claimed already.
        if (airdropClaimed[msg.sender]) {
            revert CVEAirdrop__NotEligible();
        }

        // Compute the merkle leaf and verify the merkle proof.
        if (
            !verify(
                proof,
                merkleRoot,
                keccak256(abi.encodePacked(msg.sender, amount))
            )
        ) {
            revert CVEAirdrop__NotEligible();
        }

        // Document that the callers airdrop has been claimed.
        airdropClaimed[msg.sender] = true;

        // Check whether the claimer prefers a boosted lock version
        // or liquid version.
        if (locked) {
            RewardsData memory emptyData;
            uint256 boostedAmount = amount * lockedClaimMultiplier;
            SafeTransferLib.safeApprove(cve, address(veCVE), boostedAmount);

            // Create a boosted continuous lock for the caller.
            veCVE.createLockFor(
                msg.sender,
                boostedAmount,
                true,
                emptyData,
                "",
                0
            );
        } else {
            // Transfer CVE tokens.
            SafeTransferLib.safeTransfer(
                cve,
                msg.sender,
                amount
            );
        }

        // AirdropClaimed should always emit events based on the base amount.
        emit AirdropClaimed(msg.sender, amount);
    }

    /// @notice Check whether a user has CVE tokens to claim.
    /// @param user Address of the user to check.
    /// @param amount Amount to claim.
    /// @param proof Array containing the merkle proof.
    function canClaimAirdrop(
        address user,
        uint256 amount,
        bytes32[] calldata proof
    ) external view returns (bool) {
        if (amount > maximumClaimAmount) {
            return false;
        }

        if (!airdropClaimed[user]) {
            if (block.timestamp < endClaimTimestamp) {
                // Compute the leaf and verify the merkle proof.
                return
                    verify(
                        proof,
                        merkleRoot,
                        keccak256(abi.encodePacked(user, amount))
                    );
            }
        }

        return false;
    }

    /// @dev Rescue any token sent by mistake to this contract.
    /// @param token The token address to rescue.
    /// @param amount Amount of `token` to rescue, 0 indicates to rescue all.
    function rescueToken(
        address token,
        uint256 amount
    ) external {
        _checkDaoPermissions();
        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (amount == 0) {
                amount = address(this).balance;
            }

            SafeTransferLib.forceSafeTransferETH(daoOperator, amount);
        } else {
            if (token == cve) {
                revert CVEAirdrop__TransferError();
            }

            if (amount == 0) {
                amount = IERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// @notice Withdraws unclaimed tokens to the DAO after the claim
    ///         period has ended.
    function withdrawRemainingTokens() external {
        _checkDaoPermissions();

        if (block.timestamp < endClaimTimestamp) {
            revert CVEAirdrop__TransferError();
        }

        uint256 amount = IERC20(cve).balanceOf(address(this));
        SafeTransferLib.safeTransfer(
            cve, 
            centralRegistry.daoAddress(), 
            amount
        );

        emit RemainingTokensWithdrawn(amount);
    }

    /// @notice Set merkleRoot for airdrop validation.
    /// @param newRoot New merkle root.
    function setMerkleRoot(bytes32 newRoot) external {
        _checkDaoPermissions();
        
        if (newRoot == bytes32(0)) {
            revert CVEAirdrop__ParametersAreInvalid();
        }

        if (merkleRoot == bytes32(0)) {
            if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
                revert CVEAirdrop__Unauthorized();
            }
        }

        merkleRoot = newRoot;
    }

    /// @notice Set isPaused state.
    /// @param state New pause state.
    function setPauseState(bool state) external {
        _checkDaoPermissions();
        
        uint256 currentState = isPaused;
        isPaused = state ? 2 : 1;

        // If it was paused prior,
        // you need to provide users 6 weeks to claim their airdrop
        if (isPaused == 1 && currentState == 2) {
            endClaimTimestamp = block.timestamp + (6 weeks);
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev Returns whether `leaf` exists in the Merkle tree with `root`,
    ///      given `proof`.
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool isValid) {
        /// @solidity memory-safe-assembly
        assembly {
            if mload(proof) {
                // Initialize `offset` to the offset of `proof` elements in memory.
                let offset := add(proof, 0x20)
                // Left shift by 5 is equivalent to multiplying by 0x20.
                let end := add(offset, shl(5, mload(proof)))
                // Iterate over proof elements to compute root hash.
                for {

                } 1 {

                } {
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
                    if iszero(lt(offset, end)) {
                        break
                    }
                }
            }
            isValid := eq(leaf, root)
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert CVEAirdrop__Unauthorized();
        }
    }
}
