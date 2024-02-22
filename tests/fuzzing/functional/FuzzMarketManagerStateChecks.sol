pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";

contract FuzzMarketManagerStateChecks is StatefulBaseMarket {
    /// @custom:property sc-market-1 canMint should not revert when mint is not paused and token is listed
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
                "SC-MARKET-1 canMint() should have not reverted"
            );
        }
    }

    /// @custom:property sc-market-2 canMint should revert when token is not listed
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
                "SC-MARKET-2 canMint() should have reverted when token is not listed but did not"
            );
        } catch {}
    }

    /// @custom:property sc-market-3 canMint should revert when mintPaused = 2
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
                "SC-MARKET-3 canMint() should have reverted when mint is paused but did not"
            );
        } catch {}
    }

    /// @custom:property sc-market-4 canRedeem should be successful when @precondition are met
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
        require(_hasPosition(mtoken));
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
                "SC-MARKET-4 canRedeem expected to succeed under @precondition"
            );
        }
    }

    /// @custom:property sc-market-5 canRedeem should revert when redeemPaused = 2
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
        require(_hasPosition(mtoken));
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
                "SC-MARKET-5 canRedeem expected to revert when redeem is paused"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_pausedSelectorHash,
                "SC-MARKET-5 canRedeem() expected to revert with pausedSelectorHash"
            );
        }
    }

    /// @custom:property sc-market-6 canRedeem should revert when token is not listed
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
        require(_hasPosition(mtoken));
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
                "SC-MARKET-6 canRedeem expected to revert token is not listed"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_tokenNotListedSelectorHash,
                "SC-MARKET-6 canRedeem() expected to revert with token not listed"
            );
        }
    }

    /// @custom:property sc-market-7 canRedeem should revert when liquidity deficit > 0
    /// @custom:precondition redeemPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition address(this) has a position for mtoken
    /// @custom:precondition liquidity deficity for hypothetical liquidity > 0;
    function canRedeem_should_revert_deficit_exists(
        address mtoken,
        uint256 amount
    ) public {
        address account = address(this);
        require(marketManager.redeemPaused() != 2);
        require(marketManager.isListed(mtoken));
        require(_hasPosition(mtoken));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            account,
            mtoken,
            amount,
            0
        );
        require(liquidityDeficit > 0);
        try marketManager.canRedeem(mtoken, account, amount) {
            assertWithMsg(
                false,
                "SC-MARKET-7 canRedeem expected to revert deficit exists"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    marketManager_insufficientCollateralSelectorHash,
                "SC-MARKET-7 canRedeem() expected to revert with insufficient collateral"
            );
        }
    }

    /// @custom:property sc-market-8 canRedeem should just return when user has no position for token
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
        require(!_hasPosition(mtoken));
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
                "SC-MARKET-8 canRedeem() expected to return with no error when no position exists"
            );
        }
    }

    /// @custom:property sc-market-9 canRedeemWithCollateralRemoval can only be called by mtoken
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
                "SC-MARKET-9 canRedeemWithCollateralRemoval should only be callable by mtoken"
            );
        } catch {}
    }

    /// @custom:property sc-market-10 canTransfer should succeed under correct preconditions
    /// @custom:precondition transferPaused != 2
    /// @custom:precondition redeemPaused =2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition timestamp has passed hold period
    /// @custom:precondition user has position
    /// @custom:precondition liquidityDeficit should be = 0
    function canTransfer_should_succeed(
        address mtoken,
        uint256 amount
    ) public {
        require(marketManager.transferPaused() != 2);
        require(marketManager.redeemPaused() != 2);
        require(marketManager.isListed(mtoken));
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        require(_hasPosition(mtoken));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            amount,
            0
        );
        require(liquidityDeficit == 0);

        (uint256 accountCollateral, uint256 accountDebt) = marketManager
            .solvencyOf(address(this));
        require(accountDebt != 0);
        amount = clampBetween(amount, 1, accountCollateral);

        try marketManager.canTransfer(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                false,
                "SC-MARKET-10 canTransfer() canTransfer should succeed with correct preconditions"
            );
        }
    }

    /// @custom:property sc-market-11 canTransfer should fail with PAUSED when transferPaused = 2
    /// @custom:precondition transferPaused = 2
    /// @custom:precondition redeemPaused !=2
    /// @custom:precondition mtoken is listed in MarketManager
    function canTransfer_should_fail_when_transfer_is_paused(
        address mtoken,
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
                errorSelector == marketManager_pausedSelectorHash,
                "SC-MARKET-11 canTransfer() expected PAUSED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-market-12 canTransfer should fail with NOT LISTED when mtoken is not added to system
    /// @custom:precondition transferPaused != 2
    /// @custom:precondition redeemPaused != 2
    /// @custom:precondition mtoken is not listed in MarketManager
    function canTransfer_should_fail_when_mtoken_not_listed(
        address mtoken,
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
                errorSelector == marketManager_tokenNotListedSelectorHash,
                "SC-MARKET-12 canTransfer() expected NOTLISTED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-market-13 canTransfer should fail with PAUSED when redeemPaused = 2
    /// @custom:precondition transferPaused != 2
    /// @custom:precondition redeemPaused =2
    /// @custom:precondition mtoken is listed in MarketManager
    function canTransfer_should_fail_when_redeem_is_paused(
        address mtoken,
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
                errorSelector == marketManager_pausedSelectorHash,
                "SC-MARKET-13 canTransfer() expected PAUSED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-market-14 canBorrow should succeed when borrow is not paused and mtoken is listed
    /// @custom:precondition borrowPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition liquidityDeficit == 0
    /// @custom:precondition require that the mtoken has a position in the market
    function canBorrow_should_succeed(address mtoken, uint256 amount) public {
        _isSupportedDToken(mtoken);
        require(marketManager.borrowPaused(mtoken) != 2);
        require(marketManager.isListed(mtoken));
        require(_hasPosition(mtoken));
        (, uint256 liquidityDeficit) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            0,
            amount
        );
        require(liquidityDeficit == 0);
        try marketManager.canBorrow(mtoken, address(this), amount) {} catch {
            assertWithMsg(false, "SC-MARKET-14 canBorrow() should succeed");
        }
    }

    /// @custom:property sc-market-15 canBorrow should fail with PAUSED when borrow is paused
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
                errorSelector == marketManager_pausedSelectorHash,
                "SC-MARKET-15 canBorrow() expected PAUSED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-market-16 canBorrow should fail with token is not listed
    /// @custom:precondition borrowPaused != 2
    /// @custom:precondition mtoken is not listed in MarketManager
    /// @custom:precondition liquidityDeficit == 0
    function canBorrow_should_fail_when_token_is_unlisted(
        address mtoken,
        uint256 amount
    ) public {
        require(marketManager.borrowPaused(mtoken) != 2);
        require(!marketManager.isListed(mtoken));
        try marketManager.canBorrow(mtoken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_tokenNotListedSelectorHash,
                "SC-MARKET-16 canBorrow() expected TOKEN NOT LISTED selector hash on failure"
            );
        }
    }

    /// @custom:property sc-market-17 canBorrow should fail with liquidityDeficity >0
    /// @custom:precondition borrowPaused != 2
    /// @custom:precondition mtoken is listed in MarketManager
    /// @custom:precondition liquidityDeficit > 0
    /// @custom:precondition account has active position
    function canBorrow_should_fail_liquidity_deficit_exists(
        address mtoken,
        uint256 amount
    ) public {
        require(marketManager.borrowPaused(mtoken) != 2);
        require(marketManager.isListed(mtoken));
        require(_hasPosition(mtoken));
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
                    marketManager_insufficientCollateralSelectorHash,
                "SC-MARKET-17 canBorrow() expected INSUFFICIENT COLLATERAL selector hash on failure"
            );
        }
    }

    /// @custom:property sc-market-18 canBorrowWithNotify should fail when called directly
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
                "SC-MARKET-18 canBorrowWithNotify() should not succeed when not called by mtoken"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == marketManager_unauthorizedSelectorHash,
                "SC-MARKET-18 canBorrowWithNotify should have thrown unauthorized error but did not"
            );
        }
    }

    /// @custom:property sc-market-19 canRepay should succeed under correct @precondition
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
                "SC-MARKET-19 canRepay should have succeeded with correct @precondition"
            );
        }
    }

    /// @custom:property sc-market-20 canRepay should fail when token is not listed
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
                errorSelector == marketManager_tokenNotListedSelectorHash,
                "SC-MARKET-20 canRepay should have reverted with token not listed errro"
            );
        }
    }

    /// @custom:property sc-market-21 canRepay should fail when MIN_HOLD_PERIOD has not passed
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
                errorSelector == marketManager_minHoldSelectorHash,
                "SC-MARKET-21 canRepay should have reverted with minimum hold period error"
            );
        }
    }

    /// @custom:property sc-market-22 The canSeize function should succeed when seize is not paused, collateral and debt token are listed, and both tokens have the same marketManager.
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
                "SC-MARKET-22 canSeize() should be successful with correct @precondition"
            );
        }
    }

    /// @custom:property sc-market-23 The canSeize function should revert when seize is paused
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
                "SC-MARKET-23 canSeize() should have reverted with seizePaused = 2"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_pausedSelectorHash,
                "SC-MARKET-23 canSeize() should revert with paused selector"
            );
        }
    }

    /// @custom:property sc-market-24 The canSeize function should revert when collateral or debt token are not listed
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
                "SC-MARKET-24 seizePaused() should have reverted when token is unlisted"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_tokenNotListedSelectorHash,
                "SC-MARKET-24 canSeize() should revert with token not listed selector"
            );
        }
    }

    /// @custom:property sc-market-25 The canSeize function should succeed when seize is not paused, collateral and debt token are listed, and both tokens have the same marketManager.
    /// @custom:precondition seize is not paused
    /// @custom:precondition token is  not listed in MarketManager
    /// @custom:precondition MIN_HOLD_PERIOD has not passed since cooldown timestamp
    /// @custom:precondition collateral and debt token are listed
    /// @custom:precondition marketManager for collateral and debt token are not identical
    function canSeize_should_revert_when_marketManager_not_equal(
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
                "SC-MARKET-25 seizePaused() should have reverted when marketManager is not equal"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_mismatchSelectorHash,
                "SC-MARKET-25 canSeize() should revert with marketManager mismatch selector hash"
            );
        }
    }

    /// @custom:limitation TODO missing coverage on canLiquidate and canLiquidateWithExecution
}
