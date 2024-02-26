pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract FuzzDTokenSystem is StatefulBaseMarket {
    /// @custom:property s-dtok-1 marketUnderlyingHeld() must always be equal to the underlying token balance of the dtoken contract
    /// @custom:precondition dtoken is one of the supported assets
    function marketUnderlyingHeld_equivalent_to_balanceOf_underlying(
        address dtoken
    ) public {
        _isSupportedDToken(dtoken);

        uint256 marketUnderlyingHeld = DToken(dtoken).marketUnderlyingHeld();

        address underlying = DToken(dtoken).underlying();
        uint256 underlyingBalance = IERC20(underlying).balanceOf(
            address(dtoken)
        );

        assertEq(
            marketUnderlyingHeld,
            underlyingBalance,
            "S-DTOK-1 - marketUnderlyingHeld should return dtoken.balanceOf(dtoken)"
        );
    }

    /// @custom:property s-dtok-2 decimals for dtoken must always be equal to the underlying's number of decimals
    /// @custom:precondition dtoken is one of the supported assets
    function decimals_for_dtoken_equivalent_to_underlying(
        address dtoken
    ) public {
        _isSupportedDToken(dtoken);
        address underlying = DToken(dtoken).underlying();

        assertEq(
            DToken(dtoken).decimals(),
            IERC20(underlying).decimals(),
            "S-DTOK-2 - decimals for dtoken must be equivalent to underlying decimals"
        );
    }

    // @custom:property s-dtok-3 isCToken() should return false for dtoken
    // @custom:precondition dtoken is either dUSDC or dDAI
    function isCToken_returns_false(address dtoken) public {
        _isSupportedDToken(dtoken);
        assertWithMsg(
            !DToken(dtoken).isCToken(),
            "S-DTOK-3 - isCToken() should return false"
        );
    }
}
