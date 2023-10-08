// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CVEAirdrop is ReentrancyGuard {
    
    /// CONSTANTS ///

    /// @notice Maximum airdrop size any user can receive
    uint256 public immutable maxClaim;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Airdrop Merkle Root to validate claims
    bytes32 public airdropMerkleRoot;
    /// @notice Airdrop claim state; 1 = unpaused; 2 = paused
    uint256 public isPaused = 2;
    /// @notice Time by which users must claim their airdrop
    uint256 public endClaimTimestamp;
    
    /// User => Has Claimed
    mapping(address => bool) public airdropClaimed;

    /// EVENTS ///
    
    event callOptionCVEAirdropClaimed(address indexed claimer, uint256 amount);
    event RemainingCallOptionCVEWithdrawn(uint256 amount);
    event OwnerUpdated(address indexed user, address indexed newOwner);

    /// ERRORS ///

    error CVEAirdrop__Paused();
    error CVEAirdrop__ParametersareInvalid();
    error CVEAirdrop__Unauthorized();
    error CVEAirdrop__TransferError();
    error CVEAirdrop__NotEligible();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        if (!centralRegistry.hasDaoPermissions(msg.sender)){
            revert CVEAirdrop__Unauthorized();
        }
        _;
    }

    constructor(
        ICentralRegistry centralRegistry_,
        uint256 maxClaim_
    ) {
        if (!ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )){
                revert CVEAirdrop__ParametersareInvalid();
            }
        centralRegistry = centralRegistry_;
        maxClaim = maxClaim_;

    }

    /// @notice Claim CVE Call Option tokens for airdrop
    /// @param amount Requested CVE amount to claim for the airdrop
    /// @param proof Bytes32 array containing the merkle proof
    function claimAirdrop(
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        
        if (isPaused == 2){
            revert CVEAirdrop__Paused();
        }

        // Verify CVE amount request is not above the maximum claim amount
        if (amount > maxClaim){
            revert CVEAirdrop__ParametersareInvalid();
        }

        // Verify that the claim merkle root has been configured
        if (airdropMerkleRoot == bytes32(0)){
            revert CVEAirdrop__Unauthorized();
        }

        // Verify Claim window has not passed
        if (block.timestamp >= endClaimTimestamp){
            revert CVEAirdrop__NotEligible();
        }

        // Verify the user has not claimed their airdrop already
        if (airdropClaimed[msg.sender]){
            revert CVEAirdrop__NotEligible();
        }

        // Compute the merkle leaf and verify the merkle proof
        if (!verify(
                proof,
                airdropMerkleRoot,
                keccak256(abi.encodePacked(msg.sender, amount))
            )){
                revert CVEAirdrop__NotEligible();
            }

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
        if (amount > maxClaim){
            return false;
        }

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
        if (recipient == address(0)){
            revert CVEAirdrop__ParametersareInvalid();
        }

        if (token == address(0)) {
            if (amount == 0){
                amount = address(this).balance;
            }

            (bool success, ) = payable(recipient).call{ value: amount }("");
            if (!success){
                revert CVEAirdrop__TransferError();
            }
        } else {
            if (token == centralRegistry.callOptionCVE()){
                revert CVEAirdrop__TransferError();
            }

            if (amount == 0){
                amount = IERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, recipient, amount);
        }
    }

    /// @notice Withdraws unclaimed airdrop tokens to contract Owner after airdrop claim period has ended
    function withdrawRemainingAirdropTokens() external onlyDaoPermissions {
        if (block.timestamp < endClaimTimestamp){
            revert CVEAirdrop__TransferError();
        }

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
        if (newRoot == bytes32(0)){
            revert CVEAirdrop__ParametersareInvalid();
        }

        if (airdropMerkleRoot == bytes32(0)){
            if (!centralRegistry.hasElevatedPermissions(msg.sender)){
                revert CVEAirdrop__Unauthorized();
            }
        }

        airdropMerkleRoot = newRoot;
    }

    /// @notice Set isPaused state
    /// @param state new pause state
    function setPauseState(bool state) external onlyDaoPermissions {
        uint256 currentState = isPaused;
        isPaused = state ? 2: 1;

        // If it was paused prior, 
        // you need to provide users 3 months to claim their airdrop
        if (isPaused == 1 && currentState == 2){
            endClaimTimestamp = block.timestamp + (12 weeks); 
        }

    }
}
