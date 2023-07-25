// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

contract VelodromeVolatilePositionVault is BasePositionVault {
    using Math for uint256;

    /// TYPES ///

    /// @param gauge Velodrome Gauge contract
    /// @param pairFactory Velodrome Pair Factory contract
    /// @param router Velodrome Router contract
    /// @param token0 LP first token address
    /// @param token1 LP second token address
    struct StrategyData {
        IVeloGauge gauge;
        IVeloPairFactory pairFactory;
        IVeloRouter router;
        address token0;
        address token1;
    }

    /// CONSTANTS ///

    ERC20 public constant rewardToken =
        ERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);

    uint256 public immutable rewardTokenDecimals;
    bool public immutable rewardTokenIsUnderlying;

    /// STORAGE ///

    /// @notice Vault Strategy Data
    StrategyData public strategyData;

    /// @notice Is an underlying token of the vAMM LP
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
        // Validate that we have the proper gauge linked with the proper LP
        // and pair factory
        require(
            gauge.stakingToken() == asset() &&
                address(pairFactory) == router.factory(),
            "VelodromeVolatilePositionVault: improper velodrome vault config"
        );

        // Query underlying token data from the pool
        strategyData.token0 = IVeloPool(asset()).token0();
        strategyData.token1 = IVeloPool(asset()).token1();
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

    /// PUBLIC FUNCTIONS///

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards
    /// @dev Only callable by Gelato Network bot
    /// @param data Bytes array for aggregator swap data
    /// @param maxSlippage Maximum allowable slippage on swapping
    /// @return yield The amount of new assets acquired from compounding vault yield
    function harvest(
        bytes memory data,
        uint256 maxSlippage
    )
        public
        override
        onlyHarvestor
        vaultActive
        nonReentrant
        returns (uint256 yield)
    {
        uint256 pending = _calculatePendingRewards();

        if (pending > 0) {
            // claim vested rewards
            _vestRewards(_totalAssets + pending);
        }

        // can only harvest once previous reward period is done
        if (vaultData.lastVestClaim >= vaultData.vestingPeriodEnd) {
            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim velodrome rewards
            sd.gauge.getReward(address(this));

            uint256 valueIn;
            SwapperLib.Swap memory swapData = abi.decode(
                data,
                (SwapperLib.Swap)
            );
            uint256 rewardAmount = rewardToken.balanceOf(address(this));

            if (rewardAmount > 0) {
                // take protocol fee
                uint256 protocolFee = rewardAmount.mulDivDown(
                    vaultHarvestFee(),
                    1e18
                );
                rewardAmount -= protocolFee;
                SafeTransferLib.safeTransfer(
                    address(rewardToken),
                    centralRegistry.feeAccumulator(),
                    protocolFee
                );
                (uint256 rewardPrice, ) = getPriceRouter().getPrice(
                    address(rewardToken),
                    true,
                    true
                );

                valueIn += rewardAmount.mulDivDown(
                    rewardPrice,
                    10 ** rewardTokenDecimals
                );

                // swap from VELO to underlying LP token if necessary
                if (!rewardTokenIsUnderlying) {
                    // swap for 100% slippage,
                    // we have slippage check later for global level
                    SwapperLib.swap(
                        swapData,
                        centralRegistry.priceRouter(),
                        10000
                    );
                }
            }

            uint256 totalAmountA;
            uint256 totalAmountB;

            {
                // swap token0 to LP Token underlying tokens
                totalAmountA = ERC20(sd.token0).balanceOf(address(this));

                require(
                    totalAmountA > 0,
                    "VelodromeVolatilePositionVault: slippage error"
                );

                (uint256 r0, uint256 r1, ) = IVeloPair(asset()).getReserves();
                uint256 reserveA = sd.token0 == IVeloPair(asset()).token0()
                    ? r0
                    : r1;

                uint256 swapAmount = _optimalDeposit(totalAmountA, reserveA);

                _swapExactTokensForTokens(sd.token0, sd.token1, swapAmount);

                totalAmountA -= swapAmount;
                totalAmountB = ERC20(sd.token1).balanceOf(address(this));
            }

            uint256 valueOut;

            (uint256 tokenAPrice, ) = getPriceRouter().getPrice(
                sd.token0,
                true,
                true
            );
            (uint256 tokenBPrice, ) = getPriceRouter().getPrice(
                sd.token1,
                true,
                true
            );
            valueOut =
                totalAmountA.mulDivDown(
                    tokenAPrice,
                    10 ** ERC20(sd.token0).decimals()
                ) +
                totalAmountB.mulDivDown(
                    tokenBPrice,
                    10 ** ERC20(sd.token1).decimals()
                );

            // check for slippage
            require(
                valueOut > valueIn.mulDivDown(1e18 - maxSlippage, 1e18),
                "VelodromeVolatilePositionVault: bad slippage"
            );

            // add liquidity to velodrome lp
            yield = _addLiquidity(
                sd.token0,
                sd.token1,
                totalAmountA,
                totalAmountB
            );

            // deposit assets into velodrome gauge
            _deposit(yield);

            // update vesting info
            vaultData.rewardRate = uint128(
                yield.mulDivDown(rewardOffset, vestPeriod)
            );
            vaultData.vestingPeriodEnd = uint64(block.timestamp + vestPeriod);
            vaultData.lastVestClaim = uint64(block.timestamp);

            emit Harvest(yield);
        } // else yield is zero
    }

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into velodrome gauge pool
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(
            asset(),
            address(strategyData.gauge),
            assets
        );
        strategyData.gauge.deposit(assets);
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
    ///         for a perfect LP deposit for a volatile pair
    /// @param amountA The amount of `token0` this vault has currently
    /// @param reserveA The amount of `token0` the LP has in reserve
    /// @return The optimal amount of TokenA to swap
    function _optimalDeposit(
        uint256 amountA,
        uint256 reserveA
    ) internal view returns (uint256) {
        uint256 swapFee = strategyData.pairFactory.getFee(asset(), false);
        uint256 swapFeeFactor = 10000 - swapFee;
        uint256 a = (10000 + swapFeeFactor) * reserveA;
        uint256 b = amountA * 10000 * reserveA * 4 * swapFeeFactor;
        uint256 c = Math.sqrt(a * a + b);
        uint256 d = swapFeeFactor * 2;
        return (c - a) / d;
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
        routes[0].stable = false;
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
            false,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
    }
}
