// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/ERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/wormhole/ITokenBridgeRelayer.sol";
import { IProtocolMessagingHub } from "contracts/interfaces/IProtocolMessagingHub.sol";

contract CVE is ERC20 {
    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Wormhole TokenBridgeRelayer.
    ITokenBridgeRelayer public immutable tokenBridgeRelayer;

    /// @notice Address of Wormhole core contract.
    IWormhole public immutable wormhole;

    /// `bytes4(keccak256(bytes("CVE__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x15f37077;

    /// ERRORS ///

    error CVE__Unauthorized();
    error CVE__ParametersAreInvalid();
    error CVE__TokenBridgeRelayerIsZeroAddress();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address tokenBridgeRelayer_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CVE__ParametersAreInvalid();
        }
        if (tokenBridgeRelayer_ == address(0)) {
            revert CVE__TokenBridgeRelayerIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        tokenBridgeRelayer = ITokenBridgeRelayer(tokenBridgeRelayer_);
        wormhole = ITokenBridgeRelayer(tokenBridgeRelayer_).wormhole();
    }

    /// EXTERNAL FUNCTIONIS ///

    /// @notice Mints gauge emissions for the desired gauge pool
    /// @dev Allows the VotingHub to mint new gauge emissions.
    /// @param gaugePool The address of the gauge pool where emissions will be
    ///                  configured.
    /// @param amount The amount of gauge emissions to be minted
    function mintGaugeEmissions(address gaugePool, uint256 amount) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _mint(gaugePool, amount);
    }

    /// @notice Mints CVE to the calling gauge pool to fund the users
    ///         lock boost.
    /// @param amount The amount of tokens to be minted
    function mintLockBoost(uint256 amount) external {
        if (!centralRegistry.isGaugeController(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _mint(msg.sender, amount);
    }

    /// @param dstChainId Chain ID of the target blockchain.
    /// @param recipient The address of recipient on destination chain.
    /// @param amount The amount of token to bridge.
    /// @return Wormhole sequence for emitted TransferTokensWithRelay message.
    function bridge(
        uint256 dstChainId,
        address recipient,
        uint256 amount
    ) external payable returns (uint64) {
        address messagingHub = centralRegistry.protocolMessagingHub();
        _burn(msg.sender, amount);
        _mint(messagingHub, amount);

        return
            IProtocolMessagingHub(messagingHub).bridgeCVE{ value: msg.value }(
                dstChainId,
                recipient,
                amount
            );
    }

    /// @notice Returns required amount of token for relayer fee.
    /// @param dstChainId Chain ID of the target blockchain.
    /// @return Required fee.
    function relayerFee(uint256 dstChainId) external view returns (uint256) {
        return
            tokenBridgeRelayer.calculateRelayerFee(
                IProtocolMessagingHub(centralRegistry.protocolMessagingHub())
                    .wormholeChainId(dstChainId),
                address(this),
                18
            );
    }

    /// @notice Returns required amount of native asset for message fee.
    /// @return Required fee.
    function bridgeFee() external view returns (uint256) {
        return wormhole.messageFee();
    }

    /// PUBLIC FUNCTIONS ///

    /// @dev Returns the name of the token.
    function name() public pure override returns (string memory) {
        return "Curvance";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public pure override returns (string memory) {
        return "CVE";
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }
}
