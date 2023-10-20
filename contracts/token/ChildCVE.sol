// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/layerzero/OFTV2.sol";

contract CVE is OFTV2 {
    /// ERRORS ///

    error CVE__Unauthorized();

    /// CONSTRUCTOR ///

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 sharedDecimals_,
        address lzEndpoint_,
        ICentralRegistry centralRegistry_
    ) OFTV2(name_, symbol_, sharedDecimals_, lzEndpoint_, centralRegistry_) {}

    /// EXTERNAL FUNCTIONIS ///

    /// @notice Mints gauge emissions for the desired gauge pool
    /// @dev Allows the VotingHub to mint new gauge emissions.
    /// @param gaugePool The address of the gauge pool where emissions will be configured
    /// @param amount The amount of gauge emissions to be minted
    function mintGaugeEmissions(address gaugePool, uint256 amount) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            revert CVE__Unauthorized();
        }

        _mint(gaugePool, amount);
    }

    /// @notice Mints CVE to the calling gauge pool to fund the users lock boost
    /// @param amount The amount of tokens to be minted
    function mintLockBoost(uint256 amount) external {
        if (centralRegistry.isGaugeController(msg.sender)) {
            revert CVE__Unauthorized();
        }

        _mint(msg.sender, amount);
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
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
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
