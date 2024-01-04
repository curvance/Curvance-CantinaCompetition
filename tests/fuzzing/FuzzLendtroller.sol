pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { IMToken } from "contracts/market/lendtroller/LiquidityManager.sol";

contract FuzzLendtroller is StatefulBaseMarket {
    MockDataFeed public mockUsdcFeed;
    MockDataFeed public mockDaiFeed;
    bool feedsSetup;
    uint256 lastRoundUpdate;

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
        } catch {}
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

    function c_token_deposit(address mtoken, uint256 amount) public {
        amount = clampBetween(amount, 1, type(uint32).max);
        // require gauge pool has been started at a previous timestamp
        require(gaugePool.startTime() < block.timestamp);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }

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
                "LENDTROLLER - pre and post ctoken balance should increase"
            );
        } catch (bytes memory revertData) {
            emit LogAddress("msg.sender", msg.sender);
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
        mockDaiFeed.setMockAnswer(1e18);
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

    // create a version to account for stale data
    function setCTokenCollateralCaps_should_succeed(
        address mtoken,
        uint256 cap
    ) public {
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        require(block.timestamp - lastRoundUpdate <= 24 hours);
        require(feedsSetup);
        require(centralRegistry.hasDaoPermissions(address(this)));
        cap = clampBetween(cap, 1, type(uint256).max);
        // require the token is not already listed into the lendtroller
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));

        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        // adjust the following to acount for dynamic numbers here instead
        try
            lendtroller.updateCollateralToken(
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
                "LENDTROLLER - updateCollateralToken should succeed"
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

        if (mtokenBalance == 0) {
            c_token_deposit(mtoken, tokens);
        }
        if (lendtroller.collateralCaps(mtoken) == 0) {
            setCTokenCollateralCaps_should_succeed(mtoken, tokens);
        }

        uint256 oldCollateral;
        try lendtroller.statusOf(address(this)) returns (
            uint256 accountCollat,
            uint256 accountDebt,
            uint256 debt
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
        if (min == 0) {
            min = 1;
        }
        tokens = clampBetween(tokens, min, max);
        uint256 oldCollateralPosted = lendtroller.collateralPosted(mtoken);

        (bool success, bytes memory rd) = address(lendtroller).call(
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
            lendtroller.hasPosition(mtoken, address(this)),
            "LENDTROLLER - addr(this) must have position after posting"
        );
        // ensure collateralPosted increases by tokens
        uint256 newCollateralPosted = lendtroller.collateralPosted(mtoken);
        assertEq(
            newCollateralPosted,
            oldCollateralPosted + tokens,
            "LENDTROLLER - global collateral posted should increase"
        );
    }

    function remove_collateral_should_succeed(
        address mtoken,
        uint256 tokens,
        bool closePositionIfPossible
    ) public {
        require(lendtroller.hasPosition(mtoken, address(this)));
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        (uint256 oldCollateral, , ) = lendtroller.statusOf(address(this));
        tokens = clampBetween(tokens, oldCollateral, type(uint64).max);
        try
            lendtroller.removeCollateral(
                mtoken,
                tokens,
                closePositionIfPossible
            )
        {} catch {}
    }

    function removeCollateralIfNecessary_should_fail_with_wrong_caller(
        address mToken,
        uint256 balance,
        uint256 amount
    ) public {
        try
            lendtroller.reduceCollateralIfNecessary(
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
                false,
                "LENDTROLLER - canMint() should have not reverted"
            );
        }
    }

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
    } x

    function canMint_should_revert_when_mint_is_paused(
        address mToken
    ) public {
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

    function canRedeem(
        address mToken,
        address account,
        uint256 amount
    ) public {
        try lendtroller.canRedeem(mToken, account, amount) {} catch {}
    }

    function canRedeemWithCollateralRemoval_should_succeed(
        address account,
        address mToken,
        uint256 balance,
        uint256 amount,
        bool forceRedeemCollateral
    ) public {
        try
            lendtroller.canRedeemWithCollateralRemoval(
                account,
                mToken,
                balance,
                amount,
                forceRedeemCollateral
            )
        {} catch {}
    }

    function canBorrow_should_succeed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) != 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch {}
    }

    function canBorrow_should_fail_when_borrow_is_paused(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) == 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch {}
    }

    function canBorrow_should_fail_when_token_is_unlisted(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) != 2);
        require(!lendtroller.isListed(mToken));
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch {}
    }

    function canBorrowWithNotify_should_succeed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        try
            lendtroller.canBorrowWithNotify(mToken, account, amount)
        {} catch {}
    }

    function notifyBorrow_should_succeed(
        address mToken,
        address account
    ) public {
        try lendtroller.notifyBorrow(mToken, account) {} catch {}
    }

    function canRepay_should_succeed(address mToken, address account) public {
        try lendtroller.canRepay(mToken, account) {} catch {}
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

    function canSeize_should_succeed(
        address collateralToken,
        address debtToken
    ) public {
        try lendtroller.canSeize(collateralToken, debtToken) {} catch {}
    }

    function canTransfer_should_succeed(
        address mToken,
        address from,
        uint256 amount
    ) public {
        try lendtroller.canTransfer(mToken, from, amount) {} catch {}
    }

    function liquidateAccount_should_succeed(address account) public {
        try lendtroller.liquidateAccount(account) {} catch {}
    }

    function listToken_should_succeed(address token) public {
        try lendtroller.listToken(token) {} catch {}
    }

    // Stateful Functions

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
}
