// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MerkleAirdrop.sol";

interface IMerkleAirdrop {
    function init(
        address _token,
        uint256 _startTime,
        uint256 _endTime,
        bytes32 _merkleRoot
    ) external;
}

contract MerkleAirdropFactory is Ownable {
    address public airdropImplementation;

    mapping(address => bool) public instances;

    event Cloned(address instance);

    constructor(address _airdropImplementation) {
        airdropImplementation = _airdropImplementation;
    }

    /**
     * @dev clone and initialize contract
     * @param _token address of airdrop token
     * @param _startTime time to start airdrop claim
     * @param _endTime time to end airdrop claim
     * @param _merkleRoot troot of merkle tree implementation
     */
    function cloneAndInit(
        address _token,
        uint256 _startTime,
        uint256 _endTime,
        bytes32 _merkleRoot
    ) external onlyOwner returns (address) {
        address instance = Clones.clone(airdropImplementation);
        IMerkleAirdrop(instance).init(_token, _startTime, _endTime, _merkleRoot);
        instances[instance] = true;
        emit Cloned(instance);
        return instance;
    }
}
