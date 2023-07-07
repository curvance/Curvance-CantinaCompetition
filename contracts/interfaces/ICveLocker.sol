// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICveLocker {
    // @notice Increments veCVE lock token points data
    function incrementTokenPoints(address _user, uint256 _points) external;
    // @notice Reduces veCVE lock token points data 
    function reduceTokenPoints(address _user, uint256 _points) external;
    // @notice Updates veCVE lock token data
    function updateTokenDataFromContinuousOn(address _user, uint256 _epoch, uint256 _tokenPoints, uint256 _tokenUnlocks) external;
    // @notice Updates veCVE unlock data from an extended lock remaining non-continuous
    function updateTokenUnlockDataFromExtendedLock(address _user, uint256 _previousEpoch, uint256 _epoch, uint256 _previousPoints, uint256 _points) external;
    // @notice Increments veCVE lock token data from a fresh non-continuous lock
    function incrementTokenData(address _user, uint256 _epoch, uint256 _points) external;
    // @notice Reduces veCVE lock token data from a continuous lock turning off continuous mode
    function reduceTokenData(address _user, uint256 _epoch, uint256 _tokenPoints, uint256 _tokenUnlocks) external;
    // @notice Increments veCVE lock token unlock data
    function incrementTokenUnlocks(address _user, uint256 _epoch, uint256 _points) external;
    // @notice Reduces veCVE lock token unlock data
    function reduceTokenUnlocks(address _user, uint256 _epoch, uint256 _points) external;

}
