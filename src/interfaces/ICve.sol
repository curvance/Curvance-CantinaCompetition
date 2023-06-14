// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICve {
    /// TODO Needs updating to our current functions

    /// @dev Get max token supply
    function maxSupply() external view returns (uint256);

    /**
     * @dev Used to mint tokens until `maxSupply` is reached, needs to be executed
     *       by addresses with the MINTER role
     * @param _to Address to send funds to
     * @param _amount Amount to send
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @dev Checks interfaces
     * @param interfaceId Interface ID to be checked for compatibility
     * @return true if `interfaceId` is compatible with contract, otherwise, false
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
