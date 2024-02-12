pragma solidity 0.8.17;
import { FuzzMarketManager } from "tests/fuzzing/FuzzMarketManager.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";


contract FuzzDToken is FuzzMarketManager {
    /*
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
            
            // if the underlying token mint totalSupply calculation expected to overflow, revert 
            bool underlyingTokenSupplyOverflow = doesOverflow(
                preUnderlyingBalance + amount,
                preUnderlyingBalance
            );
            // if the dtoken token mint totalSupply calculation expected to overflow, revert 
            bool dtokenSupplyOverflow = doesOverflow(
                preDTokenTotalSupply + adjustedNumberOfTokens,
                preDTokenTotalSupply
            );
            // if the balance calculation expected to overflow, revert 
            bool balanceOverflow = doesOverflow(
                preDTokenBalance + adjustedNumberOfTokens,
                preDTokenBalance
            );

            // if any of the above conditions are met, then expect a revert for overflow
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

    /// @custom:precondition the repay function should fail with amount too large under correct preconditions
    function repay_should_fail_with_amount_too_large(
        address dtoken,
        uint256 amount
    ) public {
        is_supported_dtoken(dtoken);
        uint256 accountDebt = DToken(dtoken).debtBalanceCached(address(this));
        address underlying = DToken(dtoken).underlying();
        require(mint_and_approve(underlying, dtoken, amount));
        require(marketManager.isListed(dtoken));
        amount = clampBetween(amount, accountDebt + 1, type(uint256).max);
        try marketManager.canRepay(address(dtoken), address(this)) {} catch {
            return;
        }
        uint256 preTotalBorrows = DToken(dtoken).totalBorrows();
        uint256 preUnderlyingBalance = IERC20(underlying).balanceOf(
            address(this)
        );

        try DToken(dtoken).repay(amount) {
            assertWithMsg(
                false,
                "DTOKEN - repay more than accountDebt balance should fail"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                false,
                "DTOKEN - repay more than accountDebt should have INSERT_SPECIFIC_ERROR"
            );
            // assertEq(errorSelector,0,"");
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
    */

    function setupLiquidations() public {
        // hevm.warp(block.timestamp + 4 weeks);

        DToken(dUSDC).borrow(1 ether);
        DToken(dDAI).borrow(1 ether);
    }

    // by default, this should just liquidate the maximum amount, assuming nonexist liquidation
    /// @custom:precondition liquidating an account's maximum 
    /// @custom:precondition dToken is supported 
    /// @custom:precondition cToken is supported 
    /// @custom:precondition market manager for dtoken and ctoken match 
    /// @custom:precondition account has collateral posted for respective token 
    /// @custom:precondition account is in "danger" of liquidation 
    function liquidate_should_succeed_with_non_exact(
        address account,
        address dtoken,
        address collateralToken
    ) public {
        setupLiquidations();
        _check_liquidate_preconditions(
            account,
            dtoken,
            collateralToken
        );
        // Structured for non exact liquidations, debt amount to liquidate = max 
        (
            uint256 debtToLiquidate,
            uint256 seizedForLiquidation,
            uint256 seizedForProtocol
        ) = marketManager.canLiquidate(
                dtoken,
                collateralToken,
                account,
                0, // 0 does not represent anything here, when the liquidateExact is false 
                false
            );
        uint256 amount = _bound_liquidate_values(debtToLiquidate, collateralToken);

        {
            address underlyingDToken = DToken(dtoken).underlying();

            {
                uint256 senderBalanceUnderlying = IERC20(underlyingDToken)
                    .balanceOf(msg.sender);
                uint256 preAccountCollateral = IERC20(collateralToken)
                    .balanceOf(account);

                hevm.prank(msg.sender);
                DToken(dtoken).liquidate(account, IMToken(collateralToken));

                assertEq(
                    IERC20(underlyingDToken).balanceOf(msg.sender),
                    senderBalanceUnderlying + debtToLiquidate,
                    "DTOKEN - liquidate: underlying msg.sender balance after liquidate = previous underlying + debt to liquidate"
                );
                assertEq(
                    IERC20(collateralToken).balanceOf(account) +
                        seizedForLiquidation +
                        seizedForProtocol,
                    preAccountCollateral,
                    "DTOKEN - liquidate: post account collateral token balance + tokens seized for liquidation + tokens seized by protocol = pre account collateral"
                );
            }
        }
    }

    // liquidateExact amount, with zero
    function liquidate_should_succeed_with_exact_with_zero(
        address account,
        address dtoken,
        address collateralToken
    ) public {
        setupLiquidations();
        _check_liquidate_preconditions(
            account,
            dtoken,
            collateralToken
        );
        uint256 amount = 0;
        // Structured for non exact liquidations, debt amount to liquidate = max 
        uint256 collateralPostedFor = _collateralPostedFor(address(collateralToken));
        // amount = _bound_liquidate_values(collateralPostedFor, collateralToken);
        (
            uint256 debtToLiquidate,
            uint256 seizedForLiquidation,
            uint256 seizedForProtocol
        ) = marketManager.canLiquidate(
                dtoken,
                collateralToken,
                account,
                0,
                true
            );

        
        address underlyingDToken = DToken(dtoken).underlying();

    
        uint256 senderBalanceUnderlying = IERC20(underlyingDToken)
            .balanceOf(msg.sender);
        uint256 preAccountCollateral = IERC20(collateralToken)
            .balanceOf(account);

        // expect the above to fail 
        try this.prankLiquidateExact(account, amount, dtoken, collateralToken) {

        } catch {
            assert(false);
        }

        
    }        
function prankLiquidateExact(address account, uint256 amount, address dtoken, address collateralToken) external {
        hevm.prank(msg.sender);
        DToken(dtoken).liquidateExact(account, amount, IMToken(collateralToken));
} 

    // liquidateExact amount, with specified amount
    function liquidate_should_succeed_with_exact(
        uint256 amount,
        address account,
        address dtoken,
        address collateralToken
    ) public {
        setupLiquidations();
        _check_liquidate_preconditions(
            account,
            dtoken,
            collateralToken
        );
        // Structured for non exact liquidations, debt amount to liquidate = max 
        uint256 collateralPostedFor = _collateralPostedFor(address(collateralToken));
        amount = _bound_liquidate_values(collateralPostedFor, collateralToken);
        (
            uint256 debtToLiquidate,
            uint256 seizedForLiquidation,
            uint256 seizedForProtocol
        ) = marketManager.canLiquidate(
                dtoken,
                collateralToken,
                account,
                amount,
                true
            );

        {
            address underlyingDToken = DToken(dtoken).underlying();

            {
                uint256 senderBalanceUnderlying = IERC20(underlyingDToken)
                    .balanceOf(msg.sender);
                uint256 preAccountCollateral = IERC20(collateralToken)
                    .balanceOf(account);

                hevm.prank(msg.sender);
                DToken(dtoken).liquidateExact(account, amount, IMToken(collateralToken));

                assertEq(
                    IERC20(underlyingDToken).balanceOf(msg.sender),
                    senderBalanceUnderlying + debtToLiquidate,
                    "DTOKEN - liquidate: underlying msg.sender balance after liquidate = previous underlying + debt to liquidate"
                );
                assertEq(
                    IERC20(collateralToken).balanceOf(account) +
                        seizedForLiquidation +
                        seizedForProtocol,
                    preAccountCollateral,
                    "DTOKEN - liquidate: post account collateral token balance + tokens seized for liquidation + tokens seized by protocol = pre account collateral"
                );
            }
        }
    }    

    // Helper functions

    function _check_liquidate_preconditions(
        address account,
        address dtoken,
        address collateralToken
    ) private {
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
        (
            uint256 lfactor,
            uint256 debtTokenPrice,
            uint256 collatTokenPrice
        ) = marketManager.LiquidationStatusOf(
                account,
                dtoken,
                collateralToken
            );
        require(lfactor > 0);
    }

    function _bound_liquidate_values(
        uint256 amount,
        address collateralToken
    ) private returns (uint256 clampedAmount) {
        (
            ,
            uint256 collRatio,
            uint256 collReqSoft,
            uint256 collReqHard,
            uint256 liqBaseIncentive,
            uint256 liqCurve,
            uint256 liqFee,
            uint256 baseCFactor,
            uint256 cFactorCurve
        ) = marketManager.tokenData(address(collateralToken));
        require(collRatio > 0);
        uint256 maxValue = amount * collReqSoft;
        uint256 minValue = amount * collReqHard;
        emit LogUint256("min", minValue);
        emit LogUint256("max", maxValue);
        clampedAmount = clampBetween(amount, minValue, maxValue);
    }
}
