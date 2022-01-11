// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IBasicRewards {
    function getReward(address _account, bool _claimExtras) external;

    function getReward(address _account) external;

    function getReward(address _account, address _token) external;

    function stakeFor(address, uint256) external;
}

interface ICvxRewards {
    function getReward(
        address _account,
        bool _claimExtras,
        bool _stake
    ) external;
}

interface IChefRewards {
    function claim(uint256 _pid, address _account) external;
}

interface ICvxCrvDeposit {
    function deposit(uint256, bool) external;
}

interface ISwapExchange {
    function exchange(
        int128,
        int128,
        uint256,
        uint256
    ) external returns (uint256);
}
