// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;


import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

import { IBlastNativeYieldRouter } from "contracts/interfaces/blast/IBlastNativeYieldRouter.sol";
import { IBlastCentralRegistry } from "contracts/interfaces/blast/IBlastCentralRegistry.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract BlastCentralRegistry is CentralRegistry {

    /// STORAGE ///

    address public immutable nativeYieldManager;
 
    /// ERRORS ///

    error BlastCentralRegistry__InvalidNativeYieldManager();

    /// CONSTRUCTOR ///

    constructor(
        address daoAddress_,
        address timelock_,
        address emergencyCouncil_,
        uint256 genesisEpoch_,
        address sequencer_,
        address feeToken_,
        address nativeYieldManager_
    ) CentralRegistry (
        daoAddress_,
        timelock_,
        emergencyCouncil_,
        genesisEpoch_,
        sequencer_,
        feeToken_
    ){
        if (nativeYieldManager_ == address(0)) {
            revert CentralRegistry__InvalidFeeToken();
        }

        nativeYieldManager = nativeYieldManager_;
        // Provide base dao permissioning to `nativeYieldManager`,
        // so that it can register native yield rewards in the gauge system.
        hasDaoPermissions[daoAddress] = true;
       
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Adds a new Market Manager and associated fee configurations. 
    ///         Then notifies the native yield router of the Market Manager
    ///         addition.
    /// @dev Only callable on a 7 day delay or by the Emergency Council,
    ///      can only have a maximum value of 50% interest fee.
    ///      Cannot be a supported Market Manager contract prior.
    ///      Emits a {NewCurvanceContract} and {InterestFeeSet} events.
    /// @param newMarketManager The new Market Manager contract to support
    ///                         for use in Curvance.
    /// @param marketInterestFactor The interest factor associated with
    ///                             the market manager.
    function addMarketManager(
        address newMarketManager,
        uint256 marketInterestFactor
    ) public override {
        super.addMarketManager(newMarketManager, marketInterestFactor);

        IBlastNativeYieldRouter(nativeYieldManager).notifyIsMarketManager(
            newMarketManager,
            true
        );
    }

    /// @notice Removes a current market manager from Curvance.
    ///         Then notifies the native yield router of the Market Manager
    ///         removal.
    /// @dev Only callable on a 7 day delay or by the Emergency Council.
    ///      Has to be a supported Market Manager contract prior. 
    ///      Emits a {RemovedCurvanceContract} event.
    /// @param currentMarketManager The supported Market Manager contract
    ///                             to remove from Curvance.
    function removeMarketManager(address currentMarketManager) public override {
        super.removeMarketManager(currentMarketManager);

        IBlastNativeYieldRouter(nativeYieldManager).notifyIsMarketManager(
            currentMarketManager,
            false
        );
    }

    /// @notice Returns true if this contract implements the interface defined by
    ///         `interfaceId`.
    /// @param interfaceId The interface to check for implementation.
    /// @return Whether `interfaceId` is implemented or not.
    function supportsInterface(
        bytes4 interfaceId
    ) public pure override returns (bool) {
        return
            interfaceId == type(ICentralRegistry).interfaceId ||
            interfaceId == type(ICentralRegistry).interfaceId;
    }
}
