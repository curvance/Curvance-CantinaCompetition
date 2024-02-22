pragma solidity 0.8.17;
import { FuzzMarketManager } from "tests/fuzzing/FuzzMarketManager.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";

contract FuzzDToken is FuzzMarketManager {
    constructor() {
        require(_mintAndApprove(address(usdc), address(cUSDC), 1000 ether));
        require(_mintAndApprove(address(dai), address(cDAI), 1000 ether));
        require(_mintAndApprove(address(usdc), address(dUSDC), 1000 ether));
        require(_mintAndApprove(address(dai), address(dDAI), 1000 ether));
    }

    /// @custom:property dtok-1 calling DToken.mint should succeed with correct preconditions
    /// @custom:property dtok-2 underlying balance for sender DToken should decrease by amount
    /// @custom:property dtok-3  balance should increase by `amount * WAD/exchangeRateCached()`
    /// @custom:property dtok-4 DToken totalSupply should increase by `amount * WAD/exchangeRateCached()`
    /// @custom:precondition amount bound between [1, uint256.max]
    function mint_should_actually_succeed(
        address dtoken,
        uint256 amount
    ) public {
        _isSupportedDToken(dtoken);
        require(gaugePool.startTime() < block.timestamp);
        _checkPriceFeed();
        (bool mintingPossible, ) = address(marketManager).call(
            abi.encodeWithSignature("canMint(address)", dtoken)
        );
        require(mintingPossible);
        address underlyingTokenAddress = DToken(dtoken).underlying();
        // amount = clampBetweenBoundsFromOne(lower, amount);
        amount = clampBetween(amount, 0, type(uint64).max);
        require(_mintAndApprove(underlyingTokenAddress, dtoken, amount));
        uint256 preUnderlyingBalance = IERC20(underlyingTokenAddress)
            .balanceOf(address(this));
        uint256 preDTokenBalance = DToken(dtoken).balanceOf(address(this));
        uint256 preDTokenTotalSupply = DToken(dtoken).totalSupply();
        uint256 er = DToken(dtoken).exchangeRateCached();

        try DToken(dtoken).mint(amount) {
            uint256 postDTokenBalance = DToken(dtoken).balanceOf(
                address(this)
            );
            uint256 new_er = DToken(dtoken).exchangeRateCached();

            uint256 adjustedNumberOfTokens = (amount * WAD) / new_er;
            uint256 postUnderlyingBalance = IERC20(underlyingTokenAddress)
                .balanceOf(address(this));

            assertEq(
                preUnderlyingBalance - amount,
                postUnderlyingBalance,
                "DTOK-2 mint should reduce underlying token balance"
            );

            assertEq(
                preDTokenBalance,
                postDTokenBalance - adjustedNumberOfTokens,
                "DTOK-3 mint should increase balanceOf[msg.sender] by (amount*WAD)/exchangeRate"
            );

            uint256 postDTokenTotalSupply = DToken(dtoken).totalSupply();

            assertEq(
                preDTokenTotalSupply,
                postDTokenTotalSupply - adjustedNumberOfTokens,
                "DTOK-4 mint should increase totalSupply"
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
            if (adjustedNumberOfTokens == 0) {
                assertEq(
                    errorSelector,
                    invalid_amount,
                    "DTOK-X if amount*WAD/er==0, gauge pool deposit should fail"
                );
            } else if (
                underlyingTokenSupplyOverflow ||
                dtokenSupplyOverflow ||
                balanceOverflow
            ) // if any of the above conditions are met, then expect a revert for overflow
            {
                assertEq(
                    errorSelector,
                    0,
                    "DTOK-X mint should revert if overflow"
                );
            } else {
                // DTOK-1
                assertWithMsg(
                    false,
                    "DTOK-1 mint should succeed with correct preconditions"
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
    /// @custom:limitation TODO missing check for increase in _debtOf[account].principal and  _debtOf[account].accountExchangeRate
    function borrow_should_succeed_not_accruing_interest(
        address dtoken,
        uint256 amount
    ) public {
        _isSupportedDToken(dtoken);
        _checkPriceFeed();
        address underlying = DToken(dtoken).underlying();
        require(marketManager.isListed(dtoken));
        require(marketManager.borrowPaused(dtoken) != 2);
        uint256 upperBound = DToken(dtoken).marketUnderlyingHeld() -
            DToken(dtoken).totalReserves() -
            42069; // TODO: constant
        amount = clampBetween(amount, 1, upperBound - 1);
        require(_mintAndApprove(DToken(dtoken).underlying(), dtoken, amount));
        (bool borrowPossible, ) = address(marketManager).call(
            abi.encodeWithSignature(
                "canBorrow(address,address,uint256)",
                dtoken,
                address(this),
                amount
            )
        );
        require(borrowPossible);
        (uint40 lastTimestampUpdated, , uint256 compoundRate) = DToken(dtoken)
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
                "DTOK-6 borrow postTotalBorrows failed = preTotalBorrows + amount"
            );
            uint256 postUnderlyingBalance = IERC20(underlying).balanceOf(
                address(this)
            );

            assertEq(
                postUnderlyingBalance,
                preUnderlyingBalance + amount,
                "DTOK-7 borrow postUnderlyingBalance failed = underlyingBalance + amount"
            );

            postedCollateralAt[dtoken] = block.timestamp;
        } catch {
            assertWithMsg(
                false,
                "DTOK-5 borrow should succeed with correct preconditions"
            );
        }
    }

    /// @custom:property dtok-8 borrow should succeed with correct preconditions
    /// @custom:property dtok-9 totalBorrows if interest has accrued should increase by amount after borrow is called
    /// @custom:property dtok-10 underlying balance if interest not accrued should increase by amount for msg.sender
    /// @custom:precondition token to borrow is either dUSDC or dDAI
    /// @custom:precondition amount is bound between [1, marketUnderlyingHeld() - totalReserves]
    /// @custom:precondition borrow is not paused
    /// @custom:precondition dtoken must be listed
    /// @custom:precondition user must not have a shortfall for respective token
    function borrow_should_succeed_accruing_interest(
        address dtoken,
        uint256 amount
    ) public {
        _isSupportedDToken(dtoken);
        _checkPriceFeed();
        address underlying = DToken(dtoken).underlying();
        require(marketManager.borrowPaused(dtoken) != 2);
        uint256 upperBound = DToken(dtoken).marketUnderlyingHeld() -
            DToken(dtoken).totalReserves() -
            42069;
        amount = clampBetween(amount, 1, upperBound - 1);
        require(_mintAndApprove(DToken(dtoken).underlying(), dtoken, amount));
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
        (uint40 lastTimestampUpdated, , uint256 compoundRate) = DToken(dtoken)
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
                "DTOK-9 borrow postTotalBorrows failed = preTotalBorrows + amount"
            );

            uint256 postUnderlyingBalance = IERC20(underlying).balanceOf(
                address(this)
            );
            assertGte(
                postUnderlyingBalance,
                preUnderlyingBalance + amount,
                "DTOK-10 borrow postUnderlyingBalance failed = underlyingBalance + amount"
            );
            // TODO: Add check for _debtOf[account].principal
            // TODO: Add check for _debtOf[account].accountExchangeRate
            postedCollateralAt[dtoken] = block.timestamp;
        } catch {
            assertWithMsg(
                false,
                "DTOK-8 borrow should succeed with correct preconditions"
            );
        }
    }

    /// @custom:precondition dtok-11 the repay function should fail with amount too large under correct preconditions
    function repay_should_fail_with_amount_too_large(
        address dtoken,
        uint256 amount
    ) public {
        _isSupportedDToken(dtoken);
        uint256 accountDebt = DToken(dtoken).debtBalanceCached(address(this));
        address underlying = DToken(dtoken).underlying();
        require(_mintAndApprove(underlying, dtoken, amount));
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
                "DTOK-11 repay more than accountDebt balance should fail"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            assertWithMsg(
                errorSelector == dtoken_excessive_value,
                "DTOK-11 repay more than accountDebt should have EXCESSIVE_VALUE error"
            );
        }
    }

    /// @custom:property dtok-12 repaying within account debt should succeed
    /// @custom:property dtok-13 repaying any amount should reduce totalborrows for dtoken
    /// @custom:property dtok-14 repay with amount=0 should reduce underlying balance by accountDebt
    /// @custom:property dtok-15 repay with amount!=0 should reduce underlying balance by provided amount
    function repay_within_account_debt_should_succeed(
        address dtoken,
        uint256 amount
    ) public {
        _isSupportedDToken(dtoken);
        address underlying = DToken(dtoken).underlying();
        uint256 accountDebt = DToken(dtoken).debtBalanceCached(address(this));
        amount = clampBetween(amount, 0, accountDebt);
        require(_mintAndApprove(underlying, dtoken, accountDebt));
        require(marketManager.isListed(dtoken));
        try marketManager.canRepay(address(dtoken), address(this)) {} catch {
            return;
        }
        uint256 preTotalBorrows = DToken(dtoken).totalBorrows();
        uint256 preUnderlyingBalance = IERC20(underlying).balanceOf(
            address(this)
        );
        (uint40 lastTimestampUpdated, , uint256 compoundRate) = DToken(dtoken)
            .marketData();
        uint256 old_er = DToken(dtoken).exchangeRateCached();

        try DToken(dtoken).repay(amount) {
            if (lastTimestampUpdated + compoundRate <= block.timestamp) {
                {
                    // TODO: pull interest calculation into a helper function to be used across logic
                    uint256 new_er = DToken(dtoken).exchangeRateCached();
                    uint256 er_diff = new_er > old_er
                        ? new_er - old_er
                        : old_er - new_er;
                    assertEq(
                        DToken(dtoken).totalBorrows(),
                        preTotalBorrows - amount - (er_diff) * accountDebt,
                        "DTOK-X repay postBorrows = (change in er)*amount"
                    );
                }
            } else {
                assertEq(
                    DToken(dtoken).totalBorrows(),
                    preTotalBorrows - amount,
                    "DTOK-13 repay postTotalBorrows failed = preTotalBorrows - amount"
                );
            }
            uint256 postUnderlyingBalance = IERC20(underlying).balanceOf(
                address(this)
            );
            if (amount == 0) {
                assertEq(
                    postUnderlyingBalance,
                    preUnderlyingBalance - accountDebt,
                    "DTOK-14 repay with amount=0 should reduce underlying balance by accountDebt"
                );
            } else {
                assertEq(
                    postUnderlyingBalance,
                    preUnderlyingBalance - amount,
                    "DTOK-15 repay with amount>0 should reduce underlying balance by amount"
                );
            }
            postedCollateralAt[dtoken] = block.timestamp;
        } catch {
            assertWithMsg(
                false,
                "DTOK-12 repay should succeed with correct preconditions"
            );
        }
    }

    // SOFT liquidation

    // by default, this should just liquidate the maximum amount, assuming nonexist liquidation
    /// @custom:precondition liquidating an account's maximum
    /// @custom:precondition dToken is supported
    /// @custom:precondition cToken is supported
    /// @custom:precondition market manager for dtoken and ctoken match
    /// @custom:precondition account has collateral posted for respective token
    /// @custom:precondition account is in "danger" of liquidation
    function liquidate_should_succeed_with_non_exact(uint256 amount) public {
        uint256 daiPrice = DAI_PRICE;
        uint256 usdcPrice = USDC_PRICE;
        require(marketManager.seizePaused() != 2);
        address account = address(this);
        address dtoken = address(dDAI);
        address collateralToken = address(cUSDC);
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
        amount = _boundLiquidateValues(debtToLiquidate, collateralToken);
        _preLiquidate(amount, DAI_PRICE, USDC_PRICE);

        _checkLiquidatePreconditions(account, dtoken, collateralToken);

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
                    "DTOK- liquidate: underlying msg.sender balance after liquidate = previous underlying + debt to liquidate"
                );
                assertEq(
                    IERC20(collateralToken).balanceOf(account) +
                        seizedForLiquidation +
                        seizedForProtocol,
                    preAccountCollateral,
                    "DTOK- liquidate: post account collateral token balance + tokens seized for liquidation + tokens seized by protocol = pre account collateral"
                );
            }
        }
    }

    /*

    // liquidateExact amount, with zero
    function liquidate_should_succeed_with_exact_with_zero(
        address account,
        address dtoken,
        address collateralToken
    ) public {
        setupLiquidations();
        _checkLiquidatePreconditions(account, dtoken, collateralToken);
        uint256 amount = 0;
        // Structured for non exact liquidations, debt amount to liquidate = max
        uint256 collateralPostedFor = _collateralPostedFor(
            address(collateralToken)
        );
        // amount = _boundLiquidateValues(collateralPostedFor, collateralToken);
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

        uint256 senderBalanceUnderlying = IERC20(underlyingDToken).balanceOf(
            msg.sender
        );
        uint256 preAccountCollateral = IERC20(collateralToken).balanceOf(
            account
        );

        // expect the above to fail
        try
            this.prankLiquidateExact(account, amount, dtoken, collateralToken)
        {} catch {
            assert(false);
        }
    }

    function prankLiquidateExact(
        address account,
        uint256 amount,
        address dtoken,
        address collateralToken
    ) external {
        hevm.prank(msg.sender);
        DToken(dtoken).liquidateExact(
            account,
            amount,
            IMToken(collateralToken)
        );
    }

    // liquidateExact amount, with specified amount
    function liquidate_should_succeed_with_exact(
        uint256 amount,
        address account,
        address dtoken,
        address collateralToken
    ) public {
        setupLiquidations();
        _checkLiquidatePreconditions(account, dtoken, collateralToken);
        // Structured for non exact liquidations, debt amount to liquidate = max
        uint256 collateralPostedFor = _collateralPostedFor(
            address(collateralToken)
        );
        amount = _boundLiquidateValues(collateralPostedFor, collateralToken);
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
                DToken(dtoken).liquidateExact(
                    account,
                    amount,
                    IMToken(collateralToken)
                );

                assertEq(
                    IERC20(underlyingDToken).balanceOf(msg.sender),
                    senderBalanceUnderlying + debtToLiquidate,
                    "DTOK- liquidate: underlying msg.sender balance after liquidate = previous underlying + debt to liquidate"
                );
                assertEq(
                    IERC20(collateralToken).balanceOf(account) +
                        seizedForLiquidation +
                        seizedForProtocol,
                    preAccountCollateral,
                    "DTOK- liquidate: post account collateral token balance + tokens seized for liquidation + tokens seized by protocol = pre account collateral"
                );
            }
        }
    }
    */
}
