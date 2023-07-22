// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../layerzero/OFTV2.sol";

contract CVE is OFTV2 {

    uint256 public immutable TokenGenerationEventTimestamp;
    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant month = 2_629_746;
    address public teamAddress;

    uint256 public immutable DAOTreasuryAllocation;
    uint256 public immutable callOptionAllocation;
    uint256 public immutable TeamAllocation;
    uint256 public immutable TeamAllocationPerMonth;

    uint256 public DAOTreasuryTokensMinted;
    uint256 public TeamAllocationTokensMinted;
    uint256 public callOptionTokensMinted;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 sharedDecimals_,
        address lzEndpoint_,
        ICentralRegistry centralRegistry_,
        address team_,
        uint256 DAOTreasuryAllocation_,
        uint256 callOptionAllocation_,
        uint256 TeamAllocation_,
        uint256 initialTokenMint_
    ) OFTV2(name_, symbol_, sharedDecimals_, lzEndpoint_, centralRegistry_) {
        TokenGenerationEventTimestamp = block.timestamp;

        if (team_ == address(0)) {
            team_ = msg.sender;
        }

        teamAddress = team_;
        DAOTreasuryAllocation = DAOTreasuryAllocation_;
        callOptionAllocation = callOptionAllocation_;
        TeamAllocation = TeamAllocation_;
        TeamAllocationPerMonth = TeamAllocation_ / (48 * month); // Team Vesting is for 4 years and unlocked monthly

        _mint(msg.sender, initialTokenMint_);

        // TODO:
        // Permission sendAndCall?
        // Write sendEmissions in votingHub
    }

    modifier onlyProtocolMessagingHub() {
        require(
            msg.sender == centralRegistry.protocolMessagingHub(),
            "CVE: UNAUTHORIZED"
        );

        _;
    }

    modifier onlyTeam() {
        require(msg.sender == teamAddress, "CVE: UNAUTHORIZED");

        _;
    }

    /// @notice Mint new gauge emissions
    /// @dev Allows the VotingHub to mint new gauge emissions.
    /// @param _gaugeEmissions The amount of gauge emissions to be minted.
    /// Emission amount is multiplied by the lock boost value from the central registry.
    /// Resulting tokens are minted to the voting hub contract.
    function mintGaugeEmissions(
        uint256 _gaugeEmissions
    ) external onlyProtocolMessagingHub {
        _mint(
            msg.sender,
            (_gaugeEmissions * centralRegistry.lockBoostValue()) / DENOMINATOR
        );
    }

    /// @notice Mint CVE for the DAO treasury
    /// @param _tokensToMint The amount of treasury tokens to be minted.
    /// The number of tokens to mint cannot not exceed the available treasury allocation.
    function mintTreasuryTokens(
        uint256 _tokensToMint
    ) external onlyElevatedPermissions {
        require(
            DAOTreasuryAllocation >= DAOTreasuryTokensMinted + _tokensToMint,
            "CVE: insufficient token allocation"
        );

        DAOTreasuryTokensMinted += _tokensToMint;
        _mint(msg.sender, _tokensToMint);
    }

    /// @notice Mint CVE for deposit into callOptionCVE contract
    /// @param _tokensToMint The amount of call option tokens to be minted.
    /// The number of tokens to mint cannot not exceed the available call option allocation.
    function mintCallOptionTokens(
        uint256 _tokensToMint
    ) external onlyDaoPermissions {
        require(
            callOptionAllocation >= callOptionTokensMinted + _tokensToMint,
            "CVE: insufficient token allocation"
        );

        callOptionTokensMinted += _tokensToMint;
        _mint(msg.sender, _tokensToMint);
    }

    /// @notice Mint CVE from team allocation
    /// @dev Allows the DAO Manager to mint new tokens for the team allocation.
    /// @dev The amount of tokens minted is calculated based on the time passed since the Token Generation Event.
    /// @dev The number of tokens minted is capped by the total team allocation.
    function mintTeamTokens() external onlyTeam {
        uint256 timeSinceTGE = block.timestamp - TokenGenerationEventTimestamp;
        uint256 monthsSinceTGE = timeSinceTGE / month;

        uint256 _tokensToMint = (monthsSinceTGE * TeamAllocationPerMonth) -
            TeamAllocationTokensMinted;

        if (TeamAllocation <= TeamAllocationTokensMinted + _tokensToMint) {
            _tokensToMint = TeamAllocation - TeamAllocationTokensMinted;
        }

        require(_tokensToMint != 0, "CVE:  no tokens to mint");

        TeamAllocationTokensMinted += _tokensToMint;
        _mint(msg.sender, _tokensToMint);
    }

    /// @notice Set the team address
    /// @dev Allows the team to change the team's address.
    /// @param _address The new address for the team.
    function setTeamAddress(address _address) external onlyTeam {
        require(_address != address(0), "CVE: invalid parameter");
        teamAddress = _address;
    }
}
