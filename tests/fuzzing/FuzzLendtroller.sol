pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";

contract FuzzLendtroller is StatefulBaseMarket {
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

    function c_token_deposit(address mtoken, uint256 amount) public {
        amount = clampBetween(amount, 1, type(uint64).max);
        // require gauge pool has been started at a previous timestamp
        require(gaugePool.startTime() < block.timestamp);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.isListed(mtoken));

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

        // This step should mint associated shares for the user
        try MockCToken(mtoken).deposit(amount, address(this)) {} catch (
            bytes memory revertData
        ) {
            emit LogAddress("msg.sender", msg.sender);
            uint256 errorSelector = extractErrorSelector(revertData);

            emit LogUint256("error selector: ", errorSelector);
            assertWithMsg(
                false,
                "LENDTROLLER - expected mtoken.deposit() to be successful"
            );
        }
    }

    function post_collateral_should_succeed(
        address mtoken,
        uint256 tokens
    ) public {
        // require gauge pool has been started
        require(gaugePool.startTime() < block.timestamp);
        try
            lendtroller.postCollateral(address(this), mtoken, tokens)
        {} catch {}
    }

    function remove_collateral_should_succeed(
        address mtoken,
        uint256 tokens,
        bool closePositionIfPossible
    ) public {
        try
            lendtroller.removeCollateral(
                mtoken,
                tokens,
                closePositionIfPossible
            )
        {} catch {}
    }

    function removeCollateralIfNecessary_should_succeed(
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
        try lendtroller.closePosition(mToken) {} catch {}
    }

    function canMint_should_succeed(address mToken) public {
        try lendtroller.canMint(mToken) {} catch {}
    }

    function canRedeem(
        address mToken,
        address account,
        uint256 amount
    ) public {
        try lendtroller.canRedeem(mToken, account, amount) {} catch {}
    }

    function canRedeemWithCollateralRemoval_should_fail(
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
        {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeemWithCollateralRemoval should only be callable by mtoken"
            );
        } catch {}
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
    // Should always be <= a user's balanceOf() as you can only post collateral up to which you actually have inside the market.
    // CHECK: accountdata[address].collateralPosted <= marketToken.balanceOf(user)

    // Market collateral posted should always be <= caps, as all values are recorded in shares rather than # of tokens
    // accountdata[address].collateralPosted <= collateral caps per token

    //

    // Helper Functions
}
