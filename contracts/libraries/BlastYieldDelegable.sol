// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IBlastCentralRegistry } from "contracts/interfaces/blast/IBlastCentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { IBlast } from "contracts/interfaces/external/blast/IBlast.sol";

/// @title Blast Yield Delegable
/// @notice Delegates gas refunds to Curvance DAO Central Registry on Blast.
abstract contract BlastYieldDelegable {

    error BlastYieldDelegable__InvalidCentralRegistry();

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        // We take in the Central Registry contract so it is plug and play
        // with any Curvance contract that normally expects ICentralRegistry,
        // but we check against IBlastCentralRegistry which will naturally
        // work due to supportsInterface implementation in BlastCentralRegistry.
        // To make sure that we will actually be able to pull the native yield
        // manager.
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(IBlastCentralRegistry).interfaceId
            )
        ) {
            revert BlastYieldDelegable__InvalidCentralRegistry();
        }

        IBlast yieldConfiguration = IBlast(0x4300000000000000000000000000000000000002);

        // Set gas fees yield to claimable and then pass Governor
        // permissioning to native yield manager.
        yieldConfiguration.configureClaimableGas();
        yieldConfiguration.configureGovernor(
            IBlastCentralRegistry(address(centralRegistry_)).nativeYieldManager()
        );
    }
}
