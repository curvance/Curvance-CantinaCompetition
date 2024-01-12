pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { IMToken } from "contracts/market/lendtroller/LiquidityManager.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract FuzzLendtroller is StatefulBaseMarket {
    MockDataFeed public mockUsdcFeed;
    MockDataFeed public mockDaiFeed;
    bool feedsSetup;
    uint256 lastRoundUpdate;
    mapping(address => bool) setCollateralValues;
    mapping(address => bool) collateralCapsUpdated;
    mapping(address => bool) postedCollateral;

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

    // @property: calling listToken for a token should succeed
    // @precondition: mtoken must not already be listed
    // @precondition: mtoken must be one of: cDAI, cUSDC
    function list_token_should_succeed(address mtoken) public {
        uint256 amount = 42069;
        // require the token is not already listed into the lendtroller
        require(!lendtroller.isListed(mtoken));

        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        address underlyingAddress = MockCToken(mtoken).underlying();
        IERC20 underlying = IERC20(underlyingAddress);

        try lendtroller.listToken(mtoken) {
            assertWithMsg(
                lendtroller.isListed(mtoken),
                "LENDTROLLER - lendtroller.listToken() should succeed"
            );
        } catch {
            assertWithMsg(false, "LENDTROLLER - failed to list token");
        }
    }

    // @property: calling listToken() for a token that already exists should fail
    // @precondition: mtoken must already be listed
    // @precondition: mtoken must be one of: cDAI, cUSDC
    function list_token_should_fail_if_already_listed(address mtoken) public {
        uint256 amount = 42069;
        // require the token is not already listed into the lendtroller
        require(lendtroller.isListed(mtoken));

        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        address underlyingAddress = MockCToken(mtoken).underlying();
        IERC20 underlying = IERC20(underlyingAddress);

        try lendtroller.listToken(mtoken) {
            assertWithMsg(
                false,
                "LENDTROLLER - listToken for duplicate token should not be possible"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_tokenAlreadyListedSelectorHash,
                "LENDTROLLER - listToken() expected TokenAlreadyListed selector hash on failure"
            );
        }
    }

    // function c_token_depositAsCollateral(
    //     address mtoken,
    //     uint256 amount
    // ) public {
    //     amount = clampBetween(amount, 1, type(uint32).max);
    //     // require gauge pool has been started at a previous timestamp
    //     require(gaugePool.startTime() < block.timestamp);
    //     require(mtoken == address(cDAI) || mtoken == address(cUSDC));
    //     if (!lendtroller.isListed(mtoken)) {
    //         list_token_should_succeed(mtoken);
    //     }

    //     address underlyingAddress = MockCToken(mtoken).underlying();
    //     // mint ME enough tokens to cover deposit
    //     try MockToken(underlyingAddress).mint(amount) {} catch {
    //         assertWithMsg(
    //             false,
    //             "LENDTROLLER - mint underlying amount should succeed before deposit"
    //         );
    //     }
    //     // approve sufficient underlying tokens prior to calling deposit
    //     try MockToken(underlyingAddress).approve(mtoken, amount) {} catch {
    //         assertWithMsg(
    //             false,
    //             "LENDTROLLER - approve underlying amount should succeed before deposit"
    //         );
    //     }
    //     uint256 preCTokenBalanceThis = MockCToken(mtoken).balanceOf(
    //         address(this)
    //     );

    //     // This step should mint associated shares for the user
    //     try MockCToken(mtoken).depositAsCollateral(amount, address(this)) {
    //         uint256 postCTokenBalanceThis = MockCToken(mtoken).balanceOf(
    //             address(this)
    //         );

    //         assertLt(
    //             preCTokenBalanceThis,
    //             postCTokenBalanceThis,
    //             "LENDTROLLER - pre and post ctoken balance should increase"
    //         );
    //     } catch (bytes memory revertData) {
    //         emit LogAddress("msg.sender", msg.sender);
    //         uint256 errorSelector = extractErrorSelector(revertData);

    //         emit LogUint256("error selector: ", errorSelector);
    //         assertWithMsg(
    //             false,
    //             "LENDTROLLER - expected mtoken.deposit() to be successful"
    //         );
    //     }
    // }

    // @property: After depositing, the ctoken balance should increase
    // @precondition: amount bound between [1, uint16.max], inclusively
    // @precondition: GaugePool must have been started before block.timestamp
    // @precondition: mtoken must be one of: cDAI, cUSDC
    // @precondition: mtoken must be listed in Lendtroller
    // @precondition: minting must not be paused
    function c_token_deposit(address mtoken, uint256 amount) public {
        amount = clampBetween(amount, 1, type(uint16).max);
        require(gaugePool.startTime() < block.timestamp);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(lendtroller.mintPaused(mtoken) != 2);

        address underlyingAddress = MockCToken(mtoken).underlying();
        // mint ME enough tokens to cover deposit
        try MockToken(underlyingAddress).mint(amount) {} catch {
            uint256 currentSupply = MockToken(underlyingAddress).totalSupply();

            // if the total supply overflowed, then this is actually expected to revert
            if (currentSupply + amount < currentSupply) {
                return;
            }

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
        // TODO: investigate 20 min hold period for debt token ()
        try MockCToken(mtoken).deposit(amount, address(this)) {
            uint256 postCTokenBalanceThis = MockCToken(mtoken).balanceOf(
                address(this)
            );

            assertLt(
                preCTokenBalanceThis,
                postCTokenBalanceThis,
                "LENDTROLLER - pre and post ctoken balance should increase"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            emit LogUint256("error selector: ", errorSelector);
            assertWithMsg(
                false,
                "LENDTROLLER - expected mtoken.deposit() to be successful"
            );
        }
    }

    function setUpFeeds() public {
        require(centralRegistry.hasElevatedPermissions(address(this)));
        require(gaugePool.startTime() < block.timestamp);
        // use mock pricing for testing
        // StatefulBaseMarket - chainlinkAdaptor - usdc, dai
        mockUsdcFeed = new MockDataFeed(address(chainlinkUsdcUsd));
        chainlinkAdaptor.addAsset(address(cUSDC), address(mockUsdcFeed), true);
        dualChainlinkAdaptor.addAsset(
            address(cUSDC),
            address(mockUsdcFeed),
            true
        );
        mockDaiFeed = new MockDataFeed(address(chainlinkDaiUsd));
        chainlinkAdaptor.addAsset(address(cDAI), address(mockDaiFeed), true);
        dualChainlinkAdaptor.addAsset(
            address(cDAI),
            address(mockDaiFeed),
            true
        );

        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkDaiUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        priceRouter.addMTokenSupport(address(cDAI));
        priceRouter.addMTokenSupport(address(cUSDC));

        feedsSetup = true;
        lastRoundUpdate = block.timestamp;
    }

    // @property: collateralCaps[mtoken] after calling setCTokenCollateralCaps is updated
    // @precondition: price feed must be recent
    // @precondition: price feed must be setup
    // @precondition: address(this) must have dao permissions
    // @precondition: cap is bound between [1, uint256.max], inclusive
    // @precondition: mtoken must be listed in the Lendtroller
    // @precondition: get_safe_update_collateral_bounds must be in correct bounds
    function updateCollateralToken_should_succeed(
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
        require(feedsSetup);
        require(centralRegistry.hasDaoPermissions(address(this)));
        cap = clampBetween(cap, 1, type(uint256).max);
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));

        TokenCollateralBounds
            memory bounds = get_safe_update_collateral_bounds(
                collRatio,
                collReqSoft,
                collReqHard,
                liqIncSoft,
                liqIncHard,
                liqFee,
                baseCFactor
            );
        require(chainlinkUsdcUsd.latestAnswer() > 0);
        require(chainlinkDaiUsd.latestAnswer() > 0);
        check_price_feed();
        try
            lendtroller.updateCollateralToken(
                IMToken(address(mtoken)),
                bounds.collRatio,
                bounds.collReqSoft,
                bounds.collReqHard,
                bounds.liqIncSoft,
                bounds.liqIncHard,
                bounds.liqFee,
                bounds.baseCFactor
            )
        {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - updateCollateralToken should succeed"
            );
        }
        setCollateralValues[mtoken] = true;
    }

    function setCToken_should_succeed(address mtoken, uint256 cap) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(setCollateralValues[mtoken]);
        check_price_feed();

        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "setCTokenCollateralCaps(address[],uint256[])",
                tokens,
                caps
            )
        );

        if (success) {
            assertGte(
                lendtroller.collateralCaps(mtoken),
                0,
                "LENDTROLLER - collateral caps for token should be >=0"
            );
        } else {
            assertWithMsg(
                false,
                "LENDTROLLER - expected setCTokenCollateralCaps to succeed"
            );
        }

        collateralCapsUpdated[mtoken] = true;
    }

    // @property: updateCollateralToken should revert if the price feed is out of date
    // @precondition: price feed is out of date
    // @precondition: cap is bound between [1, uint256.max], inclusive
    // @precondition: mtoken must be listed in Lendtroller
    // @precondition: mtoken must be one of: cDAI, cUSDC
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
        cap = clampBetween(cap, 1, type(uint256).max);
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        TokenCollateralBounds
            memory bounds = get_safe_update_collateral_bounds(
                collRatio,
                collReqSoft,
                collReqHard,
                liqIncSoft,
                liqIncHard,
                liqFee,
                baseCFactor
            );
        try
            lendtroller.updateCollateralToken(
                IMToken(address(mtoken)),
                bounds.collRatio,
                bounds.collReqSoft,
                bounds.collReqHard,
                bounds.liqIncSoft,
                bounds.liqIncHard,
                bounds.liqFee,
                bounds.baseCFactor
            )
        {
            assertWithMsg(
                false,
                "LENDTROLLER - updateCollateralToken should not have succeeded with out of date price feeds"
            );
        } catch {}
    }

    // @property: Ensure account collateral has increased by # of tokens
    // @property: Ensure user has a valid position after posting
    // @property: Ensure collateralPosted (for mtoken) has increased by # of tokens
    // @precondition: price feed is up to date
    // @precondition: address(this) must have a balance of mtoken
    // @precondition: `tokens` to be posted is bound between [1, mtoken balance], inclusive
    // @precondition: msg.sender for postCollateral = address(this)
    function post_collateral_should_succeed(
        address mtoken,
        uint256 tokens
    ) public {
        if (!collateralCapsUpdated[mtoken]) {
            setCToken_should_succeed(mtoken, tokens);
        }
        check_price_feed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(mtoken, tokens * IMToken(mtoken).decimals());
        }
        uint256 mtokenBalance = IMToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );
        uint256 collateralCaps = lendtroller.collateralCaps(mtoken);

        uint256 oldCollateralForToken = lendtroller.collateralPosted(mtoken);
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
            (bool success, bytes memory revertData) = address(lendtroller)
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
                    "LENDTROLLER - expected postCollateral to pass with @precondition"
                );
            }
            // ensure account collateral has increased by # of tokens
            uint256 newCollateralForUser = lendtroller.collateralPostedFor(
                mtoken,
                address(this)
            );

            assertEq(
                newCollateralForUser,
                oldCollateralForUser + tokens,
                "LENDTROLLER - new collateral must collateral+tokens"
            );
            // ensure that a user has a position after posting
            assertWithMsg(
                lendtroller.hasPosition(mtoken, address(this)),
                "LENDTROLLER - addr(this) must have position after posting"
            );
            // ensure collateralPosted increases by tokens
            uint256 newCollateralForToken = lendtroller.collateralPosted(
                mtoken
            );
            assertEq(
                newCollateralForToken,
                oldCollateralForToken + tokens,
                "LENDTROLLER - global collateral posted should increase"
            );
        }
        postedCollateral[mtoken] = true;
        postedCollateralAt[mtoken] = block.timestamp;
    }

    // @property: postCollateral with token bounded too large should fail
    // @precondition: collateral caps for the token are >0
    // @precondition: price feed must be out of date
    // @precondition: user must have mtoken balance
    function post_collateral_should_fail_too_many_tokens(
        address mtoken,
        uint256 tokens
    ) public {
        require(collateralCapsUpdated[mtoken]);
        check_price_feed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(mtoken, tokens * IMToken(mtoken).decimals());
        }
        uint256 mtokenBalance = IMToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );

        // collateralPosted + tokens <= mtoken.balanceOf(address(this))
        // tokens <= mtoken.balanceOf(address(this)) - collateralPosted
        tokens = clampBetween(
            tokens,
            mtokenBalance - oldCollateralForUser + 1,
            type(uint64).max
        );

        uint256 oldCollateralForToken = lendtroller.collateralPosted(mtoken);

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "postCollateral(address,address,uint256)",
                address(this),
                mtoken,
                tokens
            )
        );

        assertWithMsg(
            !success,
            "LENDTROLLER - postCollateral() with too many tokens should fail"
        );
    }

    // @property: Global posted collateral for the token should decrease by removed amount
    // @property: User posted collateral for token should decrease by removed amount
    // @property: If there is a shortfall, the removeCollateral call should fail
    // @property: If there is no shortfall, the removeCollateral call should succeed
    // @precondition: price feed must be recent
    // @precondition: mtoken is one of: cDAI, cUSDC
    // @precondition: mtoken must be listed in the Lendtroller
    // @precondition: current timestamp must exceed the MIN_HOLD_PERIOD from postCollateral timestamp
    // @precondition: token is clamped between [1, collateralForUser]
    // @precondition: redeemPaused flag must not be set
    function remove_collateral_should_succeed(
        address mtoken,
        uint256 tokens,
        bool closePositionIfPossible
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(postedCollateral[mtoken]);
        require(lendtroller.isListed(mtoken));
        check_price_feed();

        require(
            block.timestamp >
                postedCollateralAt[mtoken] + lendtroller.MIN_HOLD_PERIOD()
        );
        require(lendtroller.hasPosition(mtoken, address(this)));
        require(lendtroller.redeemPaused() != 2);

        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );
        tokens = clampBetween(tokens, 1, oldCollateralForUser);

        uint256 oldCollateralPostedForToken = lendtroller.collateralPosted(
            mtoken
        );
        (, uint256 shortfall) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            tokens,
            0
        );

        if (shortfall > 0) {
            (bool success, bytes memory revertData) = address(lendtroller)
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
                        lendtroller_insufficientCollateralSelectorHash,
                    "LENDTROLLER - reduceCollateralIfNecessary expected to revert with insufficientCollateral"
                );
            }
        } else {
            (bool success, bytes memory rd) = address(lendtroller).call(
                abi.encodeWithSignature(
                    "removeCollateral(address,uint256,bool)",
                    mtoken,
                    tokens,
                    closePositionIfPossible
                )
            );
            // Collateral posted for the mtoken should decrease
            uint256 newCollateralPostedForToken = lendtroller.collateralPosted(
                mtoken
            );
            assertEq(
                newCollateralPostedForToken,
                oldCollateralPostedForToken - tokens,
                "LENDTROLLER - global collateral posted should decrease"
            );

            // Collateral posted for the user should decrease
            uint256 newCollateralForUser = lendtroller.collateralPostedFor(
                mtoken,
                address(this)
            );
            assertEq(
                newCollateralForUser,
                oldCollateralForUser - tokens,
                "LENDTROLLER - user collateral posted should decrease"
            );
            if (newCollateralForUser == 0 && closePositionIfPossible) {
                assertWithMsg(
                    !lendtroller.hasPosition(mtoken, address(this)),
                    "LENDTROLLER - closePositionIfPossible flag set should remove a user's position"
                );
            }
        }
    }

    // @property: removeCollateral should REVERT when no position exists
    // @precondition: mtoken is either of: cDAI or cUSDC
    // @precondition: token must be listed in Lendtroller
    // @precondition: price feed must be up to date
    // @precondition: user must NOT have an existing position
    function removeCollateral_should_fail_with_non_existent_position(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.isListed(mtoken));
        check_price_feed();
        require(!lendtroller.hasPosition(mtoken, address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
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
                "LENDTROLLER - removeCollateral should fail with non existent position"
            );
        } else {
            // expectation is that this should fail
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_invariantErrorSelectorHash,
                "LENDTROLLER - expected removeCollateral to revert with InvariantError"
            );
        }
    }

    // @property: removeCollateral should REVERT when trying to remove too much
    // @precondition: mtoken is either of: cDAI or cUSDC
    // @precondition: token must be listed in Lendtroller
    // @precondition: price feed must be up to date
    // @precondition: user must have an existing position
    // @precondition: tokens to remove is bound between [existingCollateral+1, uint32.max]
    function removeCollateral_should_fail_with_removing_too_many_tokens(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.isListed(mtoken));
        check_price_feed();
        require(lendtroller.hasPosition(mtoken, address(this)));
        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );

        tokens = clampBetween(
            tokens,
            oldCollateralForUser + 1,
            type(uint32).max
        );

        (bool success, bytes memory revertData) = address(lendtroller).call(
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
                "LENDTROLLER - removeCollateral should fail insufficient collateral"
            );
        } else {
            // expectation is that this should fail
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    lendtroller_insufficientCollateralSelectorHash,
                "LENDTROLLER - expected removeCollateral to revert with InsufficientCollateral when attempting to remove too much"
            );
        }
    }

    // @property: reduceCollateralIfNecessary should revert with unauthorized if called directly
    // @precondition: msg.sender != mtoken
    function reduceCollateralIfNecessary_should_fail_with_wrong_caller(
        address mtoken,
        uint256 amount
    ) public {
        require(msg.sender != mtoken);
        try
            lendtroller.reduceCollateralIfNecessary(
                address(this),
                mtoken,
                IMToken(mtoken).balanceOf(address(this)),
                amount
            )
        {} catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_unauthorizedSelectorHash,
                "LENDTROLLER - reduceCollateralIfNecessary expected to revert"
            );
        }
    }

    // @property: Calling closePosition should remove a position in the mtoken if sucessful
    // @property: Calling closePosition should set collateralPostedFor(mtoken, user) = 0
    // @property: Calling closePosition should reduce user asset list by 1 element
    // @precondition: token must be cDAI or cUSDC
    // @precondition: token must have an existing position
    // @precondition: collateralPostedForUser for respective token > 0
    function closePosition_should_succeed(address mtoken) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.hasPosition(mtoken, address(this)));
        uint256 collateralPostedForUser = lendtroller.collateralPostedFor(
            address(mtoken),
            address(this)
        );
        IMToken[] memory preAssetsOf = lendtroller.assetsOf(address(this));

        (bool success, bytes memory rd) = address(lendtroller).call(
            abi.encodeWithSignature("closePosition(address)", mtoken)
        );
        if (!success) {} else {
            check_close_position_post_conditions(mtoken, preAssetsOf.length);
        }
    }

    // @property: Calling closePosition should remove a position in the mtoken if sucessful
    // @property: Calling closePosition should set collateralPostedFor(mtoken, user) = 0
    // @property: Calling closePosition should reduce user asset list by 1 element
    // @precondition: token must be cDAI or cUSDC
    // @precondition: token must have an existing position
    // @precondition: collateralPostedForUser for respective token = 0
    function closePosition_should_succeed_if_collateral_is_0(
        address mtoken
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.hasPosition(mtoken, address(this)));
        uint256 collateralPostedForUser = lendtroller.collateralPostedFor(
            address(mtoken),
            address(this)
        );
        require(collateralPostedForUser == 0);
        IMToken[] memory preAssetsOf = lendtroller.assetsOf(address(this));

        (bool success, bytes memory rd) = address(lendtroller).call(
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
            !lendtroller.hasPosition(mtoken, address(this)),
            "LENDTROLLER - closePosition should remove position in mtoken if successful"
        );
        assertWithMsg(
            lendtroller.collateralPostedFor(mtoken, address(this)) == 0,
            "LENDTROLLER - closePosition should reduce collateralPosted for user to 0"
        );
        IMToken[] memory postAssetsOf = lendtroller.assetsOf(address(this));
        assertWithMsg(
            preAssetsOfLength - 1 == postAssetsOf.length,
            "LENDTROLLER - closePosition expected to remove asset from assetOf"
        );
    }

    function liquidateAccount_should_succeed(address account) public {
        try lendtroller.liquidateAccount(account) {} catch {}
    }

    // Stateful Functions

    // if closing position with a dtoken, ensure position cannot be created
    // invariant: for any dtoken, collateralPostedFor(dtoken, addr(this)) = 0

    // system invariant:
    // should not have an active position in a dtoken if one does not have debt

    // ctoken.balanceOf(user) >= collateral posted
    function cToken_balance_gte_collateral_posted(address ctoken) public {
        uint256 cTokenBalance = MockCToken(ctoken).balanceOf(address(this));

        uint256 collateralPostedForAddress = lendtroller.collateralPosted(
            address(this)
        );

        assertGte(
            cTokenBalance,
            collateralPostedForAddress,
            "LENDTROLLER - cTokenBalance must exceed collateral posted"
        );
    }

    // Market collateral posted should always be <= caps, as all values are recorded in shares rather than # of tokens
    // accountdata[address].collateralPosted <= collateral caps per token
    function collateralPosted_lte_collateralCaps(address token) public {
        uint256 collateralPosted = lendtroller.collateralPosted(token);

        uint256 collateralCaps = lendtroller.collateralCaps(token);

        assertLte(
            collateralPosted,
            collateralCaps,
            "LENDTROLLER - collateralPosted must be <= collateralCaps"
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
    ) private returns (TokenCollateralBounds memory bounds) {
        // TODO: incorrect for new rebase (min: 10%, max: 50%)
        bounds.baseCFactor = clampBetween(baseCFactor, 1, 1e18 / 1e14);

        // liquidity incentive soft -> hard goes up
        bounds.liqFee = clampBetween(
            liqFee,
            0,
            lendtroller.MAX_LIQUIDATION_FEE() / 1e14
        );

        bounds.liqIncSoft = clampBetween(
            liqIncSoft,
            lendtroller.MIN_LIQUIDATION_INCENTIVE() / 1e14 + bounds.liqFee,
            lendtroller.MAX_LIQUIDATION_INCENTIVE() / 1e14 - 1
        );

        bounds.liqIncHard = clampBetween(
            liqIncHard,
            bounds.liqIncSoft + 1, // TODO expected changes in rebase
            lendtroller.MAX_LIQUIDATION_INCENTIVE() / 1e14
        );

        // collateral requirement soft -> hard goes down
        bounds.collReqHard = clampBetween(
            collReqHard,
            bounds.liqIncHard, // account for MIN_EXCESS_COLLATERAL_REQUIREMENT  on rebase
            lendtroller.MAX_COLLATERAL_REQUIREMENT() / 1e14 - 1
        );

        bounds.collReqSoft = clampBetween(
            collReqSoft,
            bounds.collReqHard + 1,
            lendtroller.MAX_COLLATERAL_REQUIREMENT() / 1e14
        );

        uint256 collatPremium = uint256(
            ((WAD * WAD) / (WAD + (bounds.collReqSoft * 1e14)))
        );

        if (lendtroller.MAX_COLLATERALIZATION_RATIO() > collatPremium) {
            bounds.collRatio = clampBetween(
                collRatio,
                0,
                (collatPremium / 1e14) // collat ratio is going to be *1e14, so make sure that it will not overflow
            );
            emit LogUint256(
                "collateral ratio clamped to collateralization premium:",
                bounds.collRatio
            );
        } else {
            bounds.collRatio = clampBetween(
                collRatio,
                0,
                lendtroller.MAX_COLLATERALIZATION_RATIO() / 1e14
            );
            emit LogUint256(
                "collateral ratio clamped to max collateralization ratio:",
                bounds.collRatio
            );
        }
    }

    // If the price is stale, update the round data and update lastRoundUpdate
    function check_price_feed() public {
        // if lastRoundUpdate timestamp is stale
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        emit LogUint256("***********last round update: ", lastRoundUpdate);
        emit LogUint256(
            "-----------chainlink usdc",
            chainlinkUsdcUsd.latestTimestamp()
        );
        if (block.timestamp - chainlinkUsdcUsd.latestTimestamp() > 24 hours) {
            // TODO: Change this to a loop to loop over lendtroller.assetsOf()
            // Save a mapping of assets -> chainlink oracle
            // call updateRoundData on each oracle
            chainlinkUsdcUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
            chainlinkDaiUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
        }
        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        lastRoundUpdate = block.timestamp;
    }
}
