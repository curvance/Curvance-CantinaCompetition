// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

contract VelodromeStablePositionVault is BasePositionVault {
    using Math for uint256;

    /// TYPES ///

    struct StrategyData {
        IVeloGauge gauge; // Velodrome Gauge contract
        IVeloPairFactory pairFactory; // Velodrome Pair Factory contract
        IVeloRouter router; // Velodrome Router contract
        address token0; // LP first token address
        address token1; // LP second token address
        uint256 decimalsA; // token0 decimals
        uint256 decimalsB; // token1 decimals
    }

    /// CONSTANTS ///

    ERC20 public constant rewardToken =
        ERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);

    uint256 public immutable rewardTokenDecimals;
    bool public immutable rewardTokenIsUnderlying;

    /// STORAGE ///

    StrategyData public strategyData; // position vault packed configuration

    /// Token => underlying token of the sAMM LP or not
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// CONSTRUCTOR ///

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        IVeloGauge gauge,
        IVeloPairFactory pairFactory,
        IVeloRouter router
    ) BasePositionVault(asset_, centralRegistry_) {
        // Cache assigned asset address
        address _asset = asset();
        // Validate that we have the proper gauge linked with the proper LP
        // and pair factory
        require(
            gauge.stakingToken() == _asset &&
                address(pairFactory) == router.factory(),
            "VelodromeStablePositionVault: improper velodrome vault config"
        );

        // Query underlying token data from the pool
        strategyData.token0 = IVeloPool(_asset).token0();
        strategyData.token1 = IVeloPool(_asset).token1();
        strategyData.decimalsA = 10 ** ERC20(strategyData.token0).decimals();
        strategyData.decimalsB = 10 ** ERC20(strategyData.token0).decimals();

        strategyData.gauge = gauge;
        strategyData.router = router;
        strategyData.pairFactory = pairFactory;

        isUnderlyingToken[strategyData.token0] = true;
        isUnderlyingToken[strategyData.token1] = true;

        rewardTokenDecimals = rewardToken.decimals();
        rewardTokenIsUnderlying = (address(rewardToken) ==
            strategyData.token0 ||
            address(rewardToken) == strategyData.token1);
    }

    /// PUBLIC FUNCTIONS ///

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards
    /// @dev Only callable by Gelato Network bot
    /// @param data Bytes array for aggregator swap data
    /// @return yield The amount of new assets acquired from compounding vault yield
    function harvest(
        bytes calldata data
    ) external override onlyHarvestor vaultActive returns (uint256 yield) {
        uint256 pending = _calculatePendingRewards();

        if (pending > 0) {
            // claim vested rewards
            _vestRewards(_totalAssets + pending);
        }

        // can only harvest once previous reward period is done
        if (_checkVestStatus(_vaultData)) {
            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim velodrome rewards
            sd.gauge.getReward(address(this));

            SwapperLib.Swap memory swapData = abi.decode(
                data,
                (SwapperLib.Swap)
            );
            uint256 rewardAmount = rewardToken.balanceOf(address(this));

            if (rewardAmount > 0) {
                // take protocol fee
                uint256 protocolFee = rewardAmount.mulDivDown(
                    centralRegistry.protocolHarvestFee(),
                    1e18
                );
                rewardAmount -= protocolFee;
                SafeTransferLib.safeTransfer(
                    address(rewardToken),
                    centralRegistry.feeAccumulator(),
                    protocolFee
                );

                // swap from VELO to underlying LP token if necessary
                if (!rewardTokenIsUnderlying) {
                    SwapperLib.swap(swapData);
                }
            }

            // swap token0 to LP Token underlying tokens
            uint256 totalAmountA = ERC20(sd.token0).balanceOf(address(this));

            require(
                totalAmountA > 0,
                "VelodromeStablePositionVault: slippage error"
            );

            (uint256 r0, uint256 r1, ) = IVeloPair(asset()).getReserves();
            (uint256 reserveA, uint256 reserveB) = sd.token0 ==
                IVeloPair(asset()).token0()
                ? (r0, r1)
                : (r1, r0);
            uint256 swapAmount = _optimalDeposit(
                totalAmountA,
                reserveA,
                reserveB,
                sd.decimalsA,
                sd.decimalsB
            );

            _swapExactTokensForTokens(sd.token0, sd.token1, swapAmount);
            totalAmountA -= swapAmount;

            // add liquidity to velodrome lp
            yield = _addLiquidity(
                sd.token0,
                sd.token1,
                totalAmountA,
                ERC20(sd.token1).balanceOf(address(this)) // totalAmountB
            );

            // deposit assets into velodrome gauge
            _deposit(yield);

            // update vesting info
            // Cache vest period so we do not need to load it twice
            uint256 _vestPeriod = vestPeriod;
            _vaultData = _packVaultData(yield.mulDivDown(expScale, _vestPeriod), block.timestamp + _vestPeriod);


            emit Harvest(yield);
        }
        // else yield is zero
    }

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into velodrome gauge pool
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        IVeloGauge gauge = strategyData.gauge;
        SafeTransferLib.safeApprove(
            asset(),
            address(gauge),
            assets
        );
        gauge.deposit(assets);
    }

    /// @notice Withdraws specified amount of assets from velodrome gauge pool
    /// @param assets The amount of assets to withdraw
    function _withdraw(uint256 assets) internal override {
        strategyData.gauge.withdraw(assets);
    }

    /// @notice Gets the balance of assets inside velodrome gauge pool
    /// @return The current balance of assets
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return strategyData.gauge.balanceOf(address(this));
    }

    /// @notice Calculates the optimal amount of TokenA to swap to TokenB
    ///         for a perfect LP deposit for a stable pair
    /// @param amountA The amount of `token0` this vault has currently
    /// @param reserveA The amount of `token0` the LP has in reserve
    /// @param reserveB The amount of `token1` the LP has in reserve
    /// @param decimalsA The decimals of `token0`
    /// @param decimalsB The decimals of `token1`
    /// @return The optimal amount of TokenA to swap
    function _optimalDeposit(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB,
        uint256 decimalsA,
        uint256 decimalsB
    ) internal pure returns (uint256) {
        uint256 num;
        uint256 den;

        uint256 a = (amountA * 1e18) / decimalsA;
        uint256 x = (reserveA * 1e18) / decimalsA;
        uint256 y = (reserveB * 1e18) / decimalsB;
        uint256 x2 = (x * x) / 1e18;
        uint256 y2 = (y * y) / 1e18;
        uint256 p = (y * (((x2 * 3 + y2) * 1e18) / (y2 * 3 + x2))) / x;
        num = a * y;
        den = ((a + x) * p) / 1e18 + y;

        return ((num / den) * decimalsA) / 1e18;
    }

    /// @notice Approves the velodrome router to spend a token if it needs
    ///         more approval
    /// @param token The token the router will use
    /// @param amount The amount that needs to be approved
    function _approveRouter(address token, uint256 amount) internal {
        if (
            ERC20(token).allowance(
                address(this),
                address(strategyData.router)
            ) >= amount
        ) {
            return;
        }

        SafeTransferLib.safeApprove(
            token,
            address(strategyData.router),
            type(uint256).max
        );
    }

    /// @notice Swaps an exact amount of `tokenIn` for `tokenOut`
    /// @param tokenIn The token to be swapped from
    /// @param tokenOut The token to be swapped into
    /// @param amount The amount of `tokenIn` to be swapped
    function _swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal {
        _approveRouter(tokenIn, amount);

        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = tokenIn;
        routes[0].to = tokenOut;
        routes[0].stable = true;
        routes[0].factory = IVeloPool(asset()).factory();

        strategyData.router.swapExactTokensForTokens(
            amount,
            0,
            routes,
            address(this),
            block.timestamp
        );
    }

    /// @notice Adds `token0` and `token1` into a velodrome LP
    /// @param token0 The first token of the pair
    /// @param token1 The second token of the pair
    /// @param amountA The amount of the `token0`
    /// @param amountB The amount of the `token1`
    /// @return liquidity The amount of LP tokens received
    function _addLiquidity(
        address token0,
        address token1,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 liquidity) {
        _approveRouter(token0, amountA);
        _approveRouter(token1, amountB);

        (, , liquidity) = strategyData.router.addLiquidity(
            token0,
            token1,
            true,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
    }
}
