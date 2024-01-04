// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/ERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/wormhole/ITokenBridgeRelayer.sol";
import { IProtocolMessagingHub } from "contracts/interfaces/IProtocolMessagingHub.sol";

contract CVETestnet is ERC20 {
    /// CONSTANTS ///

    // Seconds in a month based on 365.2425 days.
    uint256 public constant MONTH = 2_629_746;

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Wormhole TokenBridgeRelayer.
    ITokenBridgeRelayer public tokenBridgeRelayer;

    /// @notice Address of Wormhole core contract.
    IWormhole public wormhole;

    // Timestamp when token was created
    uint256 public immutable tokenGenerationEventTimestamp;

    uint256 public immutable daoTreasuryAllocation; // 14.5%
    uint256 public immutable callOptionAllocation; // 3.75%
    uint256 public immutable teamAllocation; // 13.5%
    // 3% as veCVE immediately, 10.5% over 4 years
    uint256 public immutable teamAllocationPerMonth;

    /// `bytes4(keccak256(bytes("CVE__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x15f37077;

    /// STORAGE ///

    /// @notice Team operating address.
    address public teamAddress;

    /// @notice Number of DAO treasury tokens minted.
    uint256 public daoTreasuryMinted;

    /// @notice Number of Team allocation tokens minted.
    uint256 public teamAllocationMinted;

    /// @notice Number of Call Option reserved tokens minted.
    uint256 public callOptionsMinted;

    /// ERRORS ///

    error CVE__Unauthorized();
    error CVE__InsufficientCVEAllocation();
    error CVE__ParametersAreInvalid();
    error CVE__TokenBridgeRelayerIsZeroAddress();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address tokenBridgeRelayer_,
        address team_,
        uint256 daoTreasuryAllocation_,
        uint256 callOptionAllocation_,
        uint256 teamAllocation_,
        uint256 initialTokenMint_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CVE__ParametersAreInvalid();
        }

        if (team_ == address(0)) {
            team_ = msg.sender;
        }

        centralRegistry = centralRegistry_;
        if (tokenBridgeRelayer_ != address(0)) {
            tokenBridgeRelayer = ITokenBridgeRelayer(tokenBridgeRelayer_);
            wormhole = ITokenBridgeRelayer(tokenBridgeRelayer_).wormhole();
        }
        tokenGenerationEventTimestamp = block.timestamp;
        teamAddress = team_;
        daoTreasuryAllocation = daoTreasuryAllocation_;
        callOptionAllocation = callOptionAllocation_;
        teamAllocation = teamAllocation_;
        // Team Vesting is for 4 years and unlocked monthly.
        teamAllocationPerMonth = teamAllocation_ / 48;

        _mint(msg.sender, initialTokenMint_);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Set token bridge relayer.
    /// @param tokenBridgeRelayer_ wormbole token bridge relayer address.
    function setTokenBridgeRelayer(address tokenBridgeRelayer_) external {
        _checkElevatedPermissions();

        if (tokenBridgeRelayer_ == address(0)) {
            revert CVE__TokenBridgeRelayerIsZeroAddress();
        }

        tokenBridgeRelayer = ITokenBridgeRelayer(tokenBridgeRelayer_);
        wormhole = ITokenBridgeRelayer(tokenBridgeRelayer_).wormhole();
    }

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

    /// @notice Mint CVE for the DAO treasury.
    /// @param amount The amount of treasury tokens to be minted.
    ///               The number of tokens to mint cannot not exceed
    ///               the available treasury allocation.
    function mintTreasuryTokens(uint256 amount) external {
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
    function mintCallOptionTokens(uint256 amount) external {
        _checkDaoPermissions();

        uint256 _callOptionsMinted = callOptionsMinted;
        if (callOptionAllocation < _callOptionsMinted + amount) {
            revert CVE__InsufficientCVEAllocation();
        }

        callOptionsMinted = _callOptionsMinted + amount;
        _mint(msg.sender, amount);
    }

    /// @notice Mint CVE from team allocation.
    /// @dev Allows the DAO Manager to mint new tokens for the team allocation.
    /// @dev The amount of tokens minted is calculated based on the time passed
    ///      since the Token Generation Event.
    /// @dev The number of tokens minted is capped by the total team allocation.
    function mintTeamTokens() external {
        if (msg.sender != teamAddress) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 timeSinceTGE = block.timestamp - tokenGenerationEventTimestamp;
        uint256 monthsSinceTGE = timeSinceTGE / MONTH;
        uint256 _teamAllocationMinted = teamAllocationMinted;

        uint256 amount = (monthsSinceTGE * teamAllocationPerMonth) -
            _teamAllocationMinted;

        if (teamAllocation <= _teamAllocationMinted + amount) {
            amount = teamAllocation - teamAllocationMinted;
        }

        if (amount == 0) {
            revert CVE__ParametersAreInvalid();
        }

        teamAllocationMinted = _teamAllocationMinted + amount;
        _mint(msg.sender, amount);
    }

    /// @notice Set the team address
    /// @dev Allows the team to change the team's address.
    /// @param _address The new address for the team.
    function setTeamAddress(address _address) external {
        if (msg.sender != teamAddress) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        if (_address == address(0)) {
            revert CVE__ParametersAreInvalid();
        }

        teamAddress = _address;
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

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }
}
