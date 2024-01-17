pragma solidity 0.8.17;

contract ErrorConstants {
    uint256 vecve_lockTypeMismatchHash =
        uint256(uint32(bytes4(keccak256("VeCVE__LockTypeMismatch()"))));

    uint256 vecve_shutdownSelectorHash =
        uint256(uint32(bytes4(keccak256("VeCVE__VeCVEShutdown()"))));

    uint256 vecve_invalidLockSelectorHash =
        uint256(uint32(bytes4(keccak256("VeCVE__InvalidLock()"))));

    uint256 vecve_unauthorizedSelectorHash =
        uint256(uint32(bytes4(keccak256("VeCVE__Unauthorized()"))));
}
