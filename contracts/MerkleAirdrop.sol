// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICentralRegistry.sol";

contract CVEAirdrop {
    using SafeERC20 for IERC20;

    event callOptionCVEAirdropClaimed(address indexed claimer, uint256 amount);
    event RemainingCallOptionCVEWithdrawn(uint256 amount);
    event OwnerUpdated(address indexed user, address indexed newOwner);

    ICentralRegistry public immutable centralRegistry;
    uint256 public immutable maximumClaimAmount;
    uint256 public immutable endClaimTimestamp;

    bytes32 public airdropMerkleRoot;
    bool    public isPaused = true;
    uint256 private locked = 1;

    mapping(address => bool) public airdropClaimed;

     /**
     * @notice Constructor
     * @param _centralRegistry Contract Address of Curvance Central Registry
     * @param _endTimestamp end timestamp for airdrop claiming
     * @param _root Airdrop merkle root for claim validation
     * @param _maximumClaimAmount maximum amount to claim per address
     */
    constructor (
        ICentralRegistry _centralRegistry,
        uint256 _endTimestamp,
        uint256 _maximumClaimAmount,  
        bytes32 _root
    ) {
        centralRegistry = _centralRegistry;
        endClaimTimestamp = _endTimestamp;
        maximumClaimAmount = _maximumClaimAmount; 
        airdropMerkleRoot = _root;
    }

    modifier onlyDaoManager () {
        require(msg.sender == centralRegistry.daoAddress(), "UNAUTHORIZED");
        _;
    }

    modifier notPaused() {
        require(!isPaused, "Airdrop Paused");
        _;
    }

    modifier nonReentrant() {
        require(locked == 1, "Reentry Attempt");
        locked = 2;
        _;
        locked = 1;
    }

    function _msgSender() internal view returns (address) {
        return msg.sender;
    }

    /**
     * @notice Claim CVE Call Option tokens for airdrop
     * @param _amount Requested CVE amount to claim for the airdrop
     * @param _proof Bytes32 array containing the merkle proof
     */
    function claimAirdrop(uint256 _amount, bytes32[] calldata _proof) external notPaused nonReentrant {
        // Verify that the airdrop Merkle Root has been set
        require(airdropMerkleRoot != bytes32(0), "claimAirdrop: Airdrop Merkle Root not set");

        // Verify CVE amount request is not above the maximum claim amount
        require(_amount <= maximumClaimAmount, "claimAirdrop: Amount too high");

        // Verify Claim window has not passed
        require(block.timestamp < endClaimTimestamp, "claimAirdrop: Too late to claim");

        // Verify the user has not claimed their airdrop already
        require(!airdropClaimed[_msgSender()], "claimAirdrop: Already claimed");

        // Compute the merkle leaf and verify the merkle proof
        require(verifyProof(_proof, airdropMerkleRoot, keccak256(abi.encodePacked(_msgSender(), _amount))), "claimAirdrop: Invalid proof provided");

        // Document that airdrop has been claimed
        airdropClaimed[_msgSender()] = true;

        // Transfer CVE tokens
        IERC20(centralRegistry.callOptionCVE()).safeTransfer(_msgSender(), _amount);

        emit callOptionCVEAirdropClaimed(_msgSender(), _amount);
    }

    /**
     * @notice Gas efficient merkle proof verification implementation to validate CVE token claim
     * @param _proof Requested CVE amount to claim for the airdrop
     * @param _root Merkle root to check computed hash against
     * @param _leaf Merkle leaf containing hashed inputs to compare proof element against 
     */
    function verifyProof(bytes32[] memory _proof, bytes32 _root, bytes32 _leaf) internal pure returns (bool) {
            bytes32 computedHash = _leaf;
            uint256 iterations = _proof.length;
            bytes32 proofElement;

            for (uint256 i; i < iterations; ) {
                proofElement = _proof[i++];

                if (computedHash <= proofElement) {
                    computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
                } else {
                    computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
                }

            }
            return computedHash == _root;
    }

    /**
     * @notice Check whether a user has CVE tokens to claim
     * @param _address address of the user to check
     * @param _amount amount to claim
     * @param _proof array containing the merkle proof
     */
    function canClaimAirdrop(
        address _address,
        uint256 _amount,
        bytes32[] calldata _proof
    ) external view returns (bool) {
        if (!airdropClaimed[_address]){
            if (block.timestamp < endClaimTimestamp) {
                // Compute the leaf and verify the merkle proof
                return verifyProof(_proof, airdropMerkleRoot, keccak256(abi.encodePacked(_address, _amount)));
            }
        }
        return false;
    }

    /**
     * @dev rescue any token sent by mistake
     * @param _token token to rescue
     * @param _recipient address to receive token
     */
    function rescueToken(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyDaoManager {
        require(_recipient != address(0), "rescueToken: Invalid recipient address");
        if (_token == address(0)) {
            require(address(this).balance >= _amount, "rescueToken: Insufficient balance");
            (bool success, ) = payable(_recipient).call{ value: _amount }("");
            require(success, "rescueToken: !successful");
        } else {
            require(IERC20(_token).balanceOf(address(this)) >= _amount, "rescueToken: Insufficient balance");
            SafeERC20.safeTransfer(IERC20(_token), _recipient, _amount);
        }
    }

    /**
     * @notice Withdraws unclaimed airdrop tokens to contract Owner after airdrop claim period has ended
     */
    function withdrawRemainingAirdropTokens() external onlyDaoManager {
        require(block.timestamp > endClaimTimestamp, "withdrawRemainingAirdropTokens: Too early");
        uint256 tokensToWithdraw = IERC20(centralRegistry.callOptionCVE()).balanceOf(address(this));
        IERC20(centralRegistry.callOptionCVE()).safeTransfer(_msgSender(), tokensToWithdraw);

        emit RemainingCallOptionCVEWithdrawn(tokensToWithdraw);
    }

    /**
     * @notice Set airdropMerkleRoot for airdrop validation
     * @param _root new merkle root
     */
    function setMerkleRoot(bytes32 _root) external onlyDaoManager {
        require(_root != bytes32(0), "setMerkleRoot: Invalid Parameter");
        airdropMerkleRoot = _root;
    }

    /**
     * @notice Set isPaused state
     * @param _state new pause state
     */
    function setPauseState(bool _state) external onlyDaoManager {
        isPaused = _state;
    }

}
