pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";

contract FuzzMarketManagerSystem is StatefulBaseMarket {
    // Stateful Functions

    // if closing position with a dtoken, ensure position cannot be created
    // invariant: for any dtoken, collateralPostedFor(dtoken, addr(this)) = 0

    // system invariant:
    // should not have an active position in a dtoken if one does not have debt

    /// @custom:property s-market-1 A user’s cToken balance must always be greater than the total collateral posted for a ctoken.
    function cToken_balance_gte_collateral_posted(address ctoken) public {
        uint256 cTokenBalance = MockToken(ctoken).balanceOf(address(this));

        uint256 collateralPostedForAddress = marketManager.collateralPosted(
            address(this)
        );

        assertGte(
            cTokenBalance,
            collateralPostedForAddress,
            "MARKET MANAGER - cTokenBalance must exceed collateral posted"
        );
    }

    /// @custom:property s-market-2 Market collateral posted should always be less than or equal to collateralCaps for a token.
    function collateralPosted_lte_collateralCaps(address token) public {
        uint256 collateralPosted = marketManager.collateralPosted(token);

        if (maxCollateralCap[token] == 0) {
            assertEq(
                collateralPosted,
                maxCollateralCap[token],
                "MARKET MANAGER - collateralPosted must be equal to 0 when max collateral is posted"
            );
        } else {
            assertLt(
                collateralPosted,
                maxCollateralCap[token],
                "MARKET MANAGER - collateralPosted must be strictly less than the max collateral posted"
            );
        }
    }

    // @custom:property s-market-3 totalSupply should never be zero for any mtoken once added to marketManager
    function totalSupply_of_listed_token_is_never_zero(address mtoken) public {
        require(marketManager.isListed(mtoken));
        assertNeq(
            MockToken(mtoken).totalSupply(),
            0,
            "IMToken - totalSupply should never go down to zero once listed"
        );
    }

    function hypotheticalLiquidityOf_no_excess_liquidity_for_amount_greater_than_posted(
        address mtoken,
        uint256 amount
    ) public {
        _isSupportedDToken(mtoken);

        (
            bool hasPosition,
            uint256 balanceOf,
            uint256 collateralPosted
        ) = marketManager.tokenDataOf(address(this), mtoken);
        require(hasPosition);
        amount = clampBetween(amount, collateralPosted + 1, type(uint256).max);
        (uint256 excessLiquidity, uint256 liquidityDeficit) = marketManager
            .hypotheticalLiquidityOf(address(this), mtoken, 0, amount);
        assertEq(
            excessLiquidity,
            0,
            "MARKET MANAGER - calling hypothetical liquidity of for an amount greater than posted should result in no excess"
        );
        assertGt(
            liquidityDeficit,
            0,
            "MARKET MANAGER - calling hypothetical liquidity of for an amount greater than posted should result in error"
        );
    }

    // current debt > max allowed debt after folding
}
