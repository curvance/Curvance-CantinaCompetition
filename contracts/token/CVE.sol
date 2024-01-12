// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/external/ERC20.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/wormhole/ITokenBridgeRelayer.sol";
import { IProtocolMessagingHub } from "contracts/interfaces/IProtocolMessagingHub.sol";

/// @notice Curvance DAO's Canonical CVE Contract.
contract CVE is ERC20 {
    /// CONSTANTS ///

    /// @notice Seconds in a month based on 365.2425 days.
    uint256 public constant MONTH = 2_629_746;

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Wormhole TokenBridgeRelayer.
    ITokenBridgeRelayer public immutable tokenBridgeRelayer;
    /// @notice Address of Wormhole core contract.
    IWormhole public immutable wormhole;
    /// @notice Timestamp when token was created
    uint256 public immutable tokenGenerationEventTimestamp;
    /// @notice DAO treasury allocation of CVE, 
    ///         can be minted as needed by the DAO. 14.5%.
    uint256 public immutable daoTreasuryAllocation;
    /// @notice Initial community allocation of CVE, 
    ///         can be minted as needed by the DAO. 3.75%.
    uint256 public immutable initialCommunityAllocation;
    /// @notice Buildier allocation of CVE, 
    ///         can be minted on a monthly basis. 13.5%
    uint256 public immutable builderAllocation;
    /// @notice 3% as veCVE immediately, 10.5% vested over 4 years.
    uint256 public immutable builderAllocationPerMonth;

    /// @dev `bytes4(keccak256(bytes("CVE__Unauthorized()")))`.
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x15f37077;

    /// STORAGE ///

    /// @notice Builder operating address.
    address public builderAddress;
    /// @notice Number of DAO treasury tokens minted.
    uint256 public daoTreasuryMinted;
    /// @notice Number of Builder allocation tokens minted.
    uint256 public builderAllocationMinted;
    /// @notice Number of Call Option reserved tokens minted.
    uint256 public initialCommunityMinted;

    /// ERRORS ///

    error CVE__Unauthorized();
    error CVE__InsufficientCVEAllocation();
    error CVE__ParametersAreInvalid();
    error CVE__TokenBridgeRelayerIsZeroAddress();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address tokenBridgeRelayer_,
        address builder_
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

        if (builder_ == address(0)) {
            builder_ = msg.sender;
        }

        centralRegistry = centralRegistry_;
        tokenBridgeRelayer = ITokenBridgeRelayer(tokenBridgeRelayer_);
        wormhole = ITokenBridgeRelayer(tokenBridgeRelayer_).wormhole();
        tokenGenerationEventTimestamp = block.timestamp;
        builderAddress = builder_;

        // All allocations and mints are in 18 decimal form to match CVE.

        // 60,900,010 tokens minted as needed by the DAO.
        daoTreasuryAllocation = 60900010e18;
        // 15,750,002.59 tokens (3.75%) minted on conclusion of LBP.
        initialCommunityAllocation = 1575000259e16;
        // 44,100,007.245 tokens (10.5%) vested over 4 years.
        builderAllocation = 44100007245e15;
        // Builder Vesting is for 4 years and unlocked monthly.
        builderAllocationPerMonth = builderAllocation / 48;

        // 50,400,008.285 (12%) minted initially for:
        // 29,400,004.83 (7%) from Capital Raises.
        // 12,600,002.075 (3%) builder veCVE initial allocation.
        // 8,400,001.38 (2%) LBP allocation.
        uint256 initialTokenMint = 50400008285e15;

        _mint(msg.sender, initialTokenMint);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Mints gauge emissions for the desired gauge pool.
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
    /// @param amount The amount of tokens to be minted.
    function mintLockBoost(uint256 amount) external {
        if (!centralRegistry.isGaugeController(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _mint(msg.sender, amount);
    }

    /// @notice Mint CVE to msg.sender, 
    ///         which will always be the VeCVE contract.
    /// @dev Only callable by the ProtocolMessagingHub.
    ///      This function is used only for creating a bridged VeCVE lock.
    /// @param amount The amount of token to mint for the new veCVE lock.
    function mintVeCVELock(uint256 amount) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _mint(msg.sender, amount);
    }

    /// @notice Burn CVE from msg.sender, 
    ///         which will always be the VeCVE contract.
    /// @dev Only callable by VeCVE.
    ///      This function is used only for bridging VeCVE lock.
    /// @param amount The amount of token to burn for a bridging veCVE lock.
    function burnVeCVELock(uint256 amount) external {
        if (msg.sender != centralRegistry.veCVE()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        _burn(msg.sender, amount);
    }

    /// @notice Mint CVE for the DAO treasury.
    /// @param amount The amount of treasury tokens to be minted.
    ///               The number of tokens to mint cannot not exceed
    ///               the available treasury allocation.
    function mintTreasury(uint256 amount) external {
        _checkElevatedPermissions();

        uint256 _daoTreasuryMinted = daoTreasuryMinted;
        if (daoTreasuryAllocation < _daoTreasuryMinted + amount) {
            revert CVE__InsufficientCVEAllocation();
        }

        daoTreasuryMinted = _daoTreasuryMinted + amount;
        _mint(msg.sender, amount);
    }

    /// @notice Mint CVE for deposit into callOptionCVE contract.
    /// @param amount The amount of call option tokens to be minted.
    ///               The number of tokens to mint cannot not exceed
    ///               the available call option allocation.
    function mintCommunityAllocation(uint256 amount) external {
        _checkDaoPermissions();

        uint256 _initialCommunityMinted = initialCommunityMinted;
        if (initialCommunityAllocation < _initialCommunityMinted + amount) {
            revert CVE__InsufficientCVEAllocation();
        }

        initialCommunityMinted = _initialCommunityMinted + amount;
        _mint(msg.sender, amount);
    }

    /// @notice Mint CVE from builder allocation.
    /// @dev Allows the DAO Manager to mint new tokens for the builder
    ///      allocation.
    /// @dev The amount of tokens minted is calculated based on the time passed
    ///      since the Token Generation Event.
    /// @dev The number of tokens minted is capped by the total builder allocation.
    function mintBuilder() external {
        if (msg.sender != builderAddress) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 timeSinceTGE = block.timestamp - tokenGenerationEventTimestamp;
        uint256 monthsSinceTGE = timeSinceTGE / MONTH;
        uint256 _builderAllocationMinted = builderAllocationMinted;

        uint256 amount = (monthsSinceTGE * builderAllocationPerMonth) -
            _builderAllocationMinted;

        if (builderAllocation <= _builderAllocationMinted + amount) {
            amount = builderAllocation - builderAllocationMinted;
        }

        if (amount == 0) {
            revert CVE__ParametersAreInvalid();
        }

        builderAllocationMinted = _builderAllocationMinted + amount;
        _mint(msg.sender, amount);
    }

    /// @notice Sets the builder address.
    /// @dev Allows the builders to change the builder's address.
    /// @param newAddress The new address for the builder.
    function setBuilderAddress(address newAddress) external {
        if (msg.sender != builderAddress) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        if (newAddress == address(0)) {
            revert CVE__ParametersAreInvalid();
        }

        builderAddress = newAddress;
    }

    /// @notice Send wormhole message to bridge CVE.
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

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }
}
