pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract FuzzMarketManager is StatefulBaseMarket {
    mapping(address => bool) setCollateralValues;
    mapping(address => bool) collateralCapsUpdated;
    mapping(address => bool) postedCollateral;
    mapping(address => bool) isCollateralRatioZero;

    constructor() {
        SafeTransferLib.safeApprove(
            _USDC_ADDRESS,
            address(dUSDC),
            type(uint256).max
        );
        SafeTransferLib.safeApprove(
            _DAI_ADDRESS,
            address(dDAI),
            type(uint256).max
        );
        SafeTransferLib.safeApprove(
            _USDC_ADDRESS,
            address(cUSDC),
            type(uint256).max
        );
        SafeTransferLib.safeApprove(
            _DAI_ADDRESS,
            address(cDAI),
            type(uint256).max
        );
    }

    /// @custom:property lend-1 Once a new token is listed, marketManager.isListed(mtoken) should return true.
    /// @custom:precondition mtoken must not already be listed
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    function list_token_should_succeed(address mtoken) public {
        uint256 amount = 42069;
        // require the token is not already listed into the marketManager
        require(!marketManager.isListed(mtoken));

        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        address underlyingAddress = MockCToken(mtoken).underlying();
        IERC20 underlying = IERC20(underlyingAddress);

        try marketManager.listToken(mtoken) {
            assertWithMsg(
                marketManager.isListed(mtoken),
                "MARKET MANAGER - marketManager.listToken() should succeed"
            );
        } catch {
            assertWithMsg(false, "MARKET MANAGER - failed to list token");
        }
    }

    /// @custom:property lend-2 A token already added to the MarketManager cannot be added again
    /// @custom:precondition mtoken must already be listed
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    function list_token_should_fail_if_already_listed(address mtoken) public {
        uint256 amount = 42069;
        // require the token is not already listed into the marketManager
        require(marketManager.isListed(mtoken));

        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        address underlyingAddress = MockCToken(mtoken).underlying();
        IERC20 underlying = IERC20(underlyingAddress);

        try marketManager.listToken(mtoken) {
            assertWithMsg(
                false,
                "MARKET MANAGER - listToken for duplicate token should not be possible"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_tokenAlreadyListedSelectorHash,
                "MARKET MANAGER - listToken() expected TokenAlreadyListed selector hash on failure"
            );
        }
    }

    /// @custom:property lend-3 – A user can deposit into an mtoken provided that they have the underlying asset, and they have approved the mtoken contract.
    /// @custom:property lend-4 – When depositing assets into the mtoken, the wrapped token balance for the user should increase.
    /// @custom:property lend-29 If convertToShares overflows, deposit should revert
    /// @custom:property lend-30 If totalAssets+amount overflows, deposit should revert
    /// @custom:property lend-31 If oracle returns price <0, deposit should revert
    /// @custom:precondition GaugePool must have been started before block.timestamp
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    /// @custom:precondition mtoken must be listed in MarketManager
    /// @custom:precondition minting must not be paused
    function c_token_deposit(
        address mtoken,
        uint256 amount,
        bool lower
    ) public {
        require(gaugePool.startTime() < block.timestamp);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        if (!marketManager.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(marketManager.mintPaused(mtoken) != 2);

        address underlyingAddress = MockCToken(mtoken).underlying();
        // mint ME enough tokens to cover deposit
        try MockToken(underlyingAddress).mint(amount) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - mint underlying amount should succeed before deposit"
            );
        }
        // approve sufficient underlying tokens prior to calling deposit
        try MockToken(underlyingAddress).approve(mtoken, amount) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - approve underlying amount should succeed before deposit"
            );
        }
        uint256 preCTokenBalanceThis = MockCToken(mtoken).balanceOf(
            address(this)
        );

        // This step should mint associated shares for the user
        try MockCToken(mtoken).deposit(amount, address(this)) {
            uint256 postCTokenBalanceThis = MockCToken(mtoken).balanceOf(
                address(this)
            );

            assertLt(
                preCTokenBalanceThis,
                postCTokenBalanceThis,
                "MARKET MANAGER - pre and post ctoken balance should increase"
            );
        } catch (bytes memory revertData) {
            emit LogAddress("msg.sender", msg.sender);
            uint256 errorSelector = extractErrorSelector(revertData);

            try MockCToken(mtoken).convertToShares(amount) {} catch (
                bytes memory convertSharesData
            ) {
                uint256 convertSharesError = extractErrorSelector(
                    convertSharesData
                );
                // CTokenBase._convertToShares will revert when `mulDivDown` overflows with `revert(0,0)
                if (convertSharesError == 0) {
                    convertToSharesOverflow = true;
                }
            }

            bool assetCalc = doesOverflow(
                preTotalAssets + amount,
                preTotalAssets
            ) ||
                doesOverflow(
                    preCTokenBalanceThis + amount,
                    preCTokenBalanceThis
                );
            // LEND-31
            bool isPriceNegative;
            if (mtoken == address(cDAI)) {
                isPriceNegative = chainlinkDaiUsd.latestAnswer() < 0;
            } else {
                isPriceNegative = chainlinkUsdcUsd.latestAnswer() < 0;
            }
            // LEND-29, LEND-30
            if (convertToSharesOverflow || assetCalc) {
                assertEq(
                    errorSelector,
                    0,
                    "MARKET MANAGER - expected mtoken.deposit() to revert with overflow"
                );
            } else {
                // LEND-3
                assertWithMsg(
                    false,
                    "MARKET MANAGER - expected mtoken.deposit() to be successful"
                );
            }
        }
    }

    function check_price_divergence(
        address mtoken
    ) private returns (bool divergenceTooLarge, bool priceError) {
        (uint256 lowerPrice, uint lowError) = OracleRouter(oracleRouter)
            .getPrice(mtoken, true, true);
        (uint256 higherPrice, uint highError) = OracleRouter(oracleRouter)
            .getPrice(mtoken, true, false);

        priceError = lowError == 2 || highError == 2;

        if (
            higherPrice - lowerPrice >
            OracleRouter(oracleRouter).badSourceDivergenceFlag()
        ) {
            divergenceTooLarge = true;
        }
    }

    /// @custom:property lend-5 – Calling updateCollateralToken with variables in correct bounds should succeed.
    /// @custom:precondition price feed must be recent
    /// @custom:precondition price feed must be setup
    /// @custom:precondition address(this) must have dao permissions
    /// @custom:precondition cap is bound between [1, uint256.max], inclusive
    /// @custom:precondition mtoken must be listed in the MarketManager
    /// @custom:precondition get_safe_update_collateral_bounds must be in correct bounds
    function updateCollateralToken_should_succeed(
        address mtoken,
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor
    ) public {
        require(feedsSetup);
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(marketManager.isListed(mtoken));
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));

        (bool divergenceTooLarge, bool priceError) = check_price_divergence(
            mtoken
        );

        {
            check_price_feed();
            get_safe_update_collateral_bounds(
                collRatio,
                collReqSoft,
                collReqHard,
                liqIncSoft,
                liqIncHard,
                liqFee,
                baseCFactor
            );
            if (safeBounds.collRatio == 0) {
                isCollateralRatioZero[mtoken] = true;
            }
        }
        try
            marketManager.updateCollateralToken(
                IMToken(address(mtoken)),
                safeBounds.collRatio,
                safeBounds.collReqSoft,
                safeBounds.collReqHard,
                safeBounds.liqIncSoft,
                safeBounds.liqIncHard,
                safeBounds.liqFee,
                safeBounds.baseCFactor
            )
        {
            setCollateralValues[mtoken] = true;
        } catch (bytes memory revertData) {
            {
                uint256 errorSelector = extractErrorSelector(revertData);

                if (divergenceTooLarge || priceError) {
                    assertWithMsg(
                        errorSelector == marketmanager_priceErrorSelectorHash,
                        "MARKET MANAGER - expected updateCollateralToken to fail if price diverge too much"
                    );
                }

                // LEND-5
                assertWithMsg(
                    false,
                    "MARKET MANAGER - updateCollateralToken should succeed"
                );
            }
        }
    }

    /// @custom:property lend-6 – Calling setCTokenCollateralCaps should increase the globally set the collateral caps to the cap provided
    /// @custom:property lend-7 Setting collateral caps for a token given permissions and collateral values being set should succeed.
    /// @custom:precondition address(this) has dao permissions
    /// @custom:precondition mtoken is a C token
    /// @custom:precondition collateral values for mtoken must be set
    /// @custom:precondition cap is bound between [0, uint256.max]
    function setCToken_should_succeed(address mtoken, uint256 cap) public {
        require(IMToken(mtoken).isCToken());
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(setCollateralValues[mtoken]);
        require(!isCollateralRatioZero[mtoken]);

        check_price_feed();

        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature(
                "setCTokenCollateralCaps(address[],uint256[])",
                tokens,
                caps
            )
        );

        if (success) {
            // LEND-6
            assertEq(
                marketManager.collateralCaps(mtoken),
                cap,
                "MARKET MANAGER - collateral caps for token should be >=0"
            );
        } else {
            // LEND-7
            assertWithMsg(
                false,
                "MARKET MANAGER - expected setCTokenCollateralCaps to succeed"
            );
        }
    }

    /// @custom:property lend-8 – updateCollateralToken should revert if the price feed is out of date
    /// @custom:precondition price feed is out of date
    /// @custom:precondition cap is bound between [1, uint256.max], inclusive
    /// @custom:precondition mtoken must be listed in MarketManager
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    function updateCollateralToken_should_revert_if_price_feed_out_of_date(
        address mtoken,
        uint256 cap
    ) public {
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        require(block.timestamp - lastRoundUpdate <= 24 hours);
        require(feedsSetup);
        require(centralRegistry.hasDaoPermissions(address(this)));
        if (!marketManager.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));

        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        // adjust the following to acount for dynamic numbers here instead
        try
            marketManager.updateCollateralToken(
                IMToken(address(mtoken)),
                7000,
                3000,
                3000,
                2000,
                2000,
                100,
                1000
            )
        {} catch {
            assertWithMsg(
                false,
                "MARKET MANAGER - updateCollateralToken should not have succeeded with out of date price feeds"
            );
        } catch {}
    }

    /// @custom:property lend-9 After collateral is posted, the user’s collateral posted position for the respective asset should increase.
    /// @custom:property lend-10 After collateral is posted, calling hasPosition on the user’s mtoken should return true.
    /// @custom:property lend-11 After collateral is posted, the global collateral for the mtoken should increase by the amount posted.
    /// @custom:property lend-12 When price feed is up to date, address(this) has mtoken, tokens are bound correctly, and caller is correct, the  postCollateral call should succeed.
    /// @custom:precondition price feed is up to date
    /// @custom:precondition address(this) must have a balance of mtoken
    /// @custom:precondition `tokens` to be posted is bound between [1, mtoken balance], inclusive
    /// @custom:precondition msg.sender for postCollateral = address(this)
    function post_collateral_should_succeed(
        address mtoken,
        uint256 tokens,
        bool lower
    ) public {
        require(collateralCapsUpdated[mtoken]);
        check_price_feed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(
                mtoken,
                tokens * IMToken(mtoken).decimals(),
                lower
            );
        }

        try lendtroller.setCTokenCollateralCaps(tokens, caps) {
            assertGt(
                lendtroller.collateralCaps(mtoken),
                0,
                "LENDTROLLER - collateral caps for token should be >0"
            );
        } catch {
            assertWithMsg(
                false,
                "LENDTROLLER - expected setCTokenCollateralCaps to succeed"
            );
        }
    }

    function post_collateral_should_succeed(
        address mtoken,
        uint256 tokens
    ) public {
        // require gauge pool has been started
        require(gaugePool.startTime() < block.timestamp);
        require(feedsSetup);
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        uint256 mtokenBalance = MockCToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = marketManager.collateralPostedFor(
            mtoken,
            address(this)
        );
        uint256 collateralCaps = marketManager.collateralCaps(mtoken);

        uint256 oldCollateralForToken = marketManager.collateralPosted(mtoken);
        if (
            mtokenBalance - oldCollateralForUser >
            collateralCaps - oldCollateralForToken
        ) {
            oldCollateral = accountCollat;
        } catch {
            oldCollateral = 0;
        }

        uint256 min;
        uint256 max;
        if (oldCollateral > mtokenBalance) {
            min = mtokenBalance;
            max = oldCollateral;
        } else {
            min = oldCollateral;
            max = mtokenBalance;
        }

        {
            (bool success, bytes memory revertData) = address(marketManager)
                .call(
                    abi.encodeWithSignature(
                        "postCollateral(address,address,uint256)",
                        address(this),
                        mtoken,
                        tokens
                    )
                );
            if (!success) {
                uint256 errorSelector = extractErrorSelector(revertData);
                emit LogUint256("error selector: ", errorSelector);
                // LEND-12
                assertWithMsg(
                    false,
                    "MARKET MANAGER - expected postCollateral to pass with @precondition"
                );
            }
            // ensure account collateral has increased by # of tokens
            uint256 newCollateralForUser = marketManager.collateralPostedFor(
                mtoken,
                address(this)
            );

            uint256 mtokenExchange = MockCToken(mtoken).exchangeRateSafe();
            // LEND-9
            assertEq(
                (newCollateralForUser) * mtokenExchange,
                (oldCollateralForUser + tokens) * mtokenExchange,
                "MARKET MANAGER - new collateral must collateral+tokens"
            );
            // LEND-10
            assertWithMsg(
                marketManager.hasPosition(mtoken, address(this)),
                "MARKET MANAGER - addr(this) must have position after posting"
            );
            // ensure collateralPosted increases by tokens
            uint256 newCollateralForToken = marketManager.collateralPosted(
                mtoken
            );
            // LEND-11
            assertEq(
                newCollateralForToken,
                oldCollateralForToken + tokens,
                "MARKET MANAGER - global collateral posted should increase"
            );
        }
        tokens = clampBetween(tokens, min, max);
        uint256 oldCollateralPosted = lendtroller.collateralPosted(mtoken);

    /// @custom:property lend-13 – Trying to post too much collateral should revert.
    /// @custom:precondition collateral caps for the token are >0
    /// @custom:precondition price feed must be out of date
    /// @custom:precondition user must have mtoken balance
    /// @custom:precondition tokens is bound between [mtokenBalance - existingCollateral+1, uint256.max]
    function post_collateral_should_fail_too_many_tokens(
        address mtoken,
        uint256 tokens,
        bool lower
    ) public {
        require(collateralCapsUpdated[mtoken]);
        check_price_feed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(
                mtoken,
                tokens * IMToken(mtoken).decimals(),
                lower
            );
        }
        uint256 mtokenBalance = IMToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = marketManager.collateralPostedFor(
            mtoken,
            address(this)
        );

        // collateralPosted + tokens <= mtoken.balanceOf(address(this))
        // tokens <= mtoken.balanceOf(address(this)) - collateralPosted
        tokens = clampBetween(
            tokens,
            mtokenBalance - oldCollateralForUser + 1,
            type(uint256).max
        );

        uint256 oldCollateralForToken = marketManager.collateralPosted(mtoken);

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature(
                "postCollateral(address,address,uint256)",
                address(this),
                mtoken,
                tokens
            )
        );
        if (!success) {
            assertWithMsg(
                false,
                "LENDTROLLER - expected postCollateral to pass with preconditions"
            );
        }
        // ensure account collateral has incresaed by # of tokens
        (uint256 newCollateral, , ) = lendtroller.statusOf(address(this));
        assertEq(
            newCollateral,
            oldCollateral + tokens,
            "LENDTROLLER - new collateral must collateral+tokens"
        );
        // ensure that a user has a position after posting
        assertWithMsg(
            !success,
            "MARKET MANAGER - postCollateral() with too many tokens should fail"
        );
    }

    /// @custom:property lend-14 Removing collateral from the system should decrease the global posted collateral by the removed amount.
    /// @custom:property lend-15 Removing collateral from the system should reduce the user posted collateral by the removed amount.
    /// @custom:property lend-16 If the user has a liquidity shortfall, the user should not be permitted to remove collateral (function should fai with insufficient collateral selector hash).
    /// @custom:property lend-17 If the user does not have a liquidity shortfall and meets expected preconditions, the removeCollateral should be successful.
    /// @custom:precondition price feed must be recent
    /// @custom:precondition mtoken is one of: cDAI, cUSDC
    /// @custom:precondition mtoken must be listed in the MarketManager
    /// @custom:precondition current timestamp must exceed the MIN_HOLD_PERIOD from postCollateral timestamp
    /// @custom:precondition token is clamped between [1, collateralForUser]
    /// @custom:precondition redeemPaused flag must not be set
    function remove_collateral_should_succeed(
        address mtoken,
        uint256 tokens,
        bool closePositionIfPossible
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(postedCollateral[mtoken]);
        require(marketManager.isListed(mtoken));
        check_price_feed();

        emit LogUint256("posted collateral at: ", postedCollateralAt[mtoken]);
        emit LogUint256("MIN_HOLD_PERIOD: ", marketManager.MIN_HOLD_PERIOD());
        emit LogUint256("current timestamp: ", block.timestamp);
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );

        require(marketManager.hasPosition(mtoken, address(this)));
        require(marketManager.redeemPaused() != 2);

        uint256 oldCollateralForUser = marketManager.collateralPostedFor(
            mtoken,
            address(this)
        );
        tokens = clampBetween(tokens, 1, oldCollateralForUser);

        uint256 oldCollateralPostedForToken = marketManager.collateralPosted(
            mtoken
        );
        (, uint256 shortfall) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            tokens,
            0
        );
        emit LogUint256("shortfall:", shortfall);

        if (shortfall > 0) {
            (bool success, bytes memory revertData) = address(marketManager)
                .call(
                    abi.encodeWithSignature(
                        "removeCollateral(address,uint256,bool)",
                        mtoken,
                        tokens,
                        closePositionIfPossible
                    )
                );
            // If the call failed, ensure that the revert message is insufficient collateral
            if (!success) {
                uint256 errorSelector = extractErrorSelector(revertData);

                // LEND-16
                assertWithMsg(
                    errorSelector ==
                        marketmanager_insufficientCollateralSelectorHash,
                    "MARKET MANAGER - removeCollateral expected to revert with insufficientCollateral"
                );
            }
        } else {
            (bool success, bytes memory rd) = address(marketManager).call(
                abi.encodeWithSignature(
                    "removeCollateral(address,uint256,bool)",
                    mtoken,
                    tokens,
                    closePositionIfPossible
                )
            );
            // LEND-17
            assertWithMsg(
                success,
                "MARKET MANAGER - expected removeCollateral expected to be successful with no shortfall"
            );
            // Collateral posted for the mtoken should decrease
            uint256 newCollateralPostedForToken = marketManager
                .collateralPosted(mtoken);
            // LEND-14
            assertEq(
                newCollateralPostedForToken,
                oldCollateralPostedForToken - tokens,
                "MARKET MANAGER - global collateral posted should decrease"
            );

            // Collateral posted for the user should decrease
            uint256 newCollateralForUser = marketManager.collateralPostedFor(
                mtoken,
                address(this)
            );
            // LEND-15
            assertEq(
                newCollateralForUser,
                oldCollateralForUser - tokens,
                "MARKET MANAGER - user collateral posted should decrease"
            );
            if (newCollateralForUser == 0 && closePositionIfPossible) {
                assertWithMsg(
                    !marketManager.hasPosition(mtoken, address(this)),
                    "MARKET MANAGER - closePositionIfPossible flag set should remove a user's position"
                );
            }
        }
    }

    /// @custom:property lend-18 Removing collateral for a nonexistent position should revert with invariant error hash.
    /// @custom:precondition mtoken is either of: cDAI or cUSDC
    /// @custom:precondition token must be listed in MarketManager
    /// @custom:precondition price feed must be up to date
    /// @custom:precondition user must NOT have an existing position
    function removeCollateral_should_fail_with_non_existent_position(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(marketManager.isListed(mtoken));
        check_price_feed();
        require(!marketManager.hasPosition(mtoken, address(this)));

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature(
                "removeCollateral(address,uint256,bool)",
                mtoken,
                tokens,
                closePositionIfPossible
            )
        );

        if (success) {
            // LEND-18
            assertWithMsg(
                false,
                "MARKET MANAGER - removeCollateral should fail with non existent position"
            );
        } else {
            // expectation is that this should fail
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketmanager_invariantErrorSelectorHash,
                "MARKET MANAGER - expected removeCollateral to revert with InvariantError"
            );
        }
    }

    /// @custom:property lend-19 Removing more tokens than a user has for collateral should revert with insufficient collateral hash.
    /// @custom:precondition mtoken is either of: cDAI or cUSDC
    /// @custom:precondition token must be listed in MarketManager
    /// @custom:precondition price feed must be up to date
    /// @custom:precondition user must have an existing position
    /// @custom:precondition tokens to remove is bound between [existingCollateral+1, uint256.max]
    function removeCollateral_should_fail_with_removing_too_many_tokens(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(marketManager.isListed(mtoken));
        check_price_feed();
        require(marketManager.hasPosition(mtoken, address(this)));
        uint256 oldCollateralForUser = marketManager.collateralPostedFor(
            mtoken,
            address(this)
        );

        tokens = clampBetween(
            tokens,
            oldCollateralForUser + 1,
            type(uint256).max
        );

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature(
                "removeCollateral(address,uint256,bool)",
                mtoken,
                tokens,
                false
            )
        );

        if (success) {
            assertWithMsg(
                false,
                "MARKET MANAGER - removeCollateral should fail insufficient collateral"
            );
        } else {
            // expectation is that this should fail
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    marketmanager_insufficientCollateralSelectorHash,
                "MARKET MANAGER - expected removeCollateral to revert with InsufficientCollateral when attempting to remove too much"
            );
        }
    }

    /// @custom:property lend-20 Calling reduceCollateralIfNecessary should fail when not called within the context of the mtoken.
    /// @custom:precondition msg.sender != mtoken
    function reduceCollateralIfNecessary_should_fail_with_wrong_caller(
        address mtoken,
        uint256 amount
    ) public {
        try
            marketManager.reduceCollateralIfNecessary(
                address(this),
                mToken,
                balance,
                amount
            )
        {} catch {}
    }

    function closePosition_should_succeed(address mToken) public {
        require(lendtroller.hasPosition(mToken, address(this)));

        (bool success, bytes memory rd) = address(lendtroller).call(
            abi.encodeWithSignature("closePosition(address)", mToken)
        );
        if (!success) {}
    }

    function canMint_should_not_revert_when_mint_not_paused_and_is_listed(
        address mToken
    ) public {
        uint256 mintPaused = lendtroller.mintPaused(mToken);
        bool isListed = lendtroller.isListed(mToken);

        require(mintPaused != 2);
        require(isListed);

        try lendtroller.canMint(mToken) {} catch {
            assertWithMsg(
                errorSelector == marketmanager_unauthorizedSelectorHash,
                "MARKET MANAGER - reduceCollateralIfNecessary expected to revert"
            );
        }
    }

    /// @custom:property lend-21 Calling closePosition with correct preconditions should remove a position in the mtoken, where collateral posted for the user is greater than 0.
    /// @custom:property lend-22 Calling closePosition with correct preconditions should set collateralPosted for the user’s mtoken to zero, where collateral posted for the user is greater than 0.
    /// @custom:property lend-23 Calling closePosition with correct preconditions should reduce the user asset list by 1 element, where collateral posted for the user is greater than 0.
    /// @custom:property lend-24 Calling closePosition with correct preconditions should succeed,where collateral posted for the user is greater than 0.
    /// @custom:precondition token must be cDAI or cUSDC
    /// @custom:precondition token must have an existing position
    /// @custom:precondition collateralPostedForUser for respective token > 0
    function closePosition_should_succeed(address mtoken) public {
        require(marketManager.redeemPaused() != 2);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(marketManager.hasPosition(mtoken, address(this)));
        check_price_feed();
        uint256 collateralPostedForUser = marketManager.collateralPostedFor(
            address(mtoken),
            address(this)
        );
        require(collateralPostedForUser > 0);
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        IMToken[] memory preAssetsOf = marketManager.assetsOf(address(this));
        (, uint256 shortfall) = marketManager.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            collateralPostedForUser,
            0
        );

        (bool success, bytes memory revertData) = address(marketManager).call(
            abi.encodeWithSignature("closePosition(address)", mtoken)
        );
        uint256 errorSelector = extractErrorSelector(revertData);

        if (!success) {
            if (shortfall > 0) {
                assertWithMsg(
                    errorSelector ==
                        marketmanager_insufficientCollateralSelectorHash,
                    "MARKET MANAGER - closePosition should revert with InsufficientCollateral if shortfall exists"
                );
            } else {
                assertWithMsg(
                    false,
                    "MARKET MANAGER - closePosition expected to be successful with correct preconditions"
                );
            }
        } else {
            check_close_position_post_conditions(mtoken, preAssetsOf.length);
        }
    }

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

    function canRedeem_should_revert_when_redeem_is_paused(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() == 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canRedeem(mToken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert when redeem is paused"
            );
        } catch {}
    }

    function canRedeem_should_revert_token_not_listed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(marketManager.redeemPaused() != 2);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(marketManager.hasPosition(mtoken, address(this)));
        check_price_feed();
        uint256 collateralPostedForUser = marketManager.collateralPostedFor(
            address(mtoken),
            address(this)
        );
        require(collateralPostedForUser == 0);
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        IMToken[] memory preAssetsOf = marketManager.assetsOf(address(this));

        (bool success, bytes memory rd) = address(marketManager).call(
            abi.encodeWithSignature("closePosition(address)", mtoken)
        );
        if (!success) {} else {
            check_close_position_post_conditions(mtoken, preAssetsOf.length);
        }
    }

    function check_close_position_post_conditions(
        address mtoken,
        uint256 preAssetsOfLength
    ) private {
        assertWithMsg(
            !marketManager.hasPosition(mtoken, address(this)),
            "MARKET MANAGER - closePosition should remove position in mtoken if successful"
        );
        assertWithMsg(
            marketManager.collateralPostedFor(mtoken, address(this)) == 0,
            "MARKET MANAGER - closePosition should reduce collateralPosted for user to 0"
        );
        IMToken[] memory postAssetsOf = marketManager.assetsOf(address(this));
        assertWithMsg(
            preAssetsOfLength - 1 == postAssetsOf.length,
            "MARKET MANAGER - closePosition expected to remove asset from assetOf"
        );
    }

    function liquidateAccount_should_succeed(address account) public {
        try marketManager.liquidateAccount(account) {} catch {}
    }

    function listToken_should_succeed(address token) public {
        try lendtroller.listToken(token) {} catch {}
    }

    // Stateful Functions

    // ctoken.balanceOf(user) >= collateral posted
    function cToken_balance_gte_collateral_posted(address ctoken) public {
        uint256 cTokenBalance = MockCToken(ctoken).balanceOf(address(this));

        uint256 collateralPostedForAddress = marketManager.collateralPosted(
            address(this)
        );

        assertGte(
            cTokenBalance,
            collateralPostedForAddress,
            "MARKET MANAGER - cTokenBalance must exceed collateral posted"
        );
    }

    // Market collateral posted should always be <= caps, as all values are recorded in shares rather than # of tokens
    // accountdata[address].collateralPosted <= collateral caps per token
    function collateralPosted_lte_collateralCaps(address token) public {
        uint256 collateralPosted = marketManager.collateralPosted(token);

        uint256 collateralCaps = marketManager.collateralCaps(token);

        assertLte(
            collateralPosted,
            collateralCaps,
            "MARKET MANAGER - collateralPosted must be <= collateralCaps"
        );
    }

    // @custom:property s-lend-3 totalSupply should never be zero for any mtoken once added to MarketManager
    function totalSupply_of_listed_token_is_never_zero(address mtoken) public {
        require(marketManager.isListed(mtoken));
        assertNeq(
            IMToken(mtoken).totalSupply(),
            0,
            "IMToken - totalSupply should never go down to zero once listed"
        );
    }

    // current debt > max allowed debt after folding

    // Helper Functions

    struct TokenCollateralBounds {
        uint256 collRatio;
        uint256 collReqSoft;
        uint256 collReqHard;
        uint256 liqIncSoft;
        uint256 liqIncHard;
        uint256 liqFee;
        uint256 baseCFactor;
    }
    TokenCollateralBounds safeBounds;

    // Bounds the specific variables required to call updateCollateralBounds
    // Variables are generated in basis points, and converted to WAD (by multiplying by 1e14)
    // Assume ALL bounds below are inclusive, on both ends
    // baseCFactor: [1, WAD/1e14]
    // liqFee: [0, MAX_LIQUIDATION_FEE/1e14]
    // liqIncSoft: [MIN_LIQUIDATION_INCENTIVE() / 1e14 + liqFee, MAX_LIQUIDATION_INCENTIVE()/1e14-1]
    // liqIncHard: [liqIncSoft+1, MAX_LIQUIDATION_INCENTIVE/1e14]
    // inherently from above, liqIncSoft < liqIncHard
    // collReqHard = [liqIncHard, MAX_COLLATERAL_REQUIREMENT()/1e14-1]
    // collReqSoft = [collReqHard+1, MAX_COLLATERAL_REQUIREMENT()/1e14]
    // collateralRatio = [0, min(MAX_COLLATERALIZATION_RATIO/1e14, (WAD*WAD)/(WAD+collReqSoft*1e14))]
    function get_safe_update_collateral_bounds(
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor
    ) private {
        // TODO: incorrect for new rebase (min: 10%, max: 50%)
        safeBounds.baseCFactor = clampBetween(baseCFactor, 1, 1e18 / 1e14);

        // liquidity incentive soft -> hard goes up
        safeBounds.liqFee = clampBetween(
            liqFee,
            0,
            marketManager.MAX_LIQUIDATION_FEE() / 1e14
        );

        safeBounds.liqIncSoft = clampBetween(
            liqIncSoft,
            marketManager.MIN_LIQUIDATION_INCENTIVE() /
                1e14 +
                safeBounds.liqFee,
            marketManager.MAX_LIQUIDATION_INCENTIVE() / 1e14 - 1
        );

        safeBounds.liqIncHard = clampBetween(
            liqIncHard,
            safeBounds.liqIncSoft + 1, // TODO expected changes in rebase
            marketManager.MAX_LIQUIDATION_INCENTIVE() / 1e14
        );

        // collateral requirement soft -> hard goes down
        safeBounds.collReqHard = clampBetween(
            collReqHard,
            safeBounds.liqIncHard, // account for MIN_EXCESS_COLLATERAL_REQUIREMENT  on rebase
            marketManager.MAX_COLLATERAL_REQUIREMENT() / 1e14 - 1
        );

        safeBounds.collReqSoft = clampBetween(
            collReqSoft,
            safeBounds.collReqHard + 1,
            marketManager.MAX_COLLATERAL_REQUIREMENT() / 1e14
        );

        uint256 collatPremium = uint256(
            ((WAD * WAD) / (WAD + (safeBounds.collReqSoft * 1e14)))
        );

        if (marketManager.MAX_COLLATERALIZATION_RATIO() > collatPremium) {
            safeBounds.collRatio = clampBetween(
                collRatio,
                0,
                (collatPremium / 1e14) // collat ratio is going to be *1e14, so make sure that it will not overflow
            );
            emit LogUint256(
                "collateral ratio clamped to collateralization premium:",
                safeBounds.collRatio
            );
        } else {
            safeBounds.collRatio = clampBetween(
                collRatio,
                0,
                marketManager.MAX_COLLATERALIZATION_RATIO() / 1e14
            );
            emit LogUint256(
                "collateral ratio clamped to max collateralization ratio:",
                safeBounds.collRatio
            );
        }
    }
}
