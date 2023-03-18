// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.12;
import "../layerzero/OFT.sol";

error InvalidGas();

abstract contract cve is OFT {

    constructor(string memory _name, 
                string memory _symbol, 
                address _lzEndpoint, 
                ICentralRegistry _centralRegistry) OFT(_name, _symbol, _lzEndpoint, _centralRegistry) {
                    _mint(msg.sender, 420000069);
                }

    
    function sendFrom(address _from, uint16 _dstChainId, bytes calldata _toAddress, uint _amount, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) public payable override (OFTCore, IOFTCore){

        // Estimate the transaction fees
        (uint256 messageFee, ) = estimateSendFee(_dstChainId, _toAddress, _amount, false, _adapterParams);

        // Check if the provided gas is sufficient
        if(msg.value < messageFee) revert InvalidGas();

        super.sendFrom(_from, 
              _dstChainId, 
              _toAddress, 
              _amount, 
              _refundAddress, 
              _zroPaymentAddress, 
              _adapterParams);

    }

    function createAdapterParams(uint16 version, uint256 gasForTraverse) public pure returns (bytes memory) {
        return abi.encodePacked(version, gasForTraverse);
    }

}
