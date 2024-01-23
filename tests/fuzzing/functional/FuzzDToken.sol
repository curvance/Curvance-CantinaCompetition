pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";

contract FuzzDToken is StatefulBaseMarket {
    /// @custom:property dtok-1 calling DToken.mint should succeed with correct preconditions
    /// @custom:property dtok-2 underlying balance for sender DToken should decrease by amount
    /// @custom:property dtok-3  balance should increase by `amount * WAD/exchangeRateCached()`
    /// @custom:property dtok-4 DToken totalSupply should increase by `amount * WAD/exchangeRateCached()`
    /// @custom:precondition amount bound between [1, uint256.max]
    function mint_should_actually_succeed(
        address dtoken,
        uint256 amount
    ) public {
        is_supported_dtoken(dtoken);
        require(gaugePool.startTime() < block.timestamp);
        check_price_feed();
        (bool mintingPossible, ) = address(marketManager).call(
            abi.encodeWithSignature("canMint(address)", dtoken)
        );
        require(mintingPossible);
        address underlyingTokenAddress = DToken(dtoken).underlying();
        // amount = clampBetweenBoundsFromOne(lower, amount);
        amount = clampBetween(amount, 1, type(uint64).max);
        require(mint_and_approve(underlyingTokenAddress, dtoken, amount));
        uint256 preUnderlyingBalance = IERC20(underlyingTokenAddress)
            .balanceOf(address(this));
        uint256 preDTokenBalance = DToken(dtoken).balanceOf(address(this));
        uint256 preDTokenTotalSupply = DToken(dtoken).totalSupply();

        emit LogUint256(
            "exchange rate: ",
            DToken(dtoken).exchangeRateCached()
        );

        try DToken(dtoken).mint(amount) {
            uint256 postDTokenBalance = DToken(dtoken).balanceOf(
                address(this)
            );
            uint256 adjustedNumberOfTokens = (amount * WAD) /
                DToken(dtoken).exchangeRateCached();
            uint256 postUnderlyingBalance = IERC20(underlyingTokenAddress)
                .balanceOf(address(this));
            // DTOK-2
            assertEq(
                preUnderlyingBalance - amount,
                postUnderlyingBalance,
                "DTOKEN - mint should reduce underlying token balance"
            );
            // DTOK-3
            assertEq(
                preDTokenBalance,
                postDTokenBalance - adjustedNumberOfTokens,
                "DTOKEN - mint should increase balanceOf[msg.sender] by (amount*WAD)/exchangeRate"
            );

            uint256 postDTokenTotalSupply = DToken(dtoken).totalSupply();
            // DTOK-4
            assertEq(
                preDTokenTotalSupply,
                postDTokenTotalSupply - adjustedNumberOfTokens,
                "DTOKEN - mint should increase totalSupply"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            uint256 adjustedNumberOfTokens = (amount * WAD) /
                DToken(dtoken).exchangeRateCached();
            emit LogUint256("adjustedNumberOfTokens", adjustedNumberOfTokens);
            bool underlyingTokenSupplyOverflow = doesOverflow(
                preUnderlyingBalance + amount,
                preUnderlyingBalance
            );
            emit LogBool(
                "underlying overflow:",
                underlyingTokenSupplyOverflow
            );
            bool dtokenSupplyOverflow = doesOverflow(
                preDTokenTotalSupply + adjustedNumberOfTokens,
                preDTokenTotalSupply
            );
            emit LogBool("supply overflow:", dtokenSupplyOverflow);
            bool balanceOverflow = doesOverflow(
                preDTokenBalance + adjustedNumberOfTokens,
                preDTokenBalance
            );
            emit LogBool("dtoken balance overflow:", balanceOverflow);
            if (
                underlyingTokenSupplyOverflow ||
                dtokenSupplyOverflow ||
                balanceOverflow
            ) {
                assertEq(
                    errorSelector,
                    0,
                    "DTOKEN - mint should revert if overflow"
                );
            } else {
                // DTOK-1
                assertWithMsg(
                    false,
                    "DTOKEN - mint should succeed with correct preconditions"
                );
            }
        }
    }

    /// @custom:property dtok-5 borrow should succeed with correct preconditions
    /// @custom:property dtok-6 totalBorrows if interest has not accrued should increase by amount after borrow is called
    /// @custom:property dtok-7 underlying balance if interest has not accrued should increase by amount for msg.sender
    /// @custom:precondition token to borrow is either dUSDC or dDAI
    /// @custom:precondition amount is bound between [1, marketUnderlyingHeld() - totalReserves]
    /// @custom:precondition borrow is not paused
    /// @custom:precondition dtoken must be listed
    /// @custom:precondition user must not have a shortfall for respective token
    function borrow_should_succeed_not_accruing_interest(
        address dtoken,
        uint256 amount
    ) public {
        is_supported_dtoken(dtoken);
        check_price_feed();
        address underlying = DToken(dtoken).underlying();
        require(marketManager.isListed(dtoken));
        require(marketManager.borrowPaused(dtoken) != 2);
        uint256 upperBound = DToken(dtoken).marketUnderlyingHeld() -
            DToken(dtoken).totalReserves();
        amount = clampBetween(amount, 1, upperBound - 1);
        require(mint_and_approve(DToken(dtoken).underlying(), dtoken, amount));
        (bool borrowPossible, ) = address(marketManager).call(
            abi.encodeWithSignature(
                "canBorrow(address,address,uint256)",
                dtoken,
                address(this),
                amount
            )
        );
        require(borrowPossible);
        (uint32 lastTimestampUpdated, , uint256 compoundRate) = DToken(dtoken)
            .marketData();
        require(lastTimestampUpdated + compoundRate > block.timestamp);

        uint256 preTotalBorrows = DToken(dtoken).totalBorrows();
        uint256 preUnderlyingBalance = IERC20(underlying).balanceOf(
            address(this)
        );

        try DToken(dtoken).borrow(amount) {
            // Interest was not accrued
            assertEq(
                DToken(dtoken).totalBorrows(),
                preTotalBorrows + amount,
                "DTOKEN - borrow postTotalBorrows failed = preTotalBorrows + amount"
            );
            uint256 postUnderlyingBalance = IERC20(underlying).balanceOf(
                address(this)
            );

            assertEq(
                postUnderlyingBalance,
                preUnderlyingBalance + amount,
                "DTOKEN - borrow postUnderlyingBalance failed = underlyingBalance + amount"
            );
            // TODO: Add check for _debtOf[account].principal
            // TODO: Add check for _debtOf[account].accountExchangeRate
            postedCollateralAt[dtoken] = block.timestamp;
        } catch {
            assertWithMsg(
                false,
                "DTOKEN - borrow should succeed with correct preconditions"
            );
        }
    }

    /// @custom:property dtok- borrow should succeed with correct preconditions
    /// @custom:property dtok- totalBorrows if interest has accrued should increase by amount after borrow is called
    /// @custom:property dtok- underlying balance if interest not accrued should increase by amount for msg.sender
    /// @custom:precondition token to borrow is either dUSDC or dDAI
    /// @custom:precondition amount is bound between [1, marketUnderlyingHeld() - totalReserves]
    /// @custom:precondition borrow is not paused
    /// @custom:precondition dtoken must be listed
    /// @custom:precondition user must not have a shortfall for respective token
    function borrow_should_succeed_accruing_interest(
        address dtoken,
        uint256 amount
    ) public {
        is_supported_dtoken(dtoken);
        check_price_feed();
        address underlying = DToken(dtoken).underlying();
        require(marketManager.borrowPaused(dtoken) != 2);
        uint256 upperBound = DToken(dtoken).marketUnderlyingHeld() -
            DToken(dtoken).totalReserves();
        amount = clampBetween(amount, 1, upperBound - 1);
        require(mint_and_approve(DToken(dtoken).underlying(), dtoken, amount));
        require(marketManager.isListed(dtoken));
        (bool borrowPossible, ) = address(marketManager).call(
            abi.encodeWithSignature(
                "canBorrow(address,address,uint256)",
                dtoken,
                address(this),
                amount
            )
        );
        require(borrowPossible);
        (uint32 lastTimestampUpdated, , uint256 compoundRate) = DToken(dtoken)
            .marketData();
        require(lastTimestampUpdated + compoundRate <= block.timestamp);

        uint256 preTotalBorrows = DToken(dtoken).totalBorrows();
        uint256 preUnderlyingBalance = IERC20(underlying).balanceOf(
            address(this)
        );

        try DToken(dtoken).borrow(amount) {
            // Interest is accrued
            //  TODO: determine how much interest should have accrued instead of just Gt.
            assertGte(
                DToken(dtoken).totalBorrows(),
                preTotalBorrows + amount,
                "DTOKEN - borrow postTotalBorrows failed = preTotalBorrows + amount"
            );
            uint256 postUnderlyingBalance = IERC20(underlying).balanceOf(
                address(this)
            );

            assertGte(
                postUnderlyingBalance,
                preUnderlyingBalance + amount,
                "DTOKEN - borrow postUnderlyingBalance failed = underlyingBalance + amount"
            );
            // TODO: Add check for _debtOf[account].principal
            // TODO: Add check for _debtOf[account].accountExchangeRate
            postedCollateralAt[dtoken] = block.timestamp;
        } catch {
            assertWithMsg(
                false,
                "DTOKEN - borrow should succeed with correct preconditions"
            );
        }
    }

    /// @custom:precondition the repay function  should succeed under correct preconditions
    function repay_should_succeed(address dtoken, uint256 amount) public {
        is_supported_dtoken(dtoken);
        uint256 accountDebt = DToken(dtoken).debtBalanceCached(address(this));
        address underlying = DToken(dtoken).underlying();
        require(mint_and_approve(underlying, dtoken, amount));
        require(marketManager.isListed(dtoken));
        try marketManager.canRepay(address(dtoken), address(this)) {} catch {
            return;
        }
        uint256 preTotalBorrows = DToken(dtoken).totalBorrows();
        uint256 preUnderlyingBalance = IERC20(underlying).balanceOf(
            address(this)
        );

        try DToken(dtoken).repay(amount) {
            assertEq(
                DToken(dtoken).totalBorrows(),
                preTotalBorrows - amount,
                "DTOKEN - repay postTotalBorrows failed = preTotalBorrows - amount"
            );
            uint256 postUnderlyingBalance = IERC20(underlying).balanceOf(
                address(this)
            );
            if (amount == 0) {
                assertEq(
                    postUnderlyingBalance,
                    preUnderlyingBalance - accountDebt,
                    "DTOKEN - repay with amount=0 should reduce underlying balance by accountDebt"
                );
            } else {
                assertEq(
                    postUnderlyingBalance,
                    preUnderlyingBalance - amount,
                    "DTOKEN - repay with amount>0 should reduce underlying balance by amount"
                );
            }
        } catch {
            assertWithMsg(
                false,
                "DTOKEN - repay should succeed with correct preconditions"
            );
        }
    }

    function repay_within_account_debt_should_succeed(
        address dtoken,
        uint256 amount
    ) public {
        is_supported_dtoken(dtoken);
        address underlying = DToken(dtoken).underlying();
        uint256 accountDebt = DToken(dtoken).debtBalanceCached(address(this));
        amount = clampBetween(amount, 0, accountDebt);
        require(mint_and_approve(underlying, dtoken, amount));
        require(marketManager.isListed(dtoken));
        try marketManager.canRepay(address(dtoken), address(this)) {} catch {
            return;
        }
        uint256 preTotalBorrows = DToken(dtoken).totalBorrows();
        uint256 preUnderlyingBalance = IERC20(underlying).balanceOf(
            address(this)
        );

        try DToken(dtoken).repay(amount) {
            assertEq(
                DToken(dtoken).totalBorrows(),
                preTotalBorrows - amount,
                "DTOKEN - repay postTotalBorrows failed = preTotalBorrows - amount"
            );
            uint256 postUnderlyingBalance = IERC20(underlying).balanceOf(
                address(this)
            );
            if (amount == 0) {
                assertEq(
                    postUnderlyingBalance,
                    preUnderlyingBalance - accountDebt,
                    "DTOKEN - repay with amount=0 should reduce underlying balance by accountDebt"
                );
            } else {
                assertEq(
                    postUnderlyingBalance,
                    preUnderlyingBalance - amount,
                    "DTOKEN - repay with amount>0 should reduce underlying balance by amount"
                );
            }
        } catch {
            assertWithMsg(
                false,
                "DTOKEN - repay should succeed with correct preconditions"
            );
        }
    }

    function liquidate(
        uint256 amount,
        address account,
        address dtoken,
        address collateralToken
    ) public {
        is_supported_dtoken(dtoken);
        require(account != msg.sender);
        require(marketManager.isListed(dtoken));
        require(
            DToken(dtoken).marketManager() ==
                DToken(collateralToken).marketManager()
        );
        require(IMToken(collateralToken).isCToken());
        require(marketManager.collateralPosted(collateralToken) > 0);
        require(marketManager.seizePaused() != 2);
        {
            // Clean this up
            (
                ,
                uint256 collRatio,
                uint256 collReqSoft,
                uint256 collReqHard,
                ,
                ,
                ,
                ,

            ) = marketManager.tokenData(dtoken);

            uint maxValue = amount * collReqSoft;
            uint256 minValue = amount * collReqHard;
            amount = clampBetween(amount, minValue, maxValue);
        }
        address underlying = DToken(dtoken).underlying();

        uint256 senderBalanceUnderlying = IERC20(underlying).balanceOf(
            msg.sender
        );
        uint256 preAccountCollateral = IERC20(collateralToken).balanceOf(
            msg.sender
        );
        (
            uint256 debtTokenRepaid,
            uint256 liquidatedCToken,
            uint256 cToken
        ) = marketManager.canLiquidateWithExecution(
                dtoken,
                collateralToken,
                account,
                amount,
                true
            );

        hevm.prank(msg.sender);
        DToken(dtoken).liquidate(account, IMToken(collateralToken));

        // TODO: successful postconditions (needs tweaking)
        assertWithMsg(
            IERC20(underlying).balanceOf(msg.sender) > senderBalanceUnderlying,
            "DTOKEN - liquidate received increase in underlying"
        );
        assertGt(
            IERC20(collateralToken).balanceOf(msg.sender),
            preAccountCollateral,
            "DTOKEN - liquidate received account collateral"
        );
    }
}
