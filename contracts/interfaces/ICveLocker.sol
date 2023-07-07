// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICveLocker {
    // @notice Increments veCVE lock token points data from a fresh continuous lock
    function incrementTokenPoints(address _user, uint256 _points) external;
    // @notice Updates veCVE lock token data from a lock moved to continuous mode
    function updateTokenDataFromContinuousOn(address _user, uint256 _epoch, uint256 _tokenPoints, uint256 _tokenUnlocks) external;
    // @notice Reduces veCVE lock token data from a continuous lock turning off continuous mode
    function reduceTokenData(address _user, uint256 _epoch, uint256 _tokenPoints, uint256 _tokenUnlocks) external;
    // @notice Updates veCVE unlock data from an extended lock remaining non-continuous
    function updateTokenDataFromExtendedLock(address _user, uint256 _previousEpoch, uint256 _epoch, uint256 _points) external;
    // @notice Increments veCVE lock token data from a fresh non-continuous lock
    function incrementTokenData(address _user, uint256 _epoch, uint256 _points) external;

}
