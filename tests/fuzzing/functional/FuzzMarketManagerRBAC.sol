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
                assertWithMsg(
                    isMintPaused == 2,
                    "AC-MARKET-2 setMintPaused() true succeed set isMintPaused = 2"
                );
            } else {
                assertWithMsg(
                    isMintPaused == 1,
                    "AC-MARKET-3 setMintPaused() false should set mintPaused[mtoken] to 1"
                );
            }
        } else {
            // ac-market-1
            assertWithMsg(
                false,
                "AC-MARKET-1 setMintPaused() expected to be successful with correct preconditions"
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
                assertEq(
                    redeemPaused,
                    2,
                    "AC-MARKET-5 setRedeemPaused() true expected to set redeemPaused = 2 "
                );
            } else {
                assertEq(
                    redeemPaused,
                    1,
                    "AC-MARKET-6 setRedeemPaused false expected to set redeemPaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_unauthorizedSelectorHash,
                "AC-MARKET-4 setRedeemPaused() expected to be successful with correct preconditions"
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
                    "AC-MARKET-8 setTransferPaused() true expected to set TransferPaused = 2 "
                );
            } else {
                assertEq(
                    transferPaused,
                    1,
                    "AC-MARKET-9 setTransferPaused false expected to set TransferPaused = 1"
                );
            }
        } else {
            assertWithMsg(
                false,
                "AC-MARKET-7 setTransferPaused() expected to be successful with correct preconditions"
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
                assertEq(
                    seizePaused,
                    2,
                    "AC-MARKET-11 setSeizePaused() true expected to set seizePaused = 2 "
                );
            } else {
                assertEq(
                    seizePaused,
                    1,
                    "AC-MARKET-12 setSeizePaused false expected to set seizePaused = 1"
                );
            }
        } else {
            assertWithMsg(
                false,
                "AC-MARKET-10 setSeizePaused() expected to be successful with correct preconditions"
            );
        }
    }

    /// @custom:property ac-market-13 Calling setBorrowPaused with correct preconditions should succeed.
    /// @custom:property ac-market-14 Calling setBorrowPaused(mtoken, true) should set isBorrowPaused to 2.
    /// @custom:property ac-market-15 Calling setBorrowPaused(mtoken, false) should set isBorrowPaused to 1.
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
                    "AC-MARKET-14 setMintPaused() true succeed set isBorrowPaused = 2"
                );
            } else {
                assertWithMsg(
                    isBorrowPaused == 1,
                    "AC-MARKET-15 setMintPaused() false should set mintPaused[mtoken] to 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "AC-MARKET-13 setMintPaused() expected to be successful with correct preconditions"
            );
        }
    }
}
