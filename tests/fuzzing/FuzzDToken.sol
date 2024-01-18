pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract FuzzDToken is StatefulBaseMarket {
    /// @custom:property dtok-1 calling DToken.mint should succeed with correct preconditions
    /// @custom:property dtok-2 underlying balance for sender DToken should decrease by amount
    /// @custom:property dtok-3  balance should increase by `amount * WAD/exchangeRateCached()`
    /// @custom:property dtok-4 DToken totalSupply should increase by `amount * WAD/exchangeRateCached()`
    /// @custom:precondition amount bound between [1, uint256.max]
    function mint_should_actually_succeed(
        address dtoken,
        uint256 amount,
        bool lower
    ) public {
        is_supported_dtoken(dtoken);
        require(gaugePool.startTime() < block.timestamp);
        check_price_feed();
        (bool mintingPossible, ) = address(lendtroller).call(
            abi.encodeWithSignature("canMint(address)", dtoken)
        );
        require(mintingPossible);
        // amount = clampBetweenBoundsFromOne(lower, amount);
        amount = clampBetween(amount, 1, type(uint64).max);
        address underlyingTokenAddress = DToken(dtoken).underlying();
        uint256 preUnderlyingBalance = IERC20(underlyingTokenAddress)
            .balanceOf(msg.sender);
        uint256 preDTokenBalance = DToken(dtoken).balanceOf(msg.sender);
        uint256 preDTokenTotalSupply = DToken(dtoken).totalSupply();

        require(mint_and_approve(underlyingTokenAddress, dtoken, amount));

        emit LogUint256(
            "exchange rate: ",
            DToken(dtoken).exchangeRateCached()
        );

        try DToken(dtoken).mint(amount) {
            uint256 postDTokenBalance = DToken(dtoken).balanceOf(msg.sender);
            uint256 adjustedNumberOfTokens = (amount * WAD) /
                DToken(dtoken).exchangeRateCached();
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

            uint256 postUnderlyingBalance = IERC20(underlyingTokenAddress)
                .balanceOf(msg.sender);
            // DTOK-2
            assertEq(
                preUnderlyingBalance - amount,
                postUnderlyingBalance,
                "DTOKEN - mint should reduce underlying token balance"
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

    /// @custom:property borrow should succeed with correct preconditions
    /// @custom:precondition token to borrow is either dUSDC or dDAI
    /// @custom:precondition amount is bound between [1, marketUnderlyingHeld() - totalReserves]
    /// @custom:precondition borrow is not paused
    /// @custom:precondition dtoken must be listed
    /// @custom:precondition user must not have a shortfall for respective token
    function borrow_should_succeed(address dtoken, uint256 amount) public {
        is_supported_dtoken(dtoken);
        check_price_feed();
        require(lendtroller.borrowPaused(dtoken) != 2);
        uint256 upperBound = DToken(dtoken).marketUnderlyingHeld() -
            DToken(dtoken).totalReserves();
        amount = clampBetween(amount, 1, upperBound - 1);
        require(lendtroller.isListed(dtoken));
        (, uint256 shortfall) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            dtoken,
            amount,
            0
        );
        emit LogUint256("shortfall:", shortfall);
        require(shortfall == 0);

        mint_and_approve(DToken(dtoken).underlying(), dtoken, amount);

        try DToken(dtoken).borrow(amount) {} catch {
            assertWithMsg(
                false,
                "DTOKEN - borrow should succeed with correct preconditions"
            );
        }
    }

    /// @custom:property marketUnderlyingHeld() must always be equal to the underlying token balance of the dtoken contract
    /// @custom:precondition dtoken is one of the supported assets
    function marketUnderlyingHeld_equivalent_to_balanceOf_underlying(
        address dtoken
    ) public {
        is_supported_dtoken(dtoken);

        uint256 marketUnderlyingHeld = DToken(dtoken).marketUnderlyingHeld();

        address underlying = DToken(dtoken).underlying();
        uint256 underlyingBalance = IERC20(underlying).balanceOf(
            address(dtoken)
        );

        assertEq(
            marketUnderlyingHeld,
            underlyingBalance,
            "DToken - marketUnderlyingHeld should return dtoken.balanceOf(dtoken)"
        );
    }

    /// @custom:property decimals for dtoken must always be equal to the underlying's number of decimals
    /// @custom:precondition dtoken is one of the supported assets
    function decimals_for_dtoken_equivalent_to_underlying(
        address dtoken
    ) public {
        is_supported_dtoken(dtoken);
        address underlying = DToken(dtoken).underlying();

        assertEq(
            DToken(dtoken).decimals(),
            IERC20(underlying).decimals(),
            "DToken - decimals for dtoken must be equivalent to underlying decimals"
        );
    }

    // @custom:property isCToken() should return false for dtoken
    // @custom:precondition dtoken is either dUSDC or dDAI
    function isCToken_returns_false(address dtoken) public {
        is_supported_dtoken(dtoken);
        assertWithMsg(
            !DToken(dtoken).isCToken(),
            "DTOKEN - isCToken() should return false"
        );
    }

    // Helper Function
    function is_supported_dtoken(address dtoken) private {
        require(dtoken == address(dUSDC) || dtoken == address(dDAI));
    }
}
