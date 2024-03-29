// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IWormhole } from "contracts/interfaces/external/wormhole/IWormhole.sol";
import { IWormholeRelayer } from "contracts/interfaces/external/wormhole/IWormholeRelayer.sol";
import { ITokenMessenger } from "contracts/interfaces/external/wormhole/ITokenMessenger.sol";
import { ITokenBridge } from "contracts/interfaces/external/wormhole/ITokenBridge.sol";

/// TYPES ///

/// @param isAuthorized Whether the contract is supported or not.
///                     2 = yes
///                     0 or 1 = no
/// @param messagingChainId Messaging Chain ID where this address authorized.
/// @param cveAddress CVE address on the chain.
struct OmnichainData {
    uint256 isAuthorized;
    uint16 messagingChainId;
    address cveAddress;
}

/// @param isSupported Whether the chain is supported or not.
///                    2 = yes
///                    0 or 1 = no
/// @param messagingHub Contract address for destination chains Messaging Hub.
/// @param asSourceAux Auxilliary data when chain is source.
/// @param asDestinationAux Auxilliary data when chain is destination.
/// @param cveAddress CVE address on the chain.
struct ChainData {
    uint256 isSupported;
    address messagingHub;
    uint256 asSourceAux;
    uint256 asDestinationAux;
    address cveAddress;
}

interface ICentralRegistry {
    /// @notice Returns Genesis Epoch Timestamp of Curvance.
    function genesisEpoch() external view returns (uint256);

    /// @notice Sequencer Uptime Feed address for L2.
    function sequencer() external view returns (address);

    /// @notice Returns Protocol DAO address.
    function daoAddress() external view returns (address);

    /// @notice Returns whether the caller has dao permissions or not.
    function hasDaoPermissions(address _address) external view returns (bool);

    /// @notice Returns whether the caller has elevated protocol permissions
    ///         or not.
    function hasElevatedPermissions(
        address _address
    ) external view returns (bool);

    /// @notice Returns CVE Locker address.
    function cveLocker() external view returns (address);

    /// @notice Returns CVE address.
    function cve() external view returns (address);

    /// @notice Returns veCVE address.
    function veCVE() external view returns (address);

    /// @notice Returns oCVE address.
    function oCVE() external view returns (address);

    /// @notice Returns Protocol Messaging Hub address.
    function protocolMessagingHub() external view returns (address);

    /// @notice Returns Oracle Router address.
    function oracleRouter() external view returns (address);

    /// @notice Returns feeAccumulator address.
    function feeAccumulator() external view returns (address);

    /// @notice Returns fee token address.
    function feeToken() external view returns (address);

    /// @notice Returns WormholeCore contract address.
    function wormholeCore() external view returns (IWormhole);

    /// @notice Returns WormholeRelayer contract address.
    function wormholeRelayer() external view returns (IWormholeRelayer);

    /// @notice Returns Circle Token Messenger contract address.
    function circleTokenMessenger() external view returns (ITokenMessenger);

    /// @notice Returns Wormhole TokenBridge contract address.
    function tokenBridge() external view returns (ITokenBridge);

    /// @notice Returns wormhole specific chain ID for evm chain ID.
    /// @param chainId Evm chain ID.
    function wormholeChainId(uint256 chainId) external view returns (uint16);

    /// @notice Returns CCTP domain for evm chain ID.
    /// @param chainId Evm chain ID.
    function cctpDomain(uint256 chainId) external view returns (uint16);

    /// @notice Returns Gelato sponsor address.
    function gelatoSponsor() external view returns (address);

    /// @notice Returns protocolCompoundFee, in `WAD`.
    function protocolCompoundFee() external view returns (uint256);

    /// @notice Returns protocolYieldFee, in `WAD`.
    function protocolYieldFee() external view returns (uint256);

    /// @notice Returns protocolHarvestFee, in `WAD`.
    function protocolHarvestFee() external view returns (uint256);

    /// @notice Returns protocolLeverageFee, in `WAD`.
    function protocolLeverageFee() external view returns (uint256);

    /// @notice Lending Market => Protocol Reserve Factor on interest generated.
    function protocolInterestFactor(
        address market
    ) external view returns (uint256);

    /// @notice Returns earlyUnlockPenaltyMultiplier value, in `Basis Points`
    function earlyUnlockPenaltyMultiplier() external view returns (uint256);

    /// @notice Returns voteBoostMultiplier value, in `Basis Points`
    function voteBoostMultiplier() external view returns (uint256);

    /// @notice Returns lockBoostMultiplier value, in `Basis Points`
    function lockBoostMultiplier() external view returns (uint256);

    /// @notice Returns how many other chains are supported
    function supportedChains() external view returns (uint256);

    /// @notice Address array for all Curvance Market Managers on this chain.
    function marketManagers() external view returns (address[] memory);

    /// @notice Returns `user`'s approval index.
    /// @param user The user to check approval index for.
    function userApprovalIndex(address user) external view returns (uint256);

    /// @notice Returns whether a user has delegation disabled.
    /// @param user The user to check delegation status for.
    function delegatingDisabled(address user) external view returns (bool);

    /// @notice Returns whether a particular GETH chainId is supported.
    /// ChainId => messagingHub address, 2 = supported; 1 = unsupported.
    function supportedChainData(
        uint256 chainID
    ) external view returns (ChainData memory);

    // Address => chainID => Curvance identification information.
    function getOmnichainOperators(
        address _address,
        uint256 chainID
    ) external view returns (OmnichainData memory);

    // Messaging specific ChainId => GETH comparable ChainId.
    function messagingToGETHChainId(
        uint16 chainId
    ) external view returns (uint256);

    // GETH comparable ChainId => Messaging specific ChainId.
    function GETHToMessagingChainId(
        uint256 chainId
    ) external view returns (uint16);

    /// @notice Returns whether the inputted address is an approved zapper.
    function isZapper(address addressToCheck) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved swapper.
    function isSwapper(address addressToCheck) external view returns (bool);

    /// @notice Returns whether the inputted address is an approved veCVELocker.
    function isVeCVELocker(address addressToCheck) external view returns (bool);

    /// @notice Returns whether the inputted address is a Gauge Controller.
    function isGaugeController(address addressToCheck) external view returns (bool);

    /// @notice Returns whether the inputted address is a Harvester.
    function isHarvester(address addressToCheck) external view returns (bool);

    /// @notice Returns whether the inputted address is a Market Manager.
    function isMarketManager(address addressToCheck) external view returns (bool);

    /// @notice Returns whether the inputted address is an Approved Endpoint.
    function isEndpoint(address addressToCheck) external view returns (bool);

    function externalCallDataChecker(
        address addressToCheck
    ) external view returns (address);
}
