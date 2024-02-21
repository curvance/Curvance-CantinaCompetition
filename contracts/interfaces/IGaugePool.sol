// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGaugePool {
    /// @notice Sets emission rates of tokens of next epoch.
    /// @dev Only the protocol messaging hub can call this.
    /// @param epoch The epoch to set emission rates for, should be the next epoch.
    /// @param tokens Array containing all tokens to set emission rates for.
    /// @param poolWeights Gauge/Pool weights corresponding to DAO
    ///                    voted emission rates.
    function setEmissionRates(
        uint256 epoch,
        address[] memory tokens,
        uint256[] memory poolWeights
    ) external;

    /// @notice Deposit into gauge pool.
    /// @param token Pool token address.
    /// @param user User address.
    /// @param amount Amounts to deposit.
    function deposit(
        address token,
        address user,
        uint256 amount
    ) external;

    /// @notice Registers a withdrawal of `token` deposits by `user`
    ///         from the gauge pool.
    /// @dev This does not actually include any token transfers as tokens
    ///      are permissionlessly escrowed by CToken/DToken contracts and
    ///      we simply record deposits/withdraws here.
    /// @param token Pool token address.
    /// @param user The user address.
    /// @param amount Amounts to withdraw.
    function withdraw(
        address token,
        address user,
        uint256 amount
    ) external;
}
