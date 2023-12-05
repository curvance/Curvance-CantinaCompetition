// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/libraries/ERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

contract CVE is ERC20 {
    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// ERRORS ///

    error CVE__Unauthorized();

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "lzApp: invalid central registry"
        );

        centralRegistry = centralRegistry_;
    }

    /// EXTERNAL FUNCTIONIS ///

    /// @notice Mints gauge emissions for the desired gauge pool
    /// @dev Allows the VotingHub to mint new gauge emissions.
    /// @param gaugePool The address of the gauge pool where emissions will be
    ///                  configured.
    /// @param amount The amount of gauge emissions to be minted
    function mintGaugeEmissions(address gaugePool, uint256 amount) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            revert CVE__Unauthorized();
        }

        _mint(gaugePool, amount);
    }

    /// @notice Mints CVE to the calling gauge pool to fund the users
    ///         lock boost.
    /// @param amount The amount of tokens to be minted
    function mintLockBoost(uint256 amount) external {
        if (!centralRegistry.isGaugeController(msg.sender)) {
            revert CVE__Unauthorized();
        }

        _mint(msg.sender, amount);
    }

    /// PUBLIC FUNCTIONS ///

    /// @dev Returns the name of the token.
    function name() public pure override returns (string memory) {
        return "Child Curvance";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public pure override returns (string memory) {
        return "ChildCVE";
    }
}
