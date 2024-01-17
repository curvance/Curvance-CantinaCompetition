pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract FuzzDToken is StatefulBaseMarket {
    // @custom:property borrow should succeed with correct preconditions
    // @custom:precondition token to borrow is either dUSDC or dDAI
    // @custom:precondition borrow is not paused
    // @custom:precondition dtoken must be listed
    // @custom:precondition user must not have a shortfall for respective token
    function borrow_should_succeed(address dtoken, uint256 amount) public {
        is_supported_dtoken(dtoken);
        require(lendtroller.borrowPaused(dtoken) != 2);
        amount = clampBetween(amount, 1, type(uint64).max);
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
