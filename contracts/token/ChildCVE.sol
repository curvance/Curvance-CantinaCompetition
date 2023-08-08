// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/layerzero/OFTV2.sol";

contract CVE is OFTV2 {
    
    /// CONSTANTS ///

    uint256 public constant DENOMINATOR = 10000; // Scalar for math

    /// CONSTRUCTOR ///

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 sharedDecimals_,
        address lzEndpoint_,
        ICentralRegistry centralRegistry_
    ) OFTV2(name_, symbol_, sharedDecimals_, lzEndpoint_, centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Mint new gauge emissions
    /// @dev Allows the VotingHub to mint new gauge emissions.
    /// @param gaugeEmissions The amount of gauge emissions to be minted
    /// @param gaugePool The address of the gauge pool where emissions will be configured
    /// Emission amount is multiplied by the lock boost value from the central registry
    /// Resulting tokens are minted to the voting hub contract.
    function mintGaugeEmissions(
        uint256 gaugeEmissions,
        address gaugePool
    ) external {
        require(
            msg.sender == centralRegistry.protocolMessagingHub(),
            "CVE: UNAUTHORIZED"
        );
        _mint(
            gaugePool,
            (gaugeEmissions * centralRegistry.lockBoostValue()) / DENOMINATOR
        );
    }

    /// PUBLIC FUNCTIONS ///

    function sendAndCall(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint256 _amount,
        bytes calldata _payload,
        uint64 _dstGasForCall,
        LzCallParams calldata _callParams
    ) public payable override onlyMessagingHub {
        super.sendAndCall(
            _from,
            _dstChainId,
            _toAddress,
            _amount,
            _payload,
            _dstGasForCall,
            _callParams
        );
    }
}
