// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITimelock {
    /// @notice Permissionlessly update DAO address if it has been changed
    ///         through the Curvance Central Registry.
    function updateDaoAddress() external;
}
