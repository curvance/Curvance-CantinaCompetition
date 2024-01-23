pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";

contract FuzzMarketManagerStateChecks is StatefulBaseMarket {
    /// @custom:property sc-lend-1 canMint should not revert when mint is not paused and token is listed
    /// @custom:precondition mintPaused !=2
    /// @custom:precondition mtoken is listed in MarketManager
    function canMint_should_not_revert_when_mint_not_paused_and_is_listed(
        address mtoken
    ) public {
        uint256 mintPaused = marketManager.mintPaused(mtoken);
        bool isListed = marketManager.isListed(mtoken);

        require(mintPaused != 2);
        require(isListed);

        try marketManager.canMint(mtoken) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have not reverted"
            );
        }
    }

    /// @custom:property sc-lend-2 canMint should revert when token is not listed
    /// @custom:precondition mintPaused !=2
    /// @custom:precondition mtoken is not listed in MarketManager
    function canMint_should_revert_when_token_is_not_listed(
        address mtoken
    ) public {
        uint256 mintPaused = marketManager.mintPaused(mtoken);
        bool isListed = marketManager.isListed(mtoken);

        require(mintPaused != 2);
        require(!isListed);

        try marketManager.canMint(mtoken) {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have reverted when token is not listed but did not"
            );
        } catch {}
    }

    /// @custom:property sc-lend-3 canMint should revert when mintPaused = 2
    /// @custom:precondition mintPaused = 2
    /// @custom:precondition mtoken is listed in MarketManager
    function canMint_should_revert_when_mint_is_paused(address mtoken) public {
        uint256 mintPaused = marketManager.mintPaused(mtoken);
        bool isListed = marketManager.isListed(mtoken);

        require(mintPaused == 2);
        require(isListed);

        try marketManager.canMint(mtoken) {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have reverted when mint is paused but did not"
            );
        } catch {}
    }

    /// @custom:property sc-lend-4 canRedeem should be successful when @precondition are met
    /// @custom:precondition redeemPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition current timestamp > cooldownTimestamp + MIN_HOLD_PERIOD
    /// @custom:precondition user has a position for mtoken, addr(this)
    /// @custom:precondition liquidityDeficity >0
    function canRedeem_should_succeed(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.redeemPaused() != 2);
        require(marketManager.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        require(marketManager.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canRedeem(mtoken, account, amount) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to succeed under @precondition"
            );
        }
    }

    /// @custom:property sc-lend-5 canRedeem should revert when redeemPaused = 2
    /// @custom:precondition redeemPaused = 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition address(this) has a position for mtoken
    /// @custom:precondition liquidity deficity for hypothetical liquidity = 0;
    function canRedeem_should_revert_when_redeem_is_paused(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.redeemPaused() == 2);
        require(marketManager.isListed(mtoken));
        require(marketManager.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canRedeem(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert when redeem is paused"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_pausedSelectorHash,
                "LENDTROLLER - canRedeem() expected to revert with pausedSelectorHash"
            );
        }
    }

    /// @custom:property sc-lend-6 canRedeem should revert when token is not listed
    /// @custom:precondition redeemPaused != 2
    /// @custom:precondition mtoken is not listed in MarketManager
    /// @custom:precondition address(this) has a position for mtoken
    /// @custom:precondition liquidity deficity for hypothetical liquidity = 0;
    function canRedeem_should_revert_token_not_listed(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.redeemPaused() != 2);
        require(!marketManager.isListed(mtoken));
        require(marketManager.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canRedeem(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert token is not listed"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_tokenNotListedSelectorHash,
                "LENDTROLLER - canRedeem() expected to revert with token not listed"
            );
        }
    }

    /// @custom:property sc-lend-7 canRedeem should revert when liquidity deficit > 0
    /// @custom:precondition redeemPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition address(this) has a position for mtoken
    /// @custom:precondition liquidity deficity for hypothetical liquidity > 0;
    function canRedeem_should_revert_deficit_exists(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.redeemPaused() != 2);
        require(marketManager.isListed(mtoken));
        require(marketManager.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit > 0);
        try marketManager.canRedeem(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert token is not listed"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    marketmanager_insufficientCollateralSelectorHash,
                "LENDTROLLER - canRedeem() expected to revert with insufficient collateral"
            );
        }
    }

    /// @custom:property sc-lend-8 canRedeem should just return when user has no position for token
    /// @custom:precondition redeemPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition address(this) has no position for mtoken
    /// @custom:precondition liquidity deficity for hypothetical liquidity == 0;
    function canRedeem_should_return_when_no_position_exists(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.redeemPaused() != 2);
        require(marketManager.isListed(mtoken));
        require(!marketManager.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canRedeem(mtoken, account, amount) {} catch (
            bytes memory revertData
        ) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem() expected to return with no error when no position exists"
            );
        }
    }

    /// @custom:property sc-lend-9 canRedeemWithCollateralRemoval can only be called by mtoken
    /// @custom:precondition address(this) != mtoken
    function canRedeemWithCollateralRemoval_should_fail(
        address account,
        address mtoken,
        uint256 balance,
        uint256 amount,
        bool forceRedeemCollateral
    ) public {
        require(address(this) != mtoken);
        try
            marketManager.canRedeemWithCollateralRemoval(
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

    /// @custom:property sc-lend-10 canTransfer should succeed under correct preconditions
    /// @custom:precondition transferPaused != 2
    /// @custom:precondition redeemPaused =2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition timestamp has passed hold period
    /// @custom:precondition user has position
    function canTransfer_should_succed(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.transferPaused() != 2);
        require(marketManager.redeemPaused() != 2);
        require(marketManager.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        require(marketManager.hasPosition(mtoken, address(this)));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);

        try marketManager.canTransfer(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // canTransfer should have reverted with PAUSED
            assertWithMsg(
                errorSelector == marketmanager_pausedSelectorHash,
                "LENDTROLLER - canTransfer() expected PAUSED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-lend-11 canTransfer should fail with PAUSED when transferPaused = 2
    /// @custom:precondition transferPaused = 2
    /// @custom:precondition redeemPaused !=2
    /// @custom:precondition mtoken is listed in MarketManager
    function canTransfer_should_fail_when_transfer_is_paused(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.transferPaused() == 2);
        require(marketManager.redeemPaused() != 2);
        require(marketManager.isListed(mtoken));
        try marketManager.canTransfer(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // canTransfer should have reverted with PAUSED
            assertWithMsg(
                errorSelector == marketmanager_pausedSelectorHash,
                "LENDTROLLER - canTransfer() expected PAUSED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-lend-12 canTransfer should fail with NOT LISTED when mtoken is not added to system
    /// @custom:precondition transferPaused != 2
    /// @custom:precondition redeemPaused != 2
    /// @custom:precondition mtoken is not listed in MarketManager
    function canTransfer_should_fail_when_mtoken_not_listed(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.transferPaused() != 2);
        require(marketManager.redeemPaused() != 2);
        require(!marketManager.isListed(mtoken));
        try marketManager.canTransfer(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // canTransfer should have reverted with PAUSED
            assertWithMsg(
                errorSelector == marketmanager_tokenNotListedSelectorHash,
                "LENDTROLLER - canTransfer() expected NOTLISTED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-lend-13 canTransfer should fail with PAUSED when redeemPaused = 2
    /// @custom:precondition transferPaused != 2
    /// @custom:precondition redeemPaused =2
    /// @custom:precondition mtoken is listed in MarketManager
    function canTransfer_should_fail_when_redeem_is_paused(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.transferPaused() != 2);
        require(marketManager.redeemPaused() == 2);
        require(marketManager.isListed(mtoken));
        try marketManager.canTransfer(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // canTransfer should have reverted with PAUSED
            assertWithMsg(
                errorSelector == marketmanager_pausedSelectorHash,
                "LENDTROLLER - canTransfer() expected PAUSED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-lend-14 canBorrow should succeed when borrow is not paused and mtoken is listed
    /// @custom:precondition borrowPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition liquidityDeficit == 0
    function canBorrow_should_succeed(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.borrowPaused(mtoken) != 2);
        require(marketManager.isListed(mtoken));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canBorrow(mtoken, address(this), amount) {} catch {}
    }

    /// @custom:property sc-lend-15 canBorrow should fail with PAUSED when borrow is paused
    /// @custom:precondition borrowPaused = 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition liquidityDeficit == 0
    function canBorrow_should_fail_when_borrow_is_paused(
        address mtoken,
        uint256 amount
    ) public {
        require(marketManager.borrowPaused(mtoken) == 2);
        require(marketManager.isListed(mtoken));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canBorrow(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_pausedSelectorHash,
                "LENDTROLLER - canBorrow() expected PAUSED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-lend-16 canBorrow should fail with token is not listed
    /// @custom:precondition borrowPaused != 2
    /// @custom:precondition mtoken is not listed in MarketManager
    /// @custom:precondition liquidityDeficit == 0
    function canBorrow_should_fail_when_token_is_unlisted(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.borrowPaused(mtoken) != 2);
        require(!marketManager.isListed(mtoken));
        try marketManager.canBorrow(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_tokenNotListedSelectorHash,
                "LENDTROLLER - canBorrow() expected TOKEN NOT LISTED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-lend-17 canBorrow should fail with liquidityDeficity >0
    /// @custom:precondition borrowPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition liquidityDeficit > 0
    function canBorrow_should_fail_liquidity_deficit_exists(
        address mtoken,
        uint256 amount
    ) public {
        require(marketManager.borrowPaused(mtoken) != 2);
        require(marketManager.isListed(mtoken));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canBorrow(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    marketmanager_insufficientCollateralSelectorHash,
                "LENDTROLLER - canBorrow() expected INSUFFICIENT COLLATERAL selector hash on failure"
            );
        }
    }

    /// @custom:property sc-lend-18 canBorrowWithNotify should fail when called directly
    /// @custom:precondition mtoken != address(this)
    /// @custom:precondition mtoken is listed in MarketManager
    function canBorrowWithNotify_should_fail_when_called_directly(
        address mtoken,
        address account,
        uint256 amount
    ) public {
        require(mtoken != address(this));
        require(marketManager.isListed(mtoken));
        try marketManager.canBorrowWithNotify(mtoken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canBorrowWithNotify() should not succeed when not called by mtoken"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == marketmanager_unauthorizedSelectorHash,
                "LENDTROLLER - canBorrowWithNotify should have thrown unauthorized error but did not"
            );
        }
    }

    /// @custom:property sc-lend-19 canRepay should succeed under correct @precondition
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has passed cooldown timestamp
    function canRepay_should_succeed(address mtoken, address account) public {
        require(marketManager.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        try marketManager.canRepay(mtoken, account) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canRepay should have succeeded with correct @precondition"
            );
        }
    }

    /// @custom:property sc-lend-20 canRepay should fail when token is not listed
    /// @custom:precondition mtoken is not listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has passed cooldown timestamp
    function canRepay_should_fail_when_not_listed(
        address mtoken,
        address account
    ) public {
        require(!marketManager.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        try marketManager.canRepay(mtoken, account) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == marketmanager_tokenNotListedSelectorHash,
                "LENDTROLLER - canRepay should have reverted with token not listed errro"
            );
        }
    }

    /// @custom:property sc-lend-21 canRepay should fail when MIN_HOLD_PERIOD has not passed
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has not passed since cooldown timestamp
    function canRepay_should_fail_min_hold_has_not_passed(
        address mtoken,
        address account
    ) public {
        require(marketManager.isListed(mtoken));
        require(
            block.timestamp <=
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        try marketManager.canRepay(mtoken, account) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == marketmanager_minHoldSelectorHash,
                "LENDTROLLER - canRepay should have reverted with minimum hold period error"
            );
        }
    }

    /// @custom:property sc-lend-22 The canSeize function should succeed when seize is not paused, collateral and debt token are listed, and both tokens have the same marketManager.
    /// @custom:precondition seize is not paused
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has not passed since cooldown timestamp
    /// @custom:precondition collateral and debt token are listed
    /// @custom:precondition marketManager for collateral and debt token are identical
    function canSeize_should_succeed(
        address collateralToken,
        address debtToken
    ) public {
        require(marketManager.seizePaused() != 2);
        require(marketManager.isListed(collateralToken));
        require(marketManager.isListed(debtToken));
        require(
            IMToken(collateralToken).marketManager() ==
                IMToken(debtToken).marketManager()
        );
        try marketManager.canSeize(collateralToken, debtToken) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canSeize() should be successful with correct @precondition"
            );
        }
    }

    /// @custom:property sc-lend-23 The canSeize function should revert when seize is paused
    /// @custom:precondition seize is paused
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has not passed since cooldown timestamp
    /// @custom:precondition collateral and debt token are listed
    /// @custom:precondition marketManager for collateral and debt token are identical
    function canSeize_should_revert_when_seize_paused(
        address collateralToken,
        address debtToken
    ) public {
        require(marketManager.seizePaused() == 2);
        require(marketManager.isListed(collateralToken));
        require(marketManager.isListed(debtToken));
        require(
            IMToken(collateralToken).marketManager() ==
                IMToken(debtToken).marketManager()
        );
        try marketManager.canSeize(collateralToken, debtToken) {
            assertWithMsg(
                false,
                "LENDTROLLER - canSeize() should have reverted with seizePaused = 2"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_pausedSelectorHash,
                "LENDTROLLER - canSeize() should revert with paused selector"
            );
        }
    }

    /// @custom:property sc-lend-24 The canSeize function should revert when collateral or debt token are not listed
    /// @custom:precondition seize is not paused
    /// @custom:precondition token is  not listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has not passed since cooldown timestamp
    /// @custom:precondition collateral or debt token are not listed
    /// @custom:precondition marketManager for collateral and debt token are identical
    function canSeize_should_revert_when_token_is_unlisted(
        address collateralToken,
        address debtToken
    ) public {
        require(marketManager.seizePaused() != 2);
        require(
            !marketManager.isListed(collateralToken) ||
                !marketManager.isListed(debtToken)
        );
        require(
            IMToken(collateralToken).marketManager() ==
                IMToken(debtToken).marketManager()
        );
        try marketManager.canSeize(collateralToken, debtToken) {
            assertWithMsg(
                false,
                "LENDTROLLER - seizePaused() should have reverted when token is unlisted"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_tokenNotListedSelectorHash,
                "LENDTROLLER - canSeize() should revert with token not listed selector"
            );
        }
    }

    /// @custom:property sc-lend-25 The canSeize function should succeed when seize is not paused, collateral and debt token are listed, and both tokens have the same marketManager.
    /// @custom:precondition seize is not paused
    /// @custom:precondition token is  not listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has not passed since cooldown timestamp
    /// @custom:precondition collateral and debt token are listed
    /// @custom:precondition marketManager for collateral and debt token are not identical
    function canSeize_should_revert_when_marketmanager_not_equal(
        address collateralToken,
        address debtToken
    ) public {
        require(marketManager.seizePaused() != 2);
        require(marketManager.isListed(collateralToken));
        require(marketManager.isListed(debtToken));
        require(
            IMToken(collateralToken).marketManager() !=
                IMToken(debtToken).marketManager()
        );
        try marketManager.canSeize(collateralToken, debtToken) {
            assertWithMsg(
                false,
                "LENDTROLLER - seizePaused() should have reverted when marketManager is not equal"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_mismatchSelectorHash,
                "LENDTROLLER - canSeize() should revert with marketManager mismatch selector hash"
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
            marketManager.canLiquidate(
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
            marketManager.canLiquidateWithExecution(
                dToken,
                cToken,
                account,
                amount,
                liquidateExact
            )
        {} catch {}
    }
}
