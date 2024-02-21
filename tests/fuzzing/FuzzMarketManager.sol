pragma solidity 0.8.17;
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { IMToken } from "contracts/market/LiquidityManager.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { FuzzLiquidations } from "tests/fuzzing/stateless/FuzzLiquidations.sol";

contract FuzzMarketManager is FuzzLiquidations {
    mapping(address => bool) setCollateralValues;
    // were the collateral caps for a specific mtoken updated
    mapping(address => bool) collateralCapsUpdated;
    // has collateral been posted for a specific mtoken
    mapping(address => bool) postedCollateral;
    // has the collateral ratio for a specific token been set to zero
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
        list_token_should_succeed(address(cUSDC));
    }

    function setup() public {
        setUpFeeds();
        marketManager.updateCollateralToken(
            IMToken(address(cUSDC)),
            7000,
            4000,
            3000,
            200,
            400,
            10,
            1000
        );
        setCToken_should_succeed(address(cUSDC), 100_000e18);
        c_token_deposit(address(cUSDC), 2 * WAD, true);
        post_collateral_should_succeed(address(cUSDC), WAD * 2 - 1, false);
    }

    /// @custom:property market-1 Once a new token is listed, marketManager.isListed(mtoken) should return true.
    /// @custom:precondition mtoken must not already be listed
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    function list_token_should_succeed(address mtoken) public {
        uint256 amount = 42069;
        // require the token is not already listed into the marketManager
        require(!marketManager.isListed(mtoken));

        require(
            mtoken == address(cDAI) ||
                mtoken == address(cUSDC) ||
                mtoken == address(dDAI) ||
                mtoken == address(dDAI)
        );
        require(_mintAndApprove(IMToken(mtoken).underlying(), mtoken, amount));

        try marketManager.listToken(mtoken) {
            assertWithMsg(
                marketManager.isListed(mtoken),
                "MARKET-1 marketManager.listToken() should succeed"
            );
        } catch {
            assertWithMsg(false, "MARKET-1 failed to list token");
        }
    }

    /// @custom:property market-2 A token already added to the marketManager cannot be added again
    /// @custom:precondition mtoken must already be listed
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    function list_token_should_fail_if_already_listed(address mtoken) public {
        // require the token is not already listed into the marketManager
        require(marketManager.isListed(mtoken));

        require(mtoken == address(cDAI) || mtoken == address(cUSDC));

        try marketManager.listToken(mtoken) {
            assertWithMsg(
                false,
                "MARKET-2 listToken for duplicate token should not be possible"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_tokenAlreadyListedSelectorHash,
                "MARKET-2 listToken() expected TokenAlreadyListed selector hash on failure"
            );
        }
    }

    /// @custom:property market-3 – A user can deposit into an mtoken provided that they have the underlying asset, and they have approved the mtoken contract.
    /// @custom:property market-4 – When depositing assets into the mtoken, the wrapped token balance for the user should increase.
    /// @custom:property market-29 If convertToShares overflows, deposit should revert
    /// @custom:property market-30 If totalAssets+amount overflows, deposit should revert
    /// @custom:property market-31 If oracle returns price <0, deposit should revert
    /// @custom:precondition GaugePool must have been started before block.timestamp
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    /// @custom:precondition mtoken must be listed in marketManager
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
        amount = clampBetweenBoundsFromOne(lower, amount);
        require(_mintAndApprove(underlyingAddress, mtoken, amount));
        uint256 preCTokenBalanceThis = MockCToken(mtoken).balanceOf(
            address(this)
        );
        uint256 preTotalAssets = MockCToken(mtoken).totalAssets();

        // TODO: investigate 20 min hold period for debt token ()
        try MockCToken(mtoken).deposit(amount, address(this)) {
            uint256 postCTokenBalanceThis = MockCToken(mtoken).balanceOf(
                address(this)
            );

            assertLt(
                preCTokenBalanceThis,
                postCTokenBalanceThis,
                "MARKET-4 pre and post ctoken balance should increase"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            bool convertToSharesOverflow;

            try MockCToken(mtoken).convertToShares(amount) {} catch (
                bytes memory convertSharesData
            ) {
                uint256 convertSharesError = extractErrorSelector(
                    convertSharesData
                );
                emit LogUint256(
                    "convert to shares error did overflow",
                    convertSharesError
                );
                // CTokenBase._convertToShares will revert when `mulDivDown` overflows with `revert(0,0)
                if (convertSharesError == 2904890407) {
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
            // market-31
            bool isPriceNegative;
            if (mtoken == address(cDAI)) {
                isPriceNegative = chainlinkDaiUsd.latestAnswer() < 0;
            } else {
                isPriceNegative = chainlinkUsdcUsd.latestAnswer() < 0;
            }
            // market-29, market-30
            if (convertToSharesOverflow || assetCalc) {
                assertEq(
                    errorSelector,
                    overflow,
                    "MARKET-29-31 expected mtoken.deposit() to revert with overflow"
                );
            } else {
                // market-3
                assertWithMsg(
                    false,
                    "MARKET-3 expected mtoken.deposit() to be successful"
                );
            }
        }
    }

    /// @custom:property market-5 – Calling updateCollateralToken with variables in correct bounds should succeed.
    /// @custom:property market-6 - calling updateCollateralToken for token prices that deviate too much results in a PriceError
    /// @custom:property market-7 - calling updateCollateralToken for token prices that are <0 results in a PriceError
    /// @custom:property market-8 - calling updateCollateralToken again with a pre-CR != 0 with new CR=0 should revert
    /// @custom:precondition price feed must be recent
    /// @custom:precondition price feed must be setup
    /// @custom:precondition address(this) must have dao permissions
    /// @custom:precondition cap is bound between [1, uint256.max], inclusive
    /// @custom:precondition mtoken must be listed in the marketManager
    /// @custom:precondition _getSafeUpdateCollateralBounds must be in correct bounds
    /// TODO: Logic to not allow updateCollateralToken to be re-called with a 0 CR was added after, and needs to be acounted for in these tests
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
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(marketManager.isListed(mtoken));
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(feedsSetup);

        (bool divergenceTooLarge, bool priceError) = _checkPriceDivergence(
            mtoken
        );

        (, uint256 oldCR, , , , , , , ) = marketManager.tokenData(mtoken);
        {
            _checkPriceFeed();
            _getSafeUpdateCollateralBounds(
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

                if (divergenceTooLarge) {
                    assertWithMsg(
                        errorSelector == marketManager_priceErrorSelectorHash,
                        "MARKET-6 expected updateCollateralToken to fail if price diverge too much or encounters error"
                    );
                } else if (priceError) {
                    assertWithMsg(
                        errorSelector == marketManager_priceErrorSelectorHash,
                        "MARKET-7 expected updateCollateralToken to fail if price diverge too much or encounters error"
                    );
                } else if (oldCR != 0 && safeBounds.collRatio == 0) {
                    assertWithMsg(
                        errorSelector ==
                            marketManager_invalidParameterSelectorHash,
                        "MARKET-8 updateCollateralToken expected to fail if trying to zero a non-zero CR"
                    );
                } else {
                    // market-5
                    assertWithMsg(
                        false,
                        "MARKET-5 updateCollateralToken should succeed"
                    );
                }
            }
        }
    }

    /// @custom:property market-9 – Calling setCTokenCollateralCaps should increase the globally set the collateral caps to the cap provided
    /// @custom:property market-10 Setting collateral caps for a token given permissions and collateral values being set should succeed.
    /// @custom:precondition address(this) has dao permissions
    /// @custom:precondition mtoken is a C token
    /// @custom:precondition collateral values for mtoken must be set
    /// @custom:precondition cap is bound between [0, uint256.max]
    function setCToken_should_succeed(address mtoken, uint256 cap) public {
        require(IMToken(mtoken).isCToken());
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(setCollateralValues[mtoken]);
        require(!isCollateralRatioZero[mtoken]);
        if (cap > maxCollateralCap[mtoken]) {
            maxCollateralCap[mtoken] = cap;
        }

        _checkPriceFeed();

        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        (bool success, ) = address(marketManager).call(
            abi.encodeWithSignature(
                "setCTokenCollateralCaps(address[],uint256[])",
                tokens,
                caps
            )
        );

        if (success) {
            assertEq(
                marketManager.collateralCaps(mtoken),
                cap,
                "MARKET-9 collateral caps for token should be >=0"
            );
        } else {
            // market-7
            assertWithMsg(
                false,
                "MARKET-10 expected setCTokenCollateralCaps to succeed"
            );
        }

        collateralCapsUpdated[mtoken] = true;
    }

    /// @custom:property market-8 – updateCollateralToken should revert if the price feed is out of date
    /// @custom:precondition price feed is out of date
    /// @custom:precondition cap is bound between [1, uint256.max], inclusive
    /// @custom:precondition mtoken must be listed in marketManager
    /// @custom:precondition mtoken must be one of: cDAI, cUSDC
    function updateCollateralToken_should_revert_if_price_feed_out_of_date(
        address mtoken,
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor,
        uint256 cap
    ) public {
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        require(block.timestamp - lastRoundUpdate > 24 hours);
        if (mtoken == address(cDAI)) {
            require(
                block.timestamp - chainlinkDaiUsd.latestTimestamp() > 24 hours
            );
        } else if (mtoken == address(cUSDC)) {
            require(
                block.timestamp - chainlinkUsdcUsd.latestTimestamp() > 24 hours
            );
        } else {
            return;
        }
        require(feedsSetup);
        require(centralRegistry.hasDaoPermissions(address(this)));
        if (!marketManager.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        {
            _getSafeUpdateCollateralBounds(
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
            assertWithMsg(
                false,
                "MARKET-12 updateCollateralToken should not have succeeded with out of date price feeds"
            );
        } catch {}
    }

    /// @custom:property market-13 After collateral is posted, the user’s collateral posted position for the respective asset should increase.
    /// @custom:property market-14 After collateral is posted, calling hasPosition on the user’s mtoken should return true.
    /// @custom:property market-15 After collateral is posted, the global collateral for the mtoken should increase by the amount posted.
    /// @custom:property market-16 When price feed is up to date, address(this) has mtoken, tokens are bound correctly, and caller is correct, the  postCollateral call should succeed.
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
        _checkPriceFeed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(
                mtoken,
                tokens * IMToken(mtoken).decimals(),
                lower
            );
        }
        uint256 mtokenBalance = IMToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = _collateralPostedFor(mtoken);
        uint256 collateralCaps = marketManager.collateralCaps(mtoken);

        uint256 oldCollateralForToken = marketManager.collateralPosted(mtoken);
        if (
            mtokenBalance - oldCollateralForUser >
            collateralCaps - oldCollateralForToken
        ) {
            // collateralPosted[mToken] + tokens <= collateralCaps[mToken])
            // tokens <= collateralCaps[mtoken] - collateralPosted[mtoken]
            tokens = clampBetween(
                tokens,
                1,
                collateralCaps - oldCollateralForToken
            );
        } else {
            // collateralPosted + tokens <= mtoken.balanceOf(address(this))
            // tokens <= mtoken.balanceOf(address(this)) - collateralPosted
            tokens = clampBetween(
                tokens,
                1,
                mtokenBalance - oldCollateralForUser
            );
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
                assertWithMsg(
                    false,
                    "MARKET-16 expected postCollateral to pass with @precondition"
                );
            } else {
                // ensure account collateral has increased by # of tokens
                uint256 newCollateralForUser = _collateralPostedFor(mtoken);

                uint256 mtokenExchange = MockCToken(mtoken).exchangeRateSafe();
                assertEq(
                    (newCollateralForUser) * mtokenExchange,
                    (oldCollateralForUser + tokens) * mtokenExchange,
                    "MARKET-13 new collateral must collateral+tokens"
                );
                assertWithMsg(
                    _hasPosition(mtoken),
                    "MARKET-14 addr(this) must have position after posting"
                );

                uint256 newCollateralForToken = marketManager.collateralPosted(
                    mtoken
                );
                assertEq(
                    newCollateralForToken,
                    oldCollateralForToken + tokens,
                    "MARKET-15 global collateral posted should increase"
                );
                postedCollateral[mtoken] = true;
                postedCollateralAt[mtoken] = block.timestamp;
            }
        }
    }

    /// @custom:property market-17 – Trying to post too much collateral should revert.
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
        _checkPriceFeed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(
                mtoken,
                tokens * IMToken(mtoken).decimals(),
                lower
            );
        }
        uint256 mtokenBalance = IMToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = _collateralPostedFor(mtoken);

        // collateralPosted + tokens <= mtoken.balanceOf(address(this))
        // tokens <= mtoken.balanceOf(address(this)) - collateralPosted
        tokens = clampBetween(
            tokens,
            mtokenBalance - oldCollateralForUser + 1,
            type(uint256).max
        );

        (bool success, ) = address(marketManager).call(
            abi.encodeWithSignature(
                "postCollateral(address,address,uint256)",
                address(this),
                mtoken,
                tokens
            )
        );

        assertWithMsg(
            !success,
            "MARKET-17 postCollateral() with too many tokens should fail"
        );
    }

    /// @custom:property market-18 Removing collateral from the system should decrease the global posted collateral by the removed amount.
    /// @custom:property market-19 Removing collateral from the system should reduce the user posted collateral by the removed amount.
    /// @custom:property market-20 If the user has a liquidity shortfall, the user should not be permitted to remove collateral (function should fai with insufficient collateral selector hash).
    /// @custom:property market-21 If the user does not have a liquidity shortfall and meets expected preconditions, the removeCollateral should be successful.
    /// @custom:property market-22 If new collateral for user after removing is = 0 and a user wants to close position, the user should no longer have a position in the asset
    /// @custom:precondition price feed must be recent
    /// @custom:precondition mtoken is one of: cDAI, cUSDC
    /// @custom:precondition mtoken must be listed in the marketManager
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
        _checkPriceFeed();

        emit LogUint256('cooldown timestamp for mtoken', _getCooldownTimestampFor(mtoken))
        require(
            block.timestamp >
                _getCooldownTimestampFor() +
                    marketManager.MIN_HOLD_PERIOD()
        );

        require(_hasPosition(mtoken));
        require(marketManager.redeemPaused() != 2);

        uint256 oldCollateralForUser = _collateralPostedFor(mtoken);
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

                assertWithMsg(
                    errorSelector ==
                        marketManager_insufficientCollateralSelectorHash,
                    "MARKET-20 removeCollateral expected to revert with insufficientCollateral"
                );
            }
        } else {
            (bool success, ) = address(marketManager).call(
                abi.encodeWithSignature(
                    "removeCollateral(address,uint256,bool)",
                    mtoken,
                    tokens,
                    closePositionIfPossible
                )
            );

            assertWithMsg(
                success,
                "MARKET-21 expected removeCollateral expected to be successful with no shortfall"
            );
            // Collateral posted for the mtoken should decrease
            uint256 newCollateralPostedForToken = marketManager
                .collateralPosted(mtoken);
            assertEq(
                newCollateralPostedForToken,
                oldCollateralPostedForToken - tokens,
                "MARKET-18 global collateral posted should decrease"
            );

            // Collateral posted for the user should decrease
            uint256 newCollateralForUser = _collateralPostedFor(mtoken);
            assertEq(
                newCollateralForUser,
                oldCollateralForUser - tokens,
                "MARKET-19 user collateral posted should decrease"
            );
            if (newCollateralForUser == 0 && closePositionIfPossible) {
                assertWithMsg(
                    !_hasPosition(mtoken),
                    "MARKET-22 closePositionIfPossible flag set should remove a user's position"
                );
            }
        }
    }

    /// @custom:property market-23 Removing collateral for a nonexistent position should revert with invariant error hash.
    /// @custom:property market-41 Removing 0 tokens in collateral should revert with invalid parameter selector
    /// @custom:precondition mtoken is either of: cDAI or cUSDC
    /// @custom:precondition token must be listed in marketManager
    /// @custom:precondition price feed must be up to date
    /// @custom:precondition user must NOT have an existing position
    function removeCollateral_should_fail_with_non_existent_position(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(marketManager.isListed(mtoken));
        _checkPriceFeed();
        require(!_hasPosition(mtoken));

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
                "MARKET-23 removeCollateral should fail with non existent position"
            );
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);

            if (tokens == 0) {
                assertWithMsg(
                    errorSelector ==
                        marketManager_invalidParameterSelectorHash,
                    "MARKET-41 removeCollateral should revert when trying to remove 0 tokens"
                );
            } else {
                assertWithMsg(
                    errorSelector == marketManager_invariantErrorSelectorHash,
                    "MARKET-23 expected removeCollateral to revert with InvariantError"
                );
            }
        }
    }

    /// @custom:property market-24 Removing more tokens than a user has for collateral should revert with insufficient collateral hash.
    /// @custom:precondition mtoken is either of: cDAI or cUSDC
    /// @custom:precondition token must be listed in marketManager
    /// @custom:precondition price feed must be up to date
    /// @custom:precondition user must have an existing position
    /// @custom:precondition tokens to remove is bound between [existingCollateral+1, uint256.max]
    function removeCollateral_should_fail_with_removing_too_many_tokens(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(marketManager.isListed(mtoken));
        _checkPriceFeed();
        require(_hasPosition(mtoken));
        uint256 oldCollateralForUser = _collateralPostedFor(mtoken);

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
                "MARKET-24 removeCollateral should fail insufficient collateral"
            );
        } else {
            // expectation is that this should fail
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    marketManager_insufficientCollateralSelectorHash,
                "MARKET-24 expected removeCollateral to revert with InsufficientCollateral when attempting to remove too much"
            );
        }
    }

    /// @custom:property market-25 Calling reduceCollateralIfNecessary should fail when not called within the context of the mtoken.
    /// @custom:precondition msg.sender != mtoken
    function reduceCollateralIfNecessary_should_fail_with_wrong_caller(
        address mtoken,
        uint256 amount
    ) public {
        require(msg.sender != mtoken);
        try
            marketManager.reduceCollateralIfNecessary(
                address(this),
                mtoken,
                IMToken(mtoken).balanceOf(address(this)),
                amount
            )
        {
            assertWithMsg(
                false,
                "MARKET-25 reduceCollateralIfNecessary should not be successful if called directly"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == marketManager_unauthorizedSelectorHash,
                "MARKET-25 reduceCollateralIfNecessary expected to revert with Unauthorized"
            );
        }
    }

    /// @custom:property market-26 Calling closePosition with correct preconditions should remove a position in the mtoken, where collateral posted for the user is greater than 0.
    /// @custom:property market-27 Calling closePosition with correct preconditions should set collateralPosted for the user’s mtoken to zero, where collateral posted for the user is greater than 0.
    /// @custom:property market-28 Calling closePosition with correct preconditions should reduce the user asset list by 1 element, where collateral posted for the user is greater than 0.
    /// @custom:property market-29 Calling closePosition with correct preconditions should succeed,where collateral posted for the user is greater than 0.
    /// @custom:property market-30 In a shortfall, closePosition should revert with insufficient collateral error
    /// @custom:precondition token must be cDAI or cUSDC
    /// @custom:precondition token must have an existing position
    /// @custom:precondition collateralPostedForUser for respective token > 0
    function closePosition_should_succeed(address mtoken) public {
        require(marketManager.redeemPaused() != 2);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(_hasPosition(mtoken));
        _checkPriceFeed();
        uint256 collateralPostedForUser = _collateralPostedFor(mtoken);
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
                        marketManager_insufficientCollateralSelectorHash,
                    "MARKET-30 closePosition should revert with InsufficientCollateral if shortfall exists"
                );
            } else {
                assertWithMsg(
                    false,
                    "MARKET-29 closePosition expected to be successful with correct preconditions"
                );
            }
        } else {
            _checkClosePositionPostConditions(
                mtoken,
                preAssetsOf.length,
                "MARKET-26",
                "MARKET-27",
                "MARKET-28"
            );
        }
    }

    /// @custom:property market-31 Calling closePosition with correct preconditions should remove a position in the mtoken, where collateral posted for the user is equal to 0.
    /// @custom:property market-32 Calling closePosition with correct preconditions should set collateralPosted for the user’s mtoken to zero, where collateral posted for the user is equal to 0.
    /// @custom:property market-33 Calling closePosition with correct preconditions should reduce the user asset list by 1 element, where collateral posted for the user is equal to 0.
    /// @custom:property market-34 Calling closePosition with correct preconditions should succeed,where collateral posted for the user is equal to 0.
    /// @custom:precondition token must be cDAI or cUSDC
    /// @custom:precondition token must have an existing position
    /// @custom:precondition collateralPostedForUser for respective token = 0
    function closePosition_should_succeed_if_collateral_is_0(
        address mtoken
    ) public {
        require(marketManager.redeemPaused() != 2);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(_hasPosition(mtoken));
        _checkPriceFeed();
        uint256 collateralPostedForUser = _collateralPostedFor(mtoken);
        require(collateralPostedForUser == 0);
        require(
            block.timestamp >
                postedCollateralAt[mtoken] + marketManager.MIN_HOLD_PERIOD()
        );
        IMToken[] memory preAssetsOf = marketManager.assetsOf(address(this));

        (bool success, ) = address(marketManager).call(
            abi.encodeWithSignature("closePosition(address)", mtoken)
        );
        if (!success) {
            assertWithMsg(
                false,
                "MARKET-34 - closePosition should succeed if collateral is 0"
            );
        } else {
            _checkClosePositionPostConditions(
                mtoken,
                preAssetsOf.length,
                "MARKET-31",
                "MARKET-32",
                "MARKET-33"
            );
        }
    }

    uint256 constant DAI_PRICE = 1e24;
    uint256 constant USDC_PRICE = 1e7;

    /// @custom:property market-35 Liquidating an acount with the correct preconditions should succeed.
    /// @custom:property market-36 Liquidating an account should result in all collateral token balances being zeroed out.
    /// @custom:property market-37 Liquidating an account should result in all debtBalanceCached() for all debt tokens being zeroed out.
    function liquidateAccount_should_succeed(uint256 amount) public {
        uint256 daiPrice = DAI_PRICE;
        uint256 usdcPrice = USDC_PRICE;
        require(marketManager.seizePaused() != 2);
        address account = address(this);
        _preLiquidate(amount, DAI_PRICE, USDC_PRICE);
        calculateLiquidation_exact(amount);

        IMToken[] memory assets = marketManager.assetsOf(account);

        hevm.prank(msg.sender);
        try this.prankLiquidateAccount(account) {
            emit LogAddress("msg.sender", msg.sender);
            for (uint256 i = 0; i < assets.length; i++) {
                if (assets[i].isCToken()) {
                    assertEq(
                        _collateralPostedFor(address(assets[i])),
                        0,
                        "MARKET-36 - liquidateAccount should zero out collateral"
                    );
                } else {
                    assertEq(
                        IMToken(assets[i]).debtBalanceCached(address(this)),
                        0,
                        "MARKET-37 - liquidateAccount should zero out debt balance"
                    );
                }
            }
        } catch {
            assertWithMsg(
                false,
                "MARKET-35 liquidateAccount with correct preconditions should succeed"
            );
        }
    }

    /// @custom:property market-38 liquidateAccount shoudl fail if acocunt is not flagged for liquidation
    function liquidateAccount_should_fail_if_account_not_flagged(
        uint256 amount
    ) public {
        require(marketManager.seizePaused() != 2);
        require(!marketManager.flaggedForLiquidation(address(this)));
        address account = address(this);

        hevm.prank(msg.sender);
        try this.prankLiquidateAccount(account) {
            assertWithMsg(
                false,
                "MARKET- liquidateAccount should fail if account is not flagged for liquidations"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertEq(
                errorSelector,
                marketManager_noLiquidationAvailableSelectorHash,
                "MARKET- liquidateAccount should fail with NoLiquidationAvailable if not flagged"
            );
        }
    }

    function liquidateAccount_should_fail_if_self_account(
        uint256 amount
    ) public {
        uint256 daiPrice = DAI_PRICE;
        uint256 usdcPrice = USDC_PRICE;
        require(marketManager.seizePaused() != 2);
        address account = msg.sender;
        _preLiquidate(amount, DAI_PRICE, USDC_PRICE);

        hevm.prank(msg.sender);
        try this.prankLiquidateAccount(account) {
            assertWithMsg(
                false,
                "MARKET- liquidateAccount should fail if user attempts to liquidate themselves"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertEq(
                errorSelector,
                marketManager_unauthorizedSelectorHash,
                "MARKET- liquidateAccount should fail with Unauthorized"
            );
        }
    }

    function liquidateAccount_should_fail_if_seize_paused(
        uint256 amount
    ) public {
        require(marketManager.seizePaused() == 2);
        uint256 daiPrice = DAI_PRICE;
        uint256 usdcPrice = USDC_PRICE;
        address account = address(this);
        _preLiquidate(amount, DAI_PRICE, USDC_PRICE);

        hevm.prank(msg.sender);
        try this.prankLiquidateAccount(account) {
            assertWithMsg(
                false,
                "MARKET- liquidateAccount should fail if user attempts to liquidate themselves"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertEq(
                errorSelector,
                marketManager_pausedSelectorHash,
                "MARKET- liquidateAccount should fail with PAUSED when seize is paused"
            );
        }
    }

    function prankLiquidateAccount(address account) public {
        hevm.prank(msg.sender);
        marketManager.liquidateAccount(account);
    }

    // Helper Functions

    function _setupLiquidatableStates(
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
    function _preLiquidate(
        uint256 amount,
        uint256 daiPrice,
        uint256 usdcPrice
    ) private {
        // ensure price feeds are up to date and in sync before updating collateral token and listing
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

            // user to be liquidated must already have a position in cUSDC
            bool hasUsdcPosition = _hasPosition(address(cUSDC));
            // if they do not, post it as collateral
            if (!hasUsdcPosition) {
                post_collateral_should_succeed(address(cUSDC), WAD + 1, false);
            }
        }
        {
            // ddai must be listed in the market manager to continue
            (bool is_ddai_listed, , , , , , , , ) = marketManager.tokenData(
                address(dDAI)
            );
            // if ddai is not listed, list the ddai token to the manager
            if (!is_ddai_listed) {
                list_token_should_succeed(address(dDAI));
            }
        }

        // the maximum amount of ddai that can be borrowed is the market underlying held - totalReserves
        uint256 upperBound = DToken(address(dDAI)).marketUnderlyingHeld() -
            DToken(dDAI).totalReserves();
        // clamp the amount of ddai to borrow between 1 wei and upperBound-1
        amount = clampBetween(amount, 1, upperBound - 1);

        dDAI.borrow(amount);

        // mint tokens and set the oracle prices of the system
        _setupLiquidatableStates(amount, daiPrice, usdcPrice);
        // ensure that the account can be liquidated
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

        (uint256 accountCollateral, , uint256 accountDebt) = marketManager
            .statusOf(address(this));
        // ensure that the collateral < accountDebt to be liquidated
        require(accountCollateral < accountDebt);
    }

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
    // baseCFactor: [MIN_BASE_CFACTOR/1e14, MAX_BASE_CFACTOR/1e14]
    // liqFee: [0, MAX_LIQUIDATION_FEE/1e14]
    // liqIncSoft: [MIN_LIQUIDATION_INCENTIVE() / 1e14 + liqFee, MAX_LIQUIDATION_INCENTIVE()/1e14-1]
    // liqIncHard: [liqIncSoft+1, MAX_LIQUIDATION_INCENTIVE/1e14]
    // inherently from above, liqIncSoft < liqIncHard
    // collReqHard = [liqIncHard + MIN_EXCESS_COLLATERAL_REQUIREMENT/1e14, MAX_COLLATERAL_REQUIREMENT()/1e14-1]
    // collReqSoft = [collReqHard+1, MAX_COLLATERAL_REQUIREMENT()/1e14]
    // collateralRatio = [0, min(MAX_COLLATERALIZATION_RATIO/1e14, (WAD*WAD)/(WAD+collReqSoft*1e14))]
    function _getSafeUpdateCollateralBounds(
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor
    ) private {
        safeBounds.baseCFactor = clampBetween(
            baseCFactor,
            marketManager.MIN_BASE_CFACTOR() / 1e14,
            marketManager.MAX_BASE_CFACTOR() / 1e14
        );

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
            safeBounds.liqIncSoft + 1,
            marketManager.MAX_LIQUIDATION_INCENTIVE() / 1e14
        );

        // collateral requirement soft -> hard goes down
        safeBounds.collReqHard = clampBetween(
            collReqHard,
            safeBounds.liqIncHard +
                marketManager.MIN_EXCESS_COLLATERAL_REQUIREMENT() /
                1e14,
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
                (collatPremium / 1e14)
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

    function _checkClosePositionPostConditions(
        address mtoken,
        uint256 preAssetsOfLength,
        string memory closePositionId,
        string memory collateralPostedId,
        string memory assetsLengthId
    ) private {
        assertWithMsg(
            !_hasPosition(mtoken),
            closePositionId,
            "closePosition should remove position in mtoken if successful"
        );
        assertWithMsg(
            _collateralPostedFor(mtoken) == 0,
            collateralPostedId,
            "closePosition should reduce collateralPosted for user to 0"
        );
        IMToken[] memory postAssetsOf = marketManager.assetsOf(address(this));
        assertWithMsg(
            preAssetsOfLength - 1 == postAssetsOf.length,
            assetsLengthId,
            "closePosition expected to remove asset from assetOf"
        );
    }

    function _checkPriceDivergence(
        address mtoken
    ) private view returns (bool divergenceTooLarge, bool priceError) {
        (uint256 lowerPrice, uint lowError) = OracleRouter(oracleRouter)
            .getPrice(mtoken, true, true);
        (uint256 higherPrice, uint highError) = OracleRouter(oracleRouter)
            .getPrice(mtoken, true, false);

        priceError = lowError == 2 || highError == 2;
        if (lowerPrice < 0 || higherPrice < 0) {
            priceError = true;
        }

        if (
            higherPrice - lowerPrice >
            OracleRouter(oracleRouter).badSourceDivergenceFlag()
        ) {
            divergenceTooLarge = true;
        }
    }

    function _checkLiquidatePreconditions(
        address account,
        address dtoken,
        address collateralToken
    ) internal {
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
    ) internal returns (uint256 clampedAmount) {
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
