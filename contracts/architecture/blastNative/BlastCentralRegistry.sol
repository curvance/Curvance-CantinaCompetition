// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CentralRegistry, ICentralRegistry, IMToken } from "contracts/architecture/CentralRegistry.sol";

import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IBlastNativeYieldManager } from "contracts/interfaces/blast/IBlastNativeYieldManager.sol";
import { IBlastCentralRegistry } from "contracts/interfaces/blast/IBlastCentralRegistry.sol";
import { IBlast } from "contracts/interfaces/external/blast/IBlast.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";

contract BlastCentralRegistry is CentralRegistry {

    /// CONSTANT ///

    /// @notice The address is managing WETH yield, also the token itself.
    /// @dev Will change when deploying to mainnet.
    IWETH public constant WETH = IWETH(0x4200000000000000000000000000000000000004);

    /// STORAGE ///

    /// @notice The address of Curvance's native Yield Manager.
    address public immutable nativeYieldManager;

    /// ERRORS ///

    error BlastCentralRegistry__Unauthorized();
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
        hasDaoPermissions[nativeYieldManager] = true;

        IBlast yieldConfiguration = IBlast(0x4300000000000000000000000000000000000002);

        // Set gas fees yield to claimable and then pass Governor
        // permissioning to native yield manager.
        yieldConfiguration.configureClaimableGas();
        yieldConfiguration.configureGovernor(daoAddress);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Withdraws all native yield fees from non-MToken addresses.
    /// @param nonMTokens Array of non-MTokens addresses to withdraw native
    ///                   from.
    function withdrawNativeYield(address[] calldata nonMTokens) external {
        // Match permissioning check to normal withdrawReserves().
        _checkDaoPermissions();

        uint256 nonMTokensLength = nonMTokens.length;
        if (nonMTokensLength == 0) {
            _revert(_PARAMETERS_MISCONFIGURED_SELECTOR);
        }

        // Cache Yield Manager storage value.
        IBlastNativeYieldManager yieldManager =IBlastNativeYieldManager(
            nativeYieldManager
        );
        address nonMToken;

        for (uint256 i; i < nonMTokensLength; ) {
            nonMToken = nonMTokens[i++];

            // Try to call isCToken as if the address was an mToken.
            (bool success, ) = nonMToken.staticcall(
                abi.encodePacked(IMToken(nonMToken).isCToken.selector)
            );
            // If the call was successful we called a Curvance mToken which
            // DAO should not be able to claim rewards for.
            if (success) {
                revert BlastCentralRegistry__Unauthorized();
            }
        }

        yieldManager.claimPendingNativeYield(nonMTokens);
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

        IBlastNativeYieldManager(nativeYieldManager).notifyIsMarketManager(
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

        IBlastNativeYieldManager(nativeYieldManager).notifyIsMarketManager(
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
            interfaceId == type(IBlastCentralRegistry).interfaceId ||
            interfaceId == type(ICentralRegistry).interfaceId;
    }
}
