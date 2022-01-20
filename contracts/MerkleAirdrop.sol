// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Allows anyone to claim a token if they exist in a merkle root.
interface IMerkleDistributor {
    // Returns the merkle root of the merkle tree containing account balances available to claim.
    function merkleRoot() external view returns (bytes32);

    // Returns true if the index has been marked claimed.
    function isClaimed(uint256 index) external view returns (bool);

    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid.
    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, address account, uint256 amount);
}

interface IMerkleAirdropFactory {
    function owner() external returns (address);
}

contract MerkleAirdrop is IMerkleDistributor, Initializable {
    using SafeERC20 for IERC20;
    using Address for address;

    address public factory;
    address public token;

    uint256 public startClaimTimestamp;
    uint256 public endClaimTimestamp;
    bytes32 public override merkleRoot;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    modifier onlyOwner() {
        require(msg.sender == IMerkleAirdropFactory(factory).owner(), "!auth");
        _;
    }

    constructor() {}

    receive() external payable {}

    /**
     * @dev initialize contract variables
     * @param _token airdrop token
     * @param _startTime time to start claiming airdrop
     * @param _merkleRoot merkle root hash of merkleroot implementation
     */
    function init(
        address _token,
        uint256 _startTime,
        uint256 _endTime,
        bytes32 _merkleRoot
    ) external initializer {
        require(_token != address(0), "!valid token");
        require(block.timestamp >= _startTime && block.timestamp < _endTime, "!valid time");
        factory = msg.sender;
        token = _token;
        startClaimTimestamp = _startTime;
        endClaimTimestamp = _endTime;
        merkleRoot = _merkleRoot;
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
    ) external onlyOwner {
        require(_recipient != address(0), "!valid recipient");
        if (_token == address(0)) {
            require(address(this).balance >= _amount, "!amount");
            (bool success, ) = payable(_recipient).call{ value: _amount }("");
            require(success, "!successful");
        } else {
            require(IERC20(_token).balanceOf(address(this)) >= _amount, "!amount");
            SafeERC20.safeTransfer(IERC20(_token), _recipient, _amount);
        }
    }

    /**
     * @dev Set time to end claim.
     * @param _endTime new timestamp.
     */
    function setClaimEndTimestamp(uint256 _endTime) external onlyOwner {
        require(_endTime > block.timestamp && _endTime > startClaimTimestamp, "!valid");
        endClaimTimestamp = _endTime;
    }

    /**
     * @notice Check if airdrop claimed.
     * @param index index to check.
     * @return bool
     */
    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    /**
     * @notice Set airdrop claimed.
     * @param index index to set claimed.
     */
    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    /**
     * @notice Claim airdrop.
     * @param index index at which to claim.
     * @param account claiming account.
     * @param amount claiming amount
     * @param merkleProof sequence of merkle proof.
     */
    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external override {
        require(block.timestamp >= startClaimTimestamp && block.timestamp < endClaimTimestamp, "!valid time");
        require(!isClaimed(index), "already claimed.");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "!valid proof");

        // Mark it claimed and send the token.
        _setClaimed(index);

        // transfer to account
        IERC20(token).safeTransfer(account, amount);

        emit Claimed(index, account, amount);
    }
}
