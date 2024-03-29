// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBooster {
    function deposit(
        uint256 _poolId,
        uint256 _amount,
        bool _stake
    ) external;

    function withdraw(uint256 _poolId, uint256 _amount) external;
    
    function poolInfo(uint256 pid) external view returns (address, address, address, address, address, bool);

}
