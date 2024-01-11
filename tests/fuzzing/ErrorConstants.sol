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

    uint256 lendtroller_unauthorizedSelectorHash =
        uint256(uint32(bytes4(keccak256("Lendtroller__Unauthorized()"))));

    uint256 lendtroller_tokenAlreadyListedSelectorHash =
        uint256(
            uint32(bytes4(keccak256("Lendtroller__TokenAlreadyListed()")))
        );

    uint256 lendtroller_tokenNotListedSelectorHash =
        uint256(uint32(bytes4(keccak256("Lendtroller__TokenNotListed()"))));

    uint256 lendtroller_insufficientCollateralSelectorHash =
        uint256(
            uint32(bytes4(keccak256("Lendtroller__InsufficientCollateral()")))
        );

    uint256 lendtroller_invariantErrorSelectorHash =
        uint256(uint32(bytes4(keccak256("Lendtroller__InvariantError()"))));

    uint256 lendtroller_pausedSelectorHash =
        uint256(uint32(bytes4(keccak256("Lendtroller__Paused()"))));
}
