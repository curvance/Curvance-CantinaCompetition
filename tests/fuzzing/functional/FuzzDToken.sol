pragma solidity 0.8.17;
import { FuzzMarketManager } from "tests/fuzzing/FuzzMarketManager.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
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
        amount = clampBetween(amount, 1, type(uint64).max);
        require(_mintAndApprove(underlyingTokenAddress, dtoken, amount));
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
        _isSupportedDToken(dtoken);
        _checkPriceFeed();
        address underlying = DToken(dtoken).underlying();
        require(marketManager.isListed(dtoken));
        require(marketManager.borrowPaused(dtoken) != 2);
        uint256 upperBound = DToken(dtoken).marketUnderlyingHeld() -
            DToken(dtoken).totalReserves();
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
        _isSupportedDToken(dtoken);
        _checkPriceFeed();
        address underlying = DToken(dtoken).underlying();
        require(marketManager.borrowPaused(dtoken) != 2);
        uint256 upperBound = DToken(dtoken).marketUnderlyingHeld() -
            DToken(dtoken).totalReserves();
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
        _isSupportedDToken(dtoken);
        address underlying = DToken(dtoken).underlying();
        uint256 accountDebt = DToken(dtoken).debtBalanceCached(address(this));
        amount = clampBetween(amount, 0, accountDebt);
        require(_mintAndApprove(underlying, dtoken, amount));
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

    function preLiquidate(
        uint amount,
        uint256 daiPrice,
        uint256 usdcPrice
    ) private {
        hevm.warp(block.timestamp + marketManager.MIN_HOLD_PERIOD());
        address liquidator = msg.sender;

        hevm.prank(liquidator);
        dai.mint(amount * WAD);

        hevm.prank(liquidator);
        dai.approve(address(dDAI), amount * WAD);

        mockDaiFeed.setMockAnswer(int256(daiPrice));
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        chainlinkDaiUsd.updateRoundData(
            0,
            int256(daiPrice),
            block.timestamp,
            block.timestamp
        );
        PriceReturnData memory daiData = chainlinkAdaptor.getPrice(
            address(dDAI),
            true,
            false
        );
        require(!daiData.hadError);

        emit LogString("set chainlink round data for usdc");
        chainlinkUsdcUsd.updateRoundData(
            0,
            int256(usdcPrice),
            block.timestamp,
            block.timestamp
        );
        mockUsdcFeed.setMockAnswer(int256(usdcPrice));
        mockUsdcFeed.setMockUpdatedAt(block.timestamp);

        PriceReturnData memory usdcData = chainlinkAdaptor.getPrice(
            address(cUSDC),
            true,
            false
        );
        require(!usdcData.hadError);
    }

    // gets prices needed to liquidate
    function try_to_liquidate(uint256 amount) public {
        // ensure price feeds are up to date before updating collateral token and listing
        _checkPriceFeed();
        {
            (
                bool is_cusdc_listed,
                uint256 cusdc_cr,
                ,
                ,
                ,
                ,
                ,
                ,

            ) = marketManager.tokenData(address(cUSDC));
            // if C_USDC is not listed, make sure to list it
            if (!is_cusdc_listed) {
                list_token_should_succeed(address(cUSDC));
            }
            // If collateral ratio of CUSDC is 0, update the market manager to increase collateral ratio
            if (cusdc_cr == 0) {
                updateCollateralToken_should_succeed(
                    address(cUSDC),
                    1000e18,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0
                );
            }

            bool hasUsdcPosition = _hasPosition(address(cUSDC));
            if (!hasUsdcPosition) {
                post_collateral_should_succeed(address(cUSDC), WAD + 1, false);
            }
        }
        {
            (bool is_ddai_listed, , , , , , , , ) = marketManager.tokenData(
                address(dDAI)
            );
            if (!is_ddai_listed) {
                list_token_should_succeed(address(dDAI));
            }
        }

        uint256 upperBound = DToken(address(dDAI)).marketUnderlyingHeld() -
            DToken(dDAI).totalReserves();
        amount = clampBetween(amount, 1, upperBound - 1);
        uint256 daiPrice = 1e20;
        // daiPrice = clampBetween(daiPrice, 1, type(uint256).max);
        uint256 usdcPrice = 1e7;
        // usdcPrice = clampBetween(usdcPrice, 1, type(uint256).max);

        dDAI.borrow(amount);

        // this will update price feeds values
        preLiquidate(amount, daiPrice, usdcPrice);
        (
            uint256 lfactor,
            uint256 debtTokenPrice,
            uint256 collatTokenPrice
        ) = marketManager.LiquidationStatusOf(
                address(this),
                address(dDAI),
                address(cUSDC)
            );
        emit LogUint256("lfactor", lfactor);
        (
            uint256 debt,
            uint256 collateralLiquidation,
            uint256 collateralProtocol
        ) = marketManager.canLiquidate(
                address(dDAI),
                address(cUSDC),
                address(this),
                amount,
                false
            );

        emit LogUint256("debt:", debt);
        emit LogUint256("collateral liquidation", collateralLiquidation);
        emit LogUint256("collateral protocol", collateralProtocol);

        _canLiquidateAccount(address(this));

        hevm.prank(msg.sender);
        try this.prankLiquidateAccount(address(this)) {} catch {
            assert(false);
        }
    }

    function _canLiquidateAccount(address account) private {
        (uint256 accountCollateral, , uint256 accountDebt) = marketManager
            .statusOf(account);
        emit LogUint256("accountCollateral", accountCollateral);
        emit LogUint256("accountDebt", accountDebt);
        require(accountCollateral < accountDebt);
    }

    function liquidateAccount_should_succeed(uint256 amount) public {
        uint256 daiPrice = 1e24;
        uint256 usdcPrice = 1e7;
        require(marketManager.seizePaused() != 2);
        preLiquidate(amount, daiPrice, usdcPrice);
        address account = address(this);
        _canLiquidateAccount(account);

        IMToken[] memory assets = marketManager.assetsOf(account);

        hevm.prank(msg.sender);
        marketManager.liquidateAccount(account);

        emit LogAddress("msg.sender", msg.sender);
        for (uint256 i = 0; i < assets.length; i++) {
            (bool hasPosition, uint256 balanceOf, ) = marketManager
                .tokenDataOf(address(this), address(assets[i]));
            assertWithMsg(
                !hasPosition,
                "marketManager - liquidations should remove user's position for their assets"
            );
            assertEq(
                balanceOf,
                0,
                "marketManager - liquidateAccount should zero out balanceOf"
            );
        }
        assert(false);
    }

    /*    

    function liquidateAccount_should_fail_if_account_not_flagged(
        uint256 amount,
        uint256 daiPrice,
        uint256 usdcPrice
    ) public {
        require(marketManager.seizePaused() != 2);
        preLiquidate(amount, daiPrice, usdcPrice);
        address account = address(this);

        _canLiquidateAccount(account);

        try this.prankLiquidateAccount(account) {
            assertWithMsg(
                false,
                "marketManager - liquidateAccount should fail if account is not flagged for liquidations"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertEq(
                errorSelector,
                marketManager_noLiquidationAvailableSelectorHash,
                "marketManager - liquidateAccount should fail with NoLiquidationAvailable if not flagged"
            );
        }
    }

    function liquidateAccount_should_fail_if_self_account(
        uint256 amount,
        uint256 daiPrice,
        uint256 usdcPrice
    ) public {
        require(marketManager.seizePaused() != 2);
        preLiquidate(amount, daiPrice, usdcPrice);
        address account = address(msg.sender);
        _canLiquidateAccount(account);

        try this.prankLiquidateAccount(account) {
            assertWithMsg(
                false,
                "marketManager - liquidateAccount should fail if user attempts to liquidate themselves"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertEq(
                errorSelector,
                marketManager_unauthorizedSelectorHash,
                "marketManager - liquidateAccount should fail with Unauthorized"
            );
        }
    }

    function liquidateAccount_should_fail_if_seize_paused(
        uint256 amount,
        uint256 daiPrice,
        uint256 usdcPrice
    ) public {
        require(marketManager.seizePaused() == 2);
        preLiquidate(amount, daiPrice, usdcPrice);
        address account = address(msg.sender);
        _canLiquidateAccount(account);

        try this.prankLiquidateAccount(account) {
            assertWithMsg(
                false,
                "marketManager - liquidateAccount should fail if user attempts to liquidate themselves"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertEq(
                errorSelector,
                marketManager_pausedSelectorHash,
                "marketManager - liquidateAccount should fail with PAUSED when seize is paused"
            );
        }
    }

    */

    // SOFT liquidation

    // by default, this should just liquidate the maximum amount, assuming nonexist liquidation
    /// @custom:precondition liquidating an account's maximum
    /// @custom:precondition dToken is supported
    /// @custom:precondition cToken is supported
    /// @custom:precondition market manager for dtoken and ctoken match
    /// @custom:precondition account has collateral posted for respective token
    /// @custom:precondition account is in "danger" of liquidation
    function liquidate_should_succeed_with_non_exact() public {
        // TODO: these should be dynamic after liquidations run through thoroughly
        address account = address(this);
        address dtoken = address(dDAI);
        address collateralToken = address(cUSDC);

        hevm.warp(block.timestamp + 5 weeks);
        borrow_should_succeed_not_accruing_interest(address(dDAI), 1000e6);
        // TODO: make this a dynamic number, that requires that the account would be marked "flagged for liquidation"
        mockDaiFeed.setMockAnswer(1000e8);

        _checkLiquidatePreconditions(account, dtoken, collateralToken);
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
        uint256 amount = _boundLiquidateValues(
            debtToLiquidate,
            collateralToken
        );

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

    function prankLiquidateAccount(address account) public {
        hevm.prank(msg.sender);
        marketManager.liquidateAccount(account);
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
    */

    // Helper functions

    function _checkLiquidatePreconditions(
        address account,
        address dtoken,
        address collateralToken
    ) private {
        _isSupportedDToken(dtoken);
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

    function _boundLiquidateValues(
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
