// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.12;
import "../layerzero/OFTV2.sol";

error InvalidGas();

contract CVE is OFTV2 {

    uint256 public immutable TokenGenerationEventTimestamp;

    constructor(string memory _name, 
                string memory _symbol,
                uint8 _sharedDecimals, 
                address _lzEndpoint, 
                ICentralRegistry _centralRegistry) OFTV2(_name, _symbol, _sharedDecimals, _lzEndpoint, _centralRegistry) {
                    TokenGenerationEventTimestamp = block.timestamp;
                    //TODO: 
                    // Add minting and token vesting functions
                    // Configure up nonblockingmessages 
                    
                    //_mint(msg.sender, 420000069 ether);
                }


}
