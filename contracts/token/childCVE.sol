// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../layerzero/OFTV2.sol";

contract CVE is OFTV2 {
    uint256 public constant DENOMINATOR = 10000;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _sharedDecimals,
        address _lzEndpoint,
        ICentralRegistry _centralRegistry
    ) OFTV2(_name, _symbol, _sharedDecimals, _lzEndpoint, _centralRegistry) {
        // TODO:
        // Permission sendAndCall?
        // Write sendEmissions in votingHub
        // Write moving cve gauge emissions to new hub chain
        // Write updating hub chain for emission purposes
    }

    modifier onlyVotingHub() {
        require(
            msg.sender == centralRegistry.votingHub(),
            "CVE: UNAUTHORIZED"
        );

        _;
    }

    /// @notice Mint new gauge emissions
    /// @dev Allows the VotingHub to mint new gauge emissions.
    /// @param _gaugeEmissions The amount of gauge emissions to be minted.
    /// Emission amount is multiplied by the lock boost value from the central registry.
    /// Resulting tokens are minted to the voting hub contract.
    function mintGaugeEmissions(
        uint256 _gaugeEmissions
    ) external onlyVotingHub {
        _mint(
            msg.sender,
            (_gaugeEmissions * centralRegistry.lockBoostValue()) / DENOMINATOR
        );
    }
}
