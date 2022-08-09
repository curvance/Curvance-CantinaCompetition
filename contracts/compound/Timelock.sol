// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/SafeMath.sol";

contract Timelock {
    using SafeMath for uint;

    error MinimumDelayNotMet();
    error MaximumDelayExceeded();
    error AddressUnauthorized();
    error TimelockNotMet();
    error TransactionStale();
    error TransactionNotQueued();
    error TransactionFailed();

    event NewAdmin(address indexed newAdmin);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event NewDelay(uint indexed newDelay);
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature,  bytes data, uint eta);
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature,  bytes data, uint eta);
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);

    uint public constant GRACE_PERIOD = 14 days;
    uint public constant MINIMUM_DELAY = 2 days;
    uint public constant MAXIMUM_DELAY = 30 days;

    address public admin;
    address public pendingAdmin;
    uint public delay;

    mapping (bytes32 => bool) public queuedTransactions;


    constructor(address admin_, uint delay_) {
        if (delay_ < MINIMUM_DELAY) {
            revert MinimumDelayNotMet();
        }
        if (delay_ > MAXIMUM_DELAY) {
            revert MaximumDelayExceeded();
        }

        admin = admin_;
        delay = delay_;
    }

    receive() external payable {}

    function setDelay(uint delay_) public {
        if (msg.sender != address(this)) {
            revert AddressUnauthorized();
        }
        if (delay_ < MINIMUM_DELAY) {
            revert MinimumDelayNotMet();
        }
        if (delay_ > MAXIMUM_DELAY) {
            revert MaximumDelayExceeded();
        }
        
        delay = delay_;

        emit NewDelay(delay);
    }

    function acceptAdmin() public {
        if (msg.sender != pendingAdmin) {
            revert AddressUnauthorized();
        }
        admin = msg.sender;
        pendingAdmin = address(0);

        emit NewAdmin(admin);
    }

    function setPendingAdmin(address pendingAdmin_) public {
        if (msg.sender != address(this)) {
            revert AddressUnauthorized();
        }
        pendingAdmin = pendingAdmin_;

        emit NewPendingAdmin(pendingAdmin);
    }

    function queueTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public returns (bytes32) {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }
        if (eta < getBlockTimestamp().add(delay)) {
            revert TimelockNotMet();
        }
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    function executeTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public payable returns (bytes memory) {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        if (!queuedTransactions[txHash]) {
            revert TransactionNotQueued();
        }
        if (eta < getBlockTimestamp().add(delay)) {
            revert TimelockNotMet();
        }
        if (eta > eta.add(GRACE_PERIOD)) {
            revert TransactionStale();
        }

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        if (!success) {
            revert TransactionFailed();
        }

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

    function getBlockTimestamp() internal view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }
}
