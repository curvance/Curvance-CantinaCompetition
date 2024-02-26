// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { FeeTokenBridgingHub } from "contracts/architecture/FeeTokenBridgingHub.sol";

import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IGelatoOneBalance } from "contracts/interfaces/IGelatoOneBalance.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract OneBalanceFeeManager is FeeTokenBridgingHub {
    /// CONSTANTS ///

    /// @notice GETH Chain ID for Polygon.
    uint256 internal constant _POLYGON_CHAIN_ID = 137;

    /// STORAGE ///

    /// @notice Address of Gelato 1Balance on Polygon.
    IGelatoOneBalance public gelatoOneBalance;

    /// @notice Address of OneBalanceFeeManager on Polygon.
    address public polygonOneBalanceFeeManager;

    /// @notice Status of message hash whether it's delivered or not.
    mapping(bytes32 => bool) public isDeliveredMessageHash;

    /// ERRORS ///

    error OneBalanceFeeManager__Unauthorized();
    error OneBalanceFeeManager__InvalidGelatoOneBalance();
    error OneBalanceFeeManager__InvalidPolygonOneBalanceFeeManager();
    error OneBalanceFeeManager__MessageHashIsAlreadyDelivered(
        bytes32 messageHash
    );

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address gelatoOneBalance_,
        address polygonOneBalanceFeeManager_
    ) FeeTokenBridgingHub(centralRegistry_) {
        if (block.chainid == _POLYGON_CHAIN_ID) {
            if (gelatoOneBalance_ == address(0)) {
                revert OneBalanceFeeManager__InvalidGelatoOneBalance();
            }

            // We infinite approve `feeToken` so that Gelato 1Balance
            // can pull funds to proper chain.
            SafeTransferLib.safeApprove(
                feeToken,
                gelatoOneBalance_,
                type(uint256).max
            );
        } else if (polygonOneBalanceFeeManager_ == address(0)) {
            revert OneBalanceFeeManager__InvalidPolygonOneBalanceFeeManager();
        }

        gelatoOneBalance = IGelatoOneBalance(gelatoOneBalance_);
        polygonOneBalanceFeeManager = polygonOneBalanceFeeManager_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Deposit fee token to Gelato 1Balance.
    /// @dev If current chain is Polygon, it deposits
    ///      Otherwise, it bridges fee token to Polygon to deposit.
    function depositOneBalanceFee() external nonReentrant {
        _checkDaoPermissions();

        if (block.chainid == _POLYGON_CHAIN_ID) {
            _depositOneBalanceFee();
        } else {
            _sendFeeToken(
                _POLYGON_CHAIN_ID,
                polygonOneBalanceFeeManager,
                IERC20(feeToken).balanceOf(address(this))
            );
        }
    }

    /// @notice Used when fees are received from other chains.
    ///         When a `send` is performed with this contract as the target,
    ///         this function will be invoked by the WormholeRelayer contract.
    /// NOTE: This function should be restricted such that only
    ///       the Wormhole Relayer contract can call it.
    /// @param payload An arbitrary message which was included in the delivery
    ///                by the requester. This message's signature will already
    ///                have been verified (as long as msg.sender is
    ///                the Wormhole Relayer contract)
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory /* additionalMessages */,
        bytes32 /* srcAddress */,
        uint16 /* srcChainId */,
        bytes32 deliveryHash
    ) external payable {
        if (block.chainid != _POLYGON_CHAIN_ID) {
            return;
        }

        if (isDeliveredMessageHash[deliveryHash]) {
            revert OneBalanceFeeManager__MessageHashIsAlreadyDelivered(
                deliveryHash
            );
        }

        isDeliveredMessageHash[deliveryHash] = true;

        address wormholeRelayer = address(centralRegistry.wormholeRelayer());

        if (msg.sender != wormholeRelayer) {
            revert OneBalanceFeeManager__Unauthorized();
        }

        uint8 payloadId = abi.decode(payload, (uint8));

        if (payloadId == 1) {
            (, bytes32 token) = abi.decode(payload, (uint8, bytes32));

            if (address(uint160(uint256(token))) == feeToken) {
                _depositOneBalanceFee();
            }
        }
    }

    /// @notice Set Gelato Network 1Balance destination address.
    /// @param newGelatoOneBalance The address of the new gelato one balance
    ///                            account.
    function setOneBalanceAddress(address newGelatoOneBalance) external {
        if (block.chainid != _POLYGON_CHAIN_ID) {
            return;
        }

        _checkDaoPermissions();

        // Revoke previous approval.
        SafeTransferLib.safeApprove(feeToken, address(gelatoOneBalance), 0);

        gelatoOneBalance = IGelatoOneBalance(newGelatoOneBalance);

        // We infinite approve fee token so that gelato 1Balance
        // can drag funds to proper chain.
        SafeTransferLib.safeApprove(
            feeToken,
            newGelatoOneBalance,
            type(uint256).max
        );
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Deposit fee token to Gelato 1Balance.
    /// @dev Only callable on Polygon PoS chain.
    function _depositOneBalanceFee() internal {
        // Transfer fees to Gelato Network 1Balance or equivalent
        gelatoOneBalance.depositToken(
            centralRegistry.gelatoSponsor(),
            IERC20(feeToken),
            IERC20(feeToken).balanceOf(address(this))
        );
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert OneBalanceFeeManager__Unauthorized();
        }
    }
}
