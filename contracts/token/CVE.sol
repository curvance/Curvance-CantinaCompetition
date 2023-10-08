// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../layerzero/OFTV2.sol";

contract CVE is OFTV2 {
    /// CONSTANTS ///

    uint256 public constant DENOMINATOR = 10000; // Scalar for math
    // Seconds in a month based on 365.2425 days
    uint256 public constant MONTH = 2_629_746;
    // Timestamp when token was created
    uint256 public immutable tokenGenerationEventTimestamp;

    uint256 public immutable daoTreasuryAllocation; // 14.5%
    uint256 public immutable callOptionAllocation; // 3.75%
    uint256 public immutable teamAllocation; // 13.5%
    // 3% as veCVE immediately, 10.5% over 4 years
    uint256 public immutable teamAllocationPerMonth;

    /// STORAGE ///

    address public teamAddress; // Team operating address
    // Number of DAO treasury tokens minted
    uint256 public daoTreasuryTokensMinted;
    // Number of Team allocation tokens minted
    uint256 public teamAllocationTokensMinted;
    // Number of Call Option reserved tokens minted
    uint256 public callOptionTokensMinted;

    /// ERRORS ///

    error CVE__Unauthorized();
    error CVE__InsufficientCVEAllocation();
    error CVE__ParametersareInvalid();

    /// CONSTRUCTOR ///

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 sharedDecimals_,
        address lzEndpoint_,
        ICentralRegistry centralRegistry_,
        address team_,
        uint256 daoTreasuryAllocation_,
        uint256 callOptionAllocation_,
        uint256 teamAllocation_,
        uint256 initialTokenMint_
    ) OFTV2(name_, symbol_, sharedDecimals_, lzEndpoint_, centralRegistry_) {
        tokenGenerationEventTimestamp = block.timestamp;

        if (team_ == address(0)) {
            team_ = msg.sender;
        }

        teamAddress = team_;
        daoTreasuryAllocation = daoTreasuryAllocation_;
        callOptionAllocation = callOptionAllocation_;
        teamAllocation = teamAllocation_;
        teamAllocationPerMonth = teamAllocation_ / 48; // Team Vesting is for 4 years and unlocked monthly

        _mint(msg.sender, initialTokenMint_);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Mints gauge emissions for the desired gauge pool
    /// @dev Allows the VotingHub to mint new gauge emissions.
    /// @param gaugePool The address of the gauge pool where emissions will be configured
    /// @param amount The amount of gauge emissions to be minted
    /// Emission amount is multiplied by the lock boost value from the central registry
    /// Resulting tokens are minted to the voting hub contract.
    function mintGaugeEmissions(address gaugePool, uint256 amount) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()){
            revert CVE__Unauthorized();
        }

        _mint(gaugePool, amount);
    }

    /// @notice Mints CVE to the calling gauge pool to fund the users lock boost
    /// @param tokensForLockBoost The amount of tokens to be minted
    function mintLockBoost(uint256 amount) external {
        if (centralRegistry.isGaugeController(msg.sender)){
            revert CVE__Unauthorized();
        }

        _mint(msg.sender, amount);
    }

    /// @notice Mint CVE for the DAO treasury
    /// @param amount The amount of treasury tokens to be minted.
    /// The number of tokens to mint cannot not exceed the available treasury allocation.
    function mintTreasuryTokens(
        uint256 amount
    ) external onlyElevatedPermissions {
        uint256 _daoTreasuryTokensMinted = daoTreasuryTokensMinted;
        if (daoTreasuryAllocation < _daoTreasuryTokensMinted + amount){
            revert CVE__InsufficientCVEAllocation();
        }

        daoTreasuryTokensMinted = _daoTreasuryTokensMinted + amount;
        _mint(msg.sender, amount);
    }

    /// @notice Mint CVE for deposit into callOptionCVE contract
    /// @param amount The amount of call option tokens to be minted.
    /// The number of tokens to mint cannot not exceed the available call option allocation.
    function mintCallOptionTokens(
        uint256 amount
    ) external onlyDaoPermissions {
        uint256 _callOptionTokensMinted = callOptionTokensMinted;
        if (callOptionAllocation < _callOptionTokensMinted + amount){
            revert CVE__InsufficientCVEAllocation();
        }

        callOptionTokensMinted = _callOptionTokensMinted + amount;
        _mint(msg.sender, amount);
    }

    /// @notice Mint CVE from team allocation
    /// @dev Allows the DAO Manager to mint new tokens for the team allocation.
    /// @dev The amount of tokens minted is calculated based on the time passed since the Token Generation Event.
    /// @dev The number of tokens minted is capped by the total team allocation.
    function mintTeamTokens() external {
        if (msg.sender != teamAddress){
            revert CVE__Unauthorized();
        }

        uint256 timeSinceTGE = block.timestamp - tokenGenerationEventTimestamp;
        uint256 monthsSinceTGE = timeSinceTGE / MONTH;
        uint256 _teamAllocationTokensMinted = teamAllocationTokensMinted;

        uint256 amount = (monthsSinceTGE * teamAllocationPerMonth) -
            _teamAllocationTokensMinted;

        if (teamAllocation <= _teamAllocationTokensMinted + amount) {
            amount = teamAllocation - teamAllocationTokensMinted;
        }
        
        if (amount == 0){
            revert CVE__ParametersareInvalid();
        }

        teamAllocationTokensMinted =
            _teamAllocationTokensMinted +
            amount;
        _mint(msg.sender, amount);
    }

    /// @notice Set the team address
    /// @dev Allows the team to change the team's address.
    /// @param _address The new address for the team.
    function setTeamAddress(address _address) external {
        if (msg.sender != teamAddress){
            revert CVE__Unauthorized();
        }

        if (_address == address(0)){
            revert CVE__ParametersareInvalid();
        }

        teamAddress = _address;
    }

    /// PUBLIC FUNCTIONS ///

    function sendAndCall(
        address from,
        uint16 dstChainId,
        bytes32 toAddress,
        uint256 amount,
        bytes calldata payload,
        uint64 dstGasForCall,
        LzCallParams calldata callParams
    ) public payable override {
        if (msg.sender != centralRegistry.protocolMessagingHub()){
            revert CVE__Unauthorized();
        }

        super.sendAndCall(
            from,
            dstChainId,
            toAddress,
            amount,
            payload,
            dstGasForCall,
            callParams
        );
    }
}
