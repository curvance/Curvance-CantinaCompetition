// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

/// @notice Facilitates delegated actions on behalf of a user inside Curvance.
/// @dev `Delegable` allows Curvance to be a modular system that plugins can
///      be built on top of. By delegating authority to a secondary address 
///      users can utilize potential third-party features such as limit
///      orders, crosschain actions, reward auto compounding,
///      chained (multiple) actions, etc.
abstract contract Delegable {

    /// STORAGE ///

    /// @notice Curvance DAO Hub.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Status of whether a user or contract has the ability to act
    ///         on behalf of an account.
    /// @dev Account address => approval index => Spender address => Can act
    ///      on behalf of account.
    mapping(address => mapping(uint256 => mapping(address => bool)))
        public isDelegate;

    /// EVENTS ///

    event DelegateApproval(
        address indexed owner,
        address indexed delegate,
        uint256 approvalIndex,
        bool isApproved
    );

    /// ERRORS ///

    error Delegable__Unauthorized();
    error Delegable__InvalidCentralRegistry();
    error Delegable__DelegatingDisabled();

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert Delegable__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;
    }
    
    /// PUBLIC FUNCTIONS ///

    /// @notice Returns `user`'s approval index.
    /// @dev The approval index is a way to revoke approval on all tokens,
    ///      and features at once if a malicious delegation was allowed by
    ///      `user`.
    /// @param user The user to check delegated approval index for.
    /// @return `User`'s approval index.
    function getUserApprovalIndex(
        address user
    ) public view returns (uint256) {
        return centralRegistry.userApprovalIndex(user);
    }

    /// @notice Returns whether a user has delegation disabled.
    /// @dev This is not a silver bullet for phishing attacks, but, adds
    ///      an additional wall of defense.
    /// @param user The user to check delegation status for.
    /// @return Whether the user has new delegation disabled or not.
    function hasDelegatingDisabled(
        address user
    ) public view returns (bool) {
        return centralRegistry.delegatingDisabled(user);
    }

    /// @notice Approves or restricts `delegate`'s authority to operate
    ///         on the caller's behalf.
    /// @dev NOTE: Be careful who you approve here!
    ///      They can delay actions such as asset redemption through repeated
    ///      denial of service.
    ///      Emits a {DelegateApproval} event.
    /// @param delegate The address that will be approved or restricted
    ///                 from delegated actions on behalf of the caller.
    /// @param isApproved Whether `delegate` is being approved or restricted
    ///                   of authority to operate on behalf of caller.
    function setDelegateApproval(
        address delegate,
        bool isApproved
    ) external {
        if (hasDelegatingDisabled(msg.sender)) {
            revert Delegable__DelegatingDisabled();
        }

        uint256 approvalIndex = getUserApprovalIndex(msg.sender);
        isDelegate[msg.sender][approvalIndex][delegate] = isApproved;

        emit DelegateApproval(
            msg.sender, 
            delegate, 
            approvalIndex, 
            isApproved
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Status of whether a user or contract has the ability to act
    ///         on behalf of an account.
    /// @param user The address to check whether `delegate` has delegation
    ///             permissions.
    /// @param delegate The address that will be approved or restricted
    ///                 from delegated actions on behalf of the caller.
    /// @return Returns whether `delegate` is an approved delegate of `user`.
    function _checkIsDelegate(
        address user,
        address delegate
    ) public view returns (bool) {
        return isDelegate[user][getUserApprovalIndex(user)][delegate];
    }
    
}
