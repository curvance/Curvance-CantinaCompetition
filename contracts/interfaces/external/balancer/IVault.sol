// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/// @dev This is an empty interface used to represent either ERC20-conforming token contracts or ETH (using the zero
/// address sentinel value). We're just relying on the fact that `interface` can be used to declare new address-like
/// types.
///
/// This concept is unrelated to a Pool's Asset Managers.
interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

interface IVault {
    /// @dev Performs a set of user balance operations, which involve Internal Balance (deposit, withdraw or transfer)
    /// and plain ERC20 transfers using the Vault's allowance. This last feature is particularly useful for relayers, as
    /// it lets integrators reuse a user's Vault allowance.
    ///
    /// For each operation, if the caller is not `sender`, it must be an authorized relayer for them.
    function manageUserBalance(UserBalanceOp[] memory ops) external payable;

    /// @dev Data for `manageUserBalance` operations, which include the possibility for ETH to be sent and received
    /// without manual WETH wrapping or unwrapping.

    struct UserBalanceOp {
        UserBalanceOpKind kind;
        IAsset asset;
        uint256 amount;
        address sender;
        address payable recipient;
    }

    // There are four possible operations in `manageUserBalance`:
    //
    // - DEPOSIT_INTERNAL
    // Increases the Internal Balance of the `recipient` account by transferring tokens from the corresponding
    // `sender`. The sender must have allowed the Vault to use their tokens via `IERC20.approve()`.
    //
    // ETH can be used by passing the ETH sentinel value as the asset and forwarding ETH in the call: it will be wrapped
    // and deposited as WETH. Any ETH amount remaining will be sent back to the caller (not the sender, which is
    // relevant for relayers).
    //
    // Emits an `InternalBalanceChanged` event.
    //
    //
    // - WITHDRAW_INTERNAL
    // Decreases the Internal Balance of the `sender` account by transferring tokens to the `recipient`.
    //
    // ETH can be used by passing the ETH sentinel value as the asset. This will deduct WETH instead, unwrap it and send
    // it to the recipient as ETH.
    //
    // Emits an `InternalBalanceChanged` event.
    //
    //
    // - TRANSFER_INTERNAL
    // Transfers tokens from the Internal Balance of the `sender` account to the Internal Balance of `recipient`.
    //
    // Reverts if the ETH sentinel value is passed.
    //
    // Emits an `InternalBalanceChanged` event.
    //
    //
    // - TRANSFER_EXTERNAL
    // Transfers tokens from `sender` to `recipient`, using the Vault's ERC20 allowance. This is typically used by
    // relayers, as it lets them reuse a user's Vault allowance.
    //
    // Reverts if the ETH sentinel value is passed.
    //
    // Emits an `ExternalBalanceTransfer` event.

    enum UserBalanceOpKind {
        DEPOSIT_INTERNAL,
        WITHDRAW_INTERNAL,
        TRANSFER_INTERNAL,
        TRANSFER_EXTERNAL
    }
}
