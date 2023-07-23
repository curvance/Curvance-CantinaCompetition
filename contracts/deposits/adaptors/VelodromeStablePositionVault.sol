// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, IPriceRouter, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

contract VelodromeStablePositionVault is BasePositionVault {
    using Math for uint256;

    /// EVENTS ///
    event Harvest(uint256 yield);

    /// STRUCTS ///
    struct StrategyData {
        /// @notice Velodrome Gauge contract
        IVeloGauge gauge;
        /// @notice Velodrome Pair Factory contract
        IVeloPairFactory pairFactory;
        /// @notice Velodrome Router contract
        IVeloRouter router;
        /// @notice LP first token address
        address tokenA;
        /// @notice LP second token address
        address tokenB;
        /// @notice tokenA decimals
        uint256 decimalsA;
        /// @notice tokenB decimals
        uint256 decimalsB;
        /// @notice Velodrome reward tokens
        address[] rewardTokens;
    }

    /// STORAGE ///

    /// Vault Strategy Data
    StrategyData public strategyData;

    /// @notice Is an underlying token of the sAMM LP
    mapping(address => bool) public isUnderlyingToken;

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        IVeloGauge gauge,
        IVeloPairFactory pairFactory,
        IVeloRouter router,
        address tokenA,
        address tokenB,
        address[] memory rewardTokens
    ) BasePositionVault(asset_, centralRegistry_) {

        strategyData.tokenA = tokenA;
        strategyData.tokenB = tokenB;
        strategyData.decimalsA = 10 ** ERC20(tokenA).decimals();
        strategyData.decimalsB = 10 ** ERC20(tokenB).decimals();
        strategyData.gauge = gauge;
        strategyData.router = router;
        strategyData.pairFactory = pairFactory;
        strategyData.rewardTokens = rewardTokens;

        isUnderlyingToken[tokenA] = true;
        isUnderlyingToken[tokenB] = true;

    }

    /// REWARD AND HARVESTING LOGIC ///
    /// @notice Harvests and compounds outstanding vault rewards and vests pending rewards
    /// @dev Only callable by Gelato Network bot
    /// @param data Bytes array for aggregator swap data
    /// @param maxSlippage Maximum allowable slippage on swapping
    /// @return yield The amount of new assets acquired from compounding vault yield
    function harvest(
        bytes memory data,
        uint256 maxSlippage
    ) public override onlyHarvestor vaultActive nonReentrant returns (uint256 yield) {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // claim vested rewards
            _vestRewards(_totalAssets + pending);
        }

        // can only harvest once previous reward period is done
        if (
            vaultData.lastVestClaim >=
            vaultData.vestingPeriodEnd
        ) {

            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim velodrome rewards
            sd.gauge.getReward(address(this));

            uint256 valueIn;

            {
                
                SwapperLib.Swap[] memory swapDataArray = abi.decode(
                    data,
                    (SwapperLib.Swap[])
                );

                uint256 numRewardTokens = sd.rewardTokens.length;
                address rewardToken;
                uint256 rewardAmount;
                uint256 protocolFee;
                uint256 rewardPrice;

                for (uint256 i; i < numRewardTokens; ++i) {
                    rewardToken = sd.rewardTokens[i];
                    rewardAmount = ERC20(rewardToken).balanceOf(address(this));

                    if (rewardAmount == 0){
                        continue;
                    } 

                    // take protocol fee
                    protocolFee = rewardAmount.mulDivDown(
                        vaultHarvestFee(),
                        1e18
                    );
                    rewardAmount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        rewardToken,
                        centralRegistry.feeAccumulator(),
                        protocolFee
                    );
                    (rewardPrice, ) = getPriceRouter().getPrice(rewardToken, true, true);

                    valueIn += rewardAmount.mulDivDown(
                        rewardPrice,
                        10 ** ERC20(rewardToken).decimals()
                    );

                    /// swap from rewardToken to underlying LP token if necessary
                    if (!isUnderlyingToken[rewardToken]) {
                        SwapperLib.swap(
                            swapDataArray[i],
                            centralRegistry.priceRouter(),
                            10000 // swap for 100% slippage, we have slippage check later for global level
                        );
                    }

                }
            }

            uint256 totalAmountA;
            uint256 totalAmountB;

            {
                // swap tokenA to LP Token underlying tokens
                totalAmountA = ERC20(sd.tokenA).balanceOf(address(this));

                require(totalAmountA > 0, "VelodromeStablePositionVault: slippage error");

                (uint256 r0, uint256 r1, ) = IVeloPair(asset()).getReserves();
                (uint256 reserveA, uint256 reserveB) = sd.tokenA ==
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

                _swapExactTokensForTokens(sd.tokenA, sd.tokenB, swapAmount);
                totalAmountA -= swapAmount;
                totalAmountB = ERC20(sd.tokenB).balanceOf(address(this));

            }
            
            uint256 valueOut;

            (uint256 tokenAPrice, ) = getPriceRouter().getPrice(sd.tokenA, true, true);
            (uint256 tokenBPrice, ) = getPriceRouter().getPrice(sd.tokenB, true, true);
            valueOut =
                totalAmountA.mulDivDown(
                    tokenAPrice,
                    10 ** ERC20(sd.tokenA).decimals()
                ) +
                totalAmountB.mulDivDown(
                    tokenBPrice,
                    10 ** ERC20(sd.tokenB).decimals()
                );

            // check for slippage
            require(valueOut >
            valueIn.mulDivDown(1e18 - maxSlippage, 1e18), "VelodromeStablePositionVault: bad slippage");

            // add liquidity to velodrome lp
            yield = _addLiquidity(
                sd.tokenA,
                sd.tokenB,
                totalAmountA,
                totalAmountB
            );
        
            // deposit assets into velodrome gauge
            _deposit(yield);
            
            // update vesting info
            vaultData.rewardRate = uint128(yield.mulDivDown(rewardOffset, vestPeriod));
            vaultData.vestingPeriodEnd = uint64(block.timestamp + vestPeriod);
            vaultData.lastVestClaim = uint64(block.timestamp);

            emit Harvest(yield);
        } 
        // else yield is zero
    }

    /// INTERNAL POSITION LOGIC ///
    /// @notice Deposits specified amount of assets into velodrome gauge pool
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(asset(), address(strategyData.gauge), assets);
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

    /// @notice Calculates the optimal amount of TokenA to swap to TokenB for a perfect LP deposit for a stable pair
    /// @param amountA The amount of `tokenA` this vault has currently
    /// @param reserveA The amount of `tokenA` the LP has in reserve
    /// @param reserveB The amount of `tokenB` the LP has in reserve
    /// @param decimalsA The decimals of `tokenA`
    /// @param decimalsB The decimals of `tokenB`
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

    /// @notice Approves the velodrome router to spend a token if it needs more approved
    /// @param token The token the router will use
    /// @param amount The amount that needs to be approved
    function _approveRouter(address token, uint256 amount) internal {
        if (ERC20(token).allowance(address(this), address(strategyData.router)) >= amount) {
            return;
        }
            
        SafeTransferLib.safeApprove(token, address(strategyData.router), type(uint256).max);
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

        strategyData.router.swapExactTokensForTokens(amount, 0, routes, address(this), block.timestamp);
    }

    /// @notice Adds `tokenA` and `tokenB` into a velodrome LP
    /// @param tokenA The first token of the pair
    /// @param tokenB The second token of the pair
    /// @param amountA The amount of the `tokenA`
    /// @param amountB The amount of the `tokenB`
    /// @return liquidity The amount of LP tokens received
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 liquidity) {
        _approveRouter(tokenA, amountA);
        _approveRouter(tokenB, amountB);
        (, , liquidity) = strategyData.router.addLiquidity(
            tokenA,
            tokenB,
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
