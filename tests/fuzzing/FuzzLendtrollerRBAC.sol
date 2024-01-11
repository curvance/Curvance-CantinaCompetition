pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { IMToken } from "contracts/market/lendtroller/LiquidityManager.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract FuzzLendtrollerRBAC is StatefulBaseMarket {
    // @property: setMintPaused with correct preconditions should not revert
    // @property: setMintPaused should set mintPaused(mtoken) = 2 when state = true
    // @property: setMintPaused should set mintPaused(mtoken) = 1 when state = false
    // @precondition: address(this) is authorized
    // @precondition: mtoken is listed
    function setMintPaused_should_succeed_when_authorized_and_listed(
        address mtoken,
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(lendtroller.isListed(mtoken));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "setMintPaused(address,bool)",
                mtoken,
                state
            )
        );
        if (success) {
            uint256 isMintPaused = lendtroller.mintPaused(mtoken);
            if (state) {
                assertWithMsg(
                    isMintPaused == 2,
                    "LENDTROLLER - setMintPaused() true succeed set isMintPaused = 2"
                );
            } else {
                assertWithMsg(
                    isMintPaused == 1,
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

    // @property: setRedeemPaused(true) should set redeemPaused = 2
    // @property: setRedeemPause(false) should set redeemPaused = 1
    // @precondition: address(this) has dao permissions
    function setRedeemPaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature("setRedeemPaused(bool)", state)
        );
        if (success) {
            uint256 redeemPaused = lendtroller.redeemPaused();
            if (state == true) {
                assertEq(
                    redeemPaused,
                    2,
                    "LENDTROLLER - setRedeemPaused() true expected to set redeemPaused = 2 "
                );
            } else {
                assertEq(
                    redeemPaused,
                    1,
                    "LENDTROLLER - setRedeemPaused false expected to set redeemPaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                errorSelector == lendtroller_unauthorizedSelectorHash,
                "LENDTROLLER - setRedeemPaused() expected to be successful with correct preconditions"
            );
        }
    }

    // @property: setTransferPaused(true) should set transferPaused = 2
    // @property: setTransferPause(false) should set transferPaused = 1
    // @precondition: address(this) has dao permissions
    function setTransferPaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature("setTransferPaused(bool)", state)
        );
        if (success) {
            uint256 transferPaused = lendtroller.transferPaused();
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

    // @property: setSeizePaused(true) should set transferPaused = 2
    // @property: setTransferPause(false) should set transferPaused = 1
    // @precondition: address(this) has dao permissions
    function setSeizePaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature("setSeizePaused(bool)", state)
        );
        if (success) {
            uint256 seizePaused = lendtroller.seizePaused();
            if (state == true) {
                assertEq(
                    seizePaused,
                    2,
                    "LENDTROLLER - setSeizePaused() true expected to set seizePaused = 2 "
                );
            } else {
                assertEq(
                    seizePaused,
                    1,
                    "LENDTROLLER - setSeizePaused false expected to set seizePaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "LENDTROLLER - setSeizePaused() expected to be successful with correct preconditions"
            );
        }
    }

    // @property: setBorrowPaused(true) should set borrowPaused = 2
    // @property: setTransferPause(false) should set borrowPaused = 1
    // @precondition: address(this) has dao permissions
    // @precondition: mtoken must be listed token in lendtroller
    function setBorrowPaused_should_succeed(
        address mtoken,
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(lendtroller.isListed(mtoken));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "setBorrowPaused(address,bool)",
                mtoken,
                state
            )
        );
        if (success) {
            uint256 isBorrowPaused = lendtroller.borrowPaused(mtoken);
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
