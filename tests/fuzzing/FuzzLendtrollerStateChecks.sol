pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { IMToken } from "contracts/market/lendtroller/LiquidityManager.sol";

contract FuzzLendtrollerStateChecks is StatefulBaseMarket {
    // @property: canMint should not revert when mint is not paused and token is listed
    // @precondition: mintPaused !=2
    // @precondition: mtoken is listed in Lendtroller
    function canMint_should_not_revert_when_mint_not_paused_and_is_listed(
        address mToken
    ) public {
        uint256 mintPaused = lendtroller.mintPaused(mToken);
        bool isListed = lendtroller.isListed(mToken);

        require(mintPaused != 2);
        require(isListed);

        try lendtroller.canMint(mToken) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have not reverted"
            );
        }
    }

    // @property: canMint should revert when token is not listed
    // @precondition: mintPaused !=2
    // @precondition: mtoken is not listed in Lendtroller
    function canMint_should_revert_when_token_is_not_listed(
        address mToken
    ) public {
        uint256 mintPaused = lendtroller.mintPaused(mToken);
        bool isListed = lendtroller.isListed(mToken);

        require(mintPaused != 2);
        require(!isListed);

        try lendtroller.canMint(mToken) {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have reverted when token is not listed but did not"
            );
        } catch {}
    }

    // @property: canMint should revert when mintPaused = 2
    // @precondition: mintPaused = 2
    // @precondition: mtoken is listed in Lendtroller
    function canMint_should_revert_when_mint_is_paused(address mToken) public {
        uint256 mintPaused = lendtroller.mintPaused(mToken);
        bool isListed = lendtroller.isListed(mToken);

        require(mintPaused == 2);
        require(isListed);

        try lendtroller.canMint(mToken) {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have reverted when mint is paused but did not"
            );
        } catch {}
    }

    // @property: canRedeem should be successful when @precondition are met
    // @precondition: redeemPaused != 2
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: current timestamp > cooldownTimestamp + MIN_HOLD_PERIOD
    // @precondition: user has a position for mtoken, addr(this)
    // @precondition: liquidityDeficity >0
    function canRedeem_should_succeed(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() != 2);
        require(lendtroller.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + lendtroller.MIN_HOLD_PERIOD()
        );
        require(lendtroller.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try lendtroller.canRedeem(mtoken, account, amount) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to succeed under @precondition"
            );
        }
    }

    // @property: canRedeem should revert when redeemPaused = 2
    // @precondition: redeemPaused = 2
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: address(this) has a position for mtoken
    // @precondition: liquidity deficity for hypothetical liquidity = 0;
    function canRedeem_should_revert_when_redeem_is_paused(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() == 2);
        require(lendtroller.isListed(mtoken));
        require(lendtroller.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try lendtroller.canRedeem(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert when redeem is paused"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_pausedSelectorHash,
                "LENDTROLLER - canRedeem() expected to revert with pausedSelectorHash"
            );
        }
    }

    // @property: canRedeem should revert when token is not listed
    // @precondition: redeemPaused != 2
    // @precondition: mtoken is not listed in Lendtroller
    // @precondition: address(this) has a position for mtoken
    // @precondition: liquidity deficity for hypothetical liquidity = 0;
    function canRedeem_should_revert_token_not_listed(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() != 2);
        require(!lendtroller.isListed(mtoken));
        require(lendtroller.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try lendtroller.canRedeem(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert token is not listed"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_tokenNotListedSelectorHash,
                "LENDTROLLER - canRedeem() expected to revert with token not listed"
            );
        }
    }

    // @property: canRedeem should revert when liquidity deficit > 0
    // @precondition: redeemPaused != 2
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: address(this) has a position for mtoken
    // @precondition: liquidity deficity for hypothetical liquidity > 0;
    function canRedeem_should_revert_deficit_exists(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() != 2);
        require(lendtroller.isListed(mtoken));
        require(lendtroller.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit > 0);
        try lendtroller.canRedeem(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert token is not listed"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    lendtroller_insufficientCollateralSelectorHash,
                "LENDTROLLER - canRedeem() expected to revert with insufficient collateral"
            );
        }
    }

    // @property: canRedeem should just return when user has no position for token
    // @precondition: redeemPaused != 2
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: address(this) has no position for mtoken
    // @precondition: liquidity deficity for hypothetical liquidity == 0;
    function canRedeem_should_return_when_no_position_exists(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() != 2);
        require(lendtroller.isListed(mtoken));
        require(!lendtroller.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try lendtroller.canRedeem(mtoken, account, amount) {} catch (
            bytes memory revertData
        ) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem() expected to return with no error when no position exists"
            );
        }
    }

    // @property: canRedeemWithCollateralRemoval can only be called by mtoken
    // @precondition: address(this) != mtoken
    function canRedeemWithCollateralRemoval_should_fail(
        address account,
        address mtoken,
        uint256 balance,
        uint256 amount,
        bool forceRedeemCollateral
    ) public {
        require(address(this) != mtoken);
        try
            lendtroller.canRedeemWithCollateralRemoval(
                account,
                mtoken,
                balance,
                amount,
                forceRedeemCollateral
            )
        {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeemWithCollateralRemoval should only be callable by mtoken"
            );
        } catch {}
    }

    // @property canTransfer should fail with PAUSED when transferPaused = 2
    // @precondition transferPaused = 2
    // @precondition redeemPaused !=2
    // @precondition mtoken is listed in Lendtroller
    function canTransfer_should_fail_when_transfer_is_paused(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.transferPaused() == 2);
        require(lendtroller.redeemPaused() != 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canTransfer(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // canTransfer should have reverted with PAUSED
            assertWithMsg(
                errorSelector == lendtroller_pausedSelectorHash,
                "LENDTROLLER - canTransfer() expected PAUSED selector hash on failure"
            );
        }
    }

    // @property canTransfer should fail with NOT LISTED when mtoken is not added to system
    // @precondition transferPaused != 2
    // @precondition redeemPaused != 2
    // @precondition mtoken is not listed in Lendtroller
    function canTransfer_should_fail_when_mtoken_not_listed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.transferPaused() != 2);
        require(lendtroller.redeemPaused() != 2);
        require(!lendtroller.isListed(mToken));
        try lendtroller.canTransfer(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // canTransfer should have reverted with PAUSED
            assertWithMsg(
                errorSelector == lendtroller_tokenNotListedSelectorHash,
                "LENDTROLLER - canTransfer() expected NOTLISTED selector hash on failure"
            );
        }
    }

    // @property canTransfer should fail with PAUSED when redeemPaused = 2
    // @precondition transferPaused != 2
    // @precondition redeemPaused =2
    // @precondition mtoken is listed in Lendtroller
    function canTransfer_should_fail_when_redeem_is_paused(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.transferPaused() != 2);
        require(lendtroller.redeemPaused() == 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canTransfer(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // canTransfer should have reverted with PAUSED
            assertWithMsg(
                errorSelector == lendtroller_pausedSelectorHash,
                "LENDTROLLER - canTransfer() expected PAUSED selector hash on failure"
            );
        }
    }

    // @property canBorrow should succeed when borrow is not paused and mtoken is listed
    // @precondition borrowPaused != 2
    // @precondition mtoken is listed in Lendtroller
    // @precondition: liquidityDeficit == 0
    function canBorrow_should_succeed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) != 2);
        require(lendtroller.isListed(mToken));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mToken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch {}
    }

    // @property canBorrow should fail with PAUSED when borrow is paused
    // @precondition: borrowPaused = 2
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: liquidityDeficit == 0
    function canBorrow_should_fail_when_borrow_is_paused(
        address mToken,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) == 2);
        require(lendtroller.isListed(mToken));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mToken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_pausedSelectorHash,
                "LENDTROLLER - canBorrow() expected PAUSED selector hash on failure"
            );
        }
    }

    // @property canBorrow should fail with token is not listed
    // @precondition: borrowPaused != 2
    // @precondition: mtoken is not listed in Lendtroller
    // @precondition: liquidityDeficit == 0
    function canBorrow_should_fail_when_token_is_unlisted(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) != 2);
        require(!lendtroller.isListed(mToken));
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_tokenNotListedSelectorHash,
                "LENDTROLLER - canBorrow() expected TOKEN NOT LISTED selector hash on failure"
            );
        }
    }

    // @property canBorrow should fail with liquidityDeficity >0
    // @precondition: borrowPaused != 2
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: liquidityDeficit > 0
    function canBorrow_should_fail_liquidity_deficit_exists(
        address mToken,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) != 2);
        require(lendtroller.isListed(mToken));
        (, uint256 liquidityDeficit) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mToken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    lendtroller_insufficientCollateralSelectorHash,
                "LENDTROLLER - canBorrow() expected INSUFFICIENT COLLATERAL selector hash on failure"
            );
        }
    }

    function canBorrowWithNotify_should_fail_when_called_directly(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(mtoken != address(this));
        require(lendtroller.isListed(mtoken));
        try lendtroller.canBorrowWithNotify(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canBorrowWithNotify() should not succeed when not called by mtoken"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == lendtroller_unauthorizedSelectorHash,
                "LENDTROLLER - canBorrowWithNotify should have thrown unauthorized error but did not"
            );
        }
    }

    function notifyBorrow_should_fail_when_called_directly(
        address mtoken,
        address account
    ) public {
        require(mtoken != address(this));

        try lendtroller.notifyBorrow(mtoken, account) {
            assertWithMsg(
                false,
                "LENDTROLLER - notifyBorrow() should not succeed when not called by mtoken"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == lendtroller_unauthorizedSelectorHash,
                "LENDTROLLER - canBorrowWithNotify should have thrown unauthorized error but did not"
            );
        }
    }

    // @property: canRepay should succeed under correct @precondition
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: MIN_HOLD_PERIOD has passed cooldown timestamp
    function canRepay_should_succeed(address mtoken, address account) public {
        require(lendtroller.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + lendtroller.MIN_HOLD_PERIOD()
        );
        try lendtroller.canRepay(mtoken, account) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canRepay should have succeeded with correct @precondition"
            );
        }
    }

    // @property: canRepay should fail when token is not listed
    // @precondition: mtoken is not listed in Lendtroller
    // @precondition: MIN_HOLD_PERIOD has passed cooldown timestamp
    function canRepay_should_fail_when_not_listed(
        address mtoken,
        address account
    ) public {
        require(!lendtroller.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + lendtroller.MIN_HOLD_PERIOD()
        );
        try lendtroller.canRepay(mtoken, account) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == lendtroller_tokenNotListedSelectorHash,
                "LENDTROLLER - canRepay should have reverted with token not listed errro"
            );
        }
    }

    // @property: canRepay should fail when MIN_HOLD_PERIOD has not passed
    // @precondition: mtoken is listed in Lendtroller
    // @precondition: MIN_HOLD_PERIOD has not passed since cooldown timestamp
    function canRepay_should_fail_min_hold_has_not_passed(
        address mtoken,
        address account
    ) public {
        require(lendtroller.isListed(mtoken));
        require(
            block.timestamp <=
                postedCollateralAt[mtoken] + lendtroller.MIN_HOLD_PERIOD()
        );
        try lendtroller.canRepay(mtoken, account) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == lendtroller_minHoldSelectorHash,
                "LENDTROLLER - canRepay should have reverted with minimum hold period error"
            );
        }
    }

    function canLiquidate_should_succeed(
        address dToken,
        address cToken,
        address account,
        uint256 amount,
        bool liquidateExact
    ) public {
        try
            lendtroller.canLiquidate(
                dToken,
                cToken,
                account,
                amount,
                liquidateExact
            )
        {} catch {}
    }

    function canLiquidateWithExecution_should_succeed(
        address dToken,
        address cToken,
        address account,
        uint256 amount,
        bool liquidateExact
    ) public {
        try
            lendtroller.canLiquidateWithExecution(
                dToken,
                cToken,
                account,
                amount,
                liquidateExact
            )
        {} catch {}
    }

    //
    function canSeize_should_succeed(
        address collateralToken,
        address debtToken
    ) public {
        require(lendtroller.seizePaused() != 2);
        require(lendtroller.isListed(collateralToken));
        require(lendtroller.isListed(debtToken));
        require(
            IMToken(collateralToken).lendtroller() ==
                IMToken(debtToken).lendtroller()
        );
        try lendtroller.canSeize(collateralToken, debtToken) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canSeize() should be successful with correct @precondition"
            );
        }
    }
}
