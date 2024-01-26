pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract FuzzMarketManagerRBAC is StatefulBaseMarket {
    /// @custom:property ac-market-1 Calling setMintPaused with correct preconditions should not revert.
    /// @custom:property ac-market-2 Calling the setMintPaused(mtoken, true) with authorization should set isMintPaused to 2.
    /// @custom:property ac-market-3 Calling the setMintPaused(mtoken, false) with authorization should set isMintPaused to 1.
    /// @custom:precondition address(this) is authorized
    /// @custom:precondition mtoken is listed
    function setMintPaused_should_succeed_when_authorized_and_listed(
        address mtoken,
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(marketManager.isListed(mtoken));

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature(
                "setMintPaused(address,bool)",
                mtoken,
                state
            )
        );
        if (success) {
            uint256 isMintPaused = marketManager.mintPaused(mtoken);
            if (state) {
                // ac-market-2
                assertWithMsg(
                    isMintPaused == 2,
                    "LENDTROLLER - setMintPaused() true succeed set isMintPaused = 2"
                );
            } else {
                // ac-market-3
                assertWithMsg(
                    isMintPaused == 1,
                    "LENDTROLLER - setMintPaused() false should set mintPaused[mtoken] to 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            // ac-market-1
            assertWithMsg(
                false,
                "LENDTROLLER - setMintPaused() expected to be successful with correct preconditions"
            );
        }
    }

    /// @custom:property ac-market-4 Calling setRedeemPaused with the correct preconditions should succeed.
    /// @custom:property ac-market-5 Calling setRedeemPaused(true) with authorization should set redeemPaused to 2.
    /// @custom:property ac-market-6 Calling setRedeemPaused(false) with authorization should set redeemPaused to 1.
    /// @custom:property setRedeemPause(false) should set redeemPaused = 1
    /// @custom:precondition address(this) has dao permissions
    function setRedeemPaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature("setRedeemPaused(bool)", state)
        );
        if (success) {
            uint256 redeemPaused = marketManager.redeemPaused();
            if (state == true) {
                // ac-market-5
                assertEq(
                    redeemPaused,
                    2,
                    "LENDTROLLER - setRedeemPaused() true expected to set redeemPaused = 2 "
                );
            } else {
                // ac-market-6
                assertEq(
                    redeemPaused,
                    1,
                    "LENDTROLLER - setRedeemPaused false expected to set redeemPaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);
            // ac-market-1
            assertWithMsg(
                errorSelector == marketManager_unauthorizedSelectorHash,
                "LENDTROLLER - setRedeemPaused() expected to be successful with correct preconditions"
            );
        }
    }

    /// @custom:property ac-market-7 Calling setTransferPaused with the correct preconditions  should not revert.
    /// @custom:propery ac-market-8 Calling setTransferPaused(true) with authorization should set transferPaused to 2.
    /// @custom:property ac-market-9 Calling setTransferPaused(false) with authorization should set transferPaused to 1.
    /// @custom:precondition address(this) has dao permissions
    function setTransferPaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature("setTransferPaused(bool)", state)
        );
        if (success) {
            uint256 transferPaused = marketManager.transferPaused();
            if (state == true) {
                assertEq(
                    transferPaused,
                    2,
                    "LENDTROLLER - setTransferPaused() true expected to set TransferPaused = 2 "
                );
            } else {
                assertEq(
                    transferPaused,
                    1,
                    "LENDTROLLER - setTransferPaused false expected to set TransferPaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "LENDTROLLER - setTransferPaused() expected to be successful with correct preconditions"
            );
        }
    }

    /// @custom:property ac-market-10 Calling setSeizePaused with the correct authorization should succeed.
    /// @custom:property ac-market-11 Calling setSeizePaused(true) should set seizePaused to 2.
    /// @custom:property ac-market-12 Calling setSeizePaused(false) should set seizePaused to 1.
    /// @custom:precondition address(this) has dao permissions
    function setSeizePaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature("setSeizePaused(bool)", state)
        );
        if (success) {
            uint256 seizePaused = marketManager.seizePaused();
            if (state == true) {
                // ac-market-11
                assertEq(
                    seizePaused,
                    2,
                    "LENDTROLLER - setSeizePaused() true expected to set seizePaused = 2 "
                );
            } else {
                assertEq(
                    // ac-market-12
                    seizePaused,
                    1,
                    "LENDTROLLER - setSeizePaused false expected to set seizePaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);
            // ac-market-10
            assertWithMsg(
                false,
                "LENDTROLLER - setSeizePaused() expected to be successful with correct preconditions"
            );
        }
    }

    /// @custom:property ac-market-3 Calling setBorrowPaused with correct preconditions should succeed.
    /// @custom:property Calling setBorrowPaused(mtoken, true) should set isBorrowPaused to 2.
    /// @custom:property Calling setBorrowPaused(mtoken, false) should set isBorrowPaused to 1.
    /// @custom:precondition address(this) has dao permissions
    /// @custom:precondition mtoken must be listed token in marketManager
    function setBorrowPaused_should_succeed(
        address mtoken,
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(marketManager.isListed(mtoken));

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature(
                "setBorrowPaused(address,bool)",
                mtoken,
                state
            )
        );
        if (success) {
            uint256 isBorrowPaused = marketManager.borrowPaused(mtoken);
            if (state) {
                assertWithMsg(
                    isBorrowPaused == 2,
                    "LENDTROLLER - setMintPaused() true succeed set isBorrowPaused = 2"
                );
            } else {
                assertWithMsg(
                    isBorrowPaused == 1,
                    "LENDTROLLER - setMintPaused() false should set mintPaused[mtoken] to 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "LENDTROLLER - setMintPaused() expected to be successful with correct preconditions"
            );
        }
    }
}
