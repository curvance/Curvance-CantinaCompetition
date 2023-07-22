// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CVEAirdrop is ReentrancyGuard {

    event callOptionCVEAirdropClaimed(address indexed claimer, uint256 amount);
    event RemainingCallOptionCVEWithdrawn(uint256 amount);
    event OwnerUpdated(address indexed user, address indexed newOwner);

    ICentralRegistry public immutable centralRegistry;
    uint256 public immutable maximumClaimAmount;
    uint256 public immutable endClaimTimestamp;

    bytes32 public airdropMerkleRoot;
    bool public isPaused = true;

    mapping(address => bool) public airdropClaimed;

    /// @notice Constructor
    /// @param _centralRegistry Contract Address of Curvance Central Registry
    /// @param _endTimestamp end timestamp for airdrop claiming
    /// @param _root Airdrop merkle root for claim validation
    /// @param _maximumClaimAmount maximum amount to claim per address
    constructor(
        ICentralRegistry _centralRegistry,
        uint256 _endTimestamp,
        uint256 _maximumClaimAmount,
        bytes32 _root
    ) {

        require(
            ERC165Checker.supportsInterface(
                address(_centralRegistry),
                type(ICentralRegistry).interfaceId
            ),
            "CVEAirdrop: invalid central registry"
        );

        centralRegistry = _centralRegistry;
        endClaimTimestamp = _endTimestamp;
        maximumClaimAmount = _maximumClaimAmount;
        airdropMerkleRoot = _root;
    }

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier notPaused() {
        require(!isPaused, "Airdrop Paused");
        _;
    }

    /// @notice Claim CVE Call Option tokens for airdrop
    /// @param _amount Requested CVE amount to claim for the airdrop
    /// @param _proof Bytes32 array containing the merkle proof
    function claimAirdrop(
        uint256 _amount,
        bytes32[] calldata _proof
    ) external notPaused nonReentrant {
        // Verify that the airdrop Merkle Root has been set
        require(
            airdropMerkleRoot != bytes32(0),
            "claimAirdrop: Airdrop Merkle Root not set"
        );

        // Verify CVE amount request is not above the maximum claim amount
        require(
            _amount <= maximumClaimAmount,
            "claimAirdrop: Amount too high"
        );

        // Verify Claim window has not passed
        require(
            block.timestamp < endClaimTimestamp,
            "claimAirdrop: Too late to claim"
        );

        // Verify the user has not claimed their airdrop already
        require(
            !airdropClaimed[msg.sender],
            "claimAirdrop: Already claimed"
        );

        // Compute the merkle leaf and verify the merkle proof
        require(
            verifyProof(
                _proof,
                airdropMerkleRoot,
                keccak256(abi.encodePacked(msg.sender, _amount))
            ),
            "claimAirdrop: Invalid proof provided"
        );

        // Document that airdrop has been claimed
        airdropClaimed[msg.sender] = true;

        // Transfer CVE tokens
        SafeTransferLib.safeTransfer(centralRegistry.callOptionCVE(),
            msg.sender,
            _amount
        );

        emit callOptionCVEAirdropClaimed(msg.sender, _amount);
    }

    /// @notice Gas efficient merkle proof verification implementation to validate CVE token claim
    /// @param _proof Requested CVE amount to claim for the airdrop
    /// @param _root Merkle root to check computed hash against
    /// @param _leaf Merkle leaf containing hashed inputs to compare proof element against
    function verifyProof(
        bytes32[] memory _proof,
        bytes32 _root,
        bytes32 _leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = _leaf;
        uint256 numProof = _proof.length;
        bytes32 proofElement;

        for (uint256 i; i < numProof; ) {
            proofElement = _proof[i++];

            if (computedHash <= proofElement) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }
        return computedHash == _root;
    }

    /// @notice Check whether a user has CVE tokens to claim
    /// @param _address address of the user to check
    /// @param _amount amount to claim
    /// @param _proof array containing the merkle proof
    function canClaimAirdrop(
        address _address,
        uint256 _amount,
        bytes32[] calldata _proof
    ) external view returns (bool) {
        if (!airdropClaimed[_address]) {
            if (block.timestamp < endClaimTimestamp) {
                // Compute the leaf and verify the merkle proof
                return
                    verifyProof(
                        _proof,
                        airdropMerkleRoot,
                        keccak256(abi.encodePacked(_address, _amount))
                    );
            }
        }
        return false;
    }

    /// @dev rescue any token sent by mistake
    /// @param _token token to rescue
    /// @param _recipient address to receive token
    function rescueToken(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyDaoPermissions {
        require(
            _recipient != address(0),
            "rescueToken: Invalid recipient address"
        );
        if (_token == address(0)) {
            require(
                address(this).balance >= _amount,
                "rescueToken: Insufficient balance"
            );
            (bool success, ) = payable(_recipient).call{ value: _amount }("");
            require(success, "rescueToken: !successful");
        } else {
            require(
                IERC20(_token).balanceOf(address(this)) >= _amount,
                "rescueToken: Insufficient balance"
            );
            SafeTransferLib.safeTransfer(_token, _recipient, _amount);
        }
    }

    /// @notice Withdraws unclaimed airdrop tokens to contract Owner after airdrop claim period has ended
    function withdrawRemainingAirdropTokens() external onlyDaoPermissions {
        require(
            block.timestamp > endClaimTimestamp,
            "withdrawRemainingAirdropTokens: Too early"
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
    /// @param _root new merkle root
    function setMerkleRoot(bytes32 _root) external onlyDaoPermissions {
        require(_root != bytes32(0), "setMerkleRoot: Invalid Parameter");
        airdropMerkleRoot = _root;
    }

    /// @notice Set isPaused state
    /// @param _state new pause state
    function setPauseState(bool _state) external onlyDaoPermissions {
        isPaused = _state;
    }
}
