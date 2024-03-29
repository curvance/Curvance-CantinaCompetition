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

    uint256 marketManager_unauthorizedSelectorHash =
        uint256(uint32(bytes4(keccak256("MarketManager__Unauthorized()"))));

    uint256 marketManager_tokenAlreadyListedSelectorHash =
        uint256(
            uint32(bytes4(keccak256("MarketManager__TokenAlreadyListed()")))
        );

    uint256 marketManager_tokenNotListedSelectorHash =
        uint256(uint32(bytes4(keccak256("MarketManager__TokenNotListed()"))));

    uint256 marketManager_insufficientCollateralSelectorHash =
        uint256(
            uint32(
                bytes4(keccak256("MarketManager__InsufficientCollateral()"))
            )
        );

    uint256 marketManager_invariantErrorSelectorHash =
        uint256(uint32(bytes4(keccak256("MarketManager__InvariantError()"))));

    uint256 marketManager_invalidParameterSelectorHash =
        uint256(
            uint32(bytes4(keccak256("MarketManager__InvalidParameter()")))
        );

    uint256 marketManager_pausedSelectorHash =
        uint256(uint32(bytes4(keccak256("MarketManager__Paused()"))));

    uint256 marketManager_noLiquidationAvailableSelectorHash =
        uint256(
            uint32(
                bytes4(keccak256("MarketManager__NoLiquidationAvailable()"))
            )
        );

    uint256 marketManager_minHoldSelectorHash =
        uint256(
            uint32(bytes4(keccak256("MarketManager__MinimumHoldPeriod()")))
        );

    uint256 marketManager_mismatchSelectorHash =
        uint256(
            uint32(bytes4(keccak256("MarketManager__MarketManagerMismatch()")))
        );

    uint256 marketManager_priceErrorSelectorHash =
        uint256(uint32(bytes4(keccak256("MarketManager__PriceError()"))));

    uint256 marketManager_insufficientUnderlyingHeldSelectorHash =
        uint256(
            uint32(bytes4(keccak256("DToken__InsufficientUnderlyingHeld()")))
        );

    uint256 token_total_supply_overflow =
        uint256(uint32(bytes4(keccak256("TotalSupplyOverflow()"))));

    uint256 token_allowance_overflow =
        uint256(uint32(bytes4(keccak256("AllowanceOverflow()"))));

    uint256 dtoken_excessive_value =
        uint256(uint32(bytes4(keccak256("DToken__ExcessiveValue()"))));

    uint256 overflow = uint256(uint32(bytes4(keccak256("MulDivFailed()"))));

    uint256 invalid_amount =
        uint256(uint32(bytes4(keccak256("InvalidAmount()"))));
}
