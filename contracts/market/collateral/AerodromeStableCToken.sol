// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, SafeTransferLib, IERC20, Math, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";
import { VelodromeLib } from "contracts/libraries/VelodromeLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

contract AerodromeStableCToken is CTokenCompounding {
    using Math for uint256;

    /// TYPES ///

    struct StrategyData {
        IVeloGauge gauge; // Aerodrome Gauge contract
        IVeloPairFactory pairFactory; // Aerodrome Pair Factory contract
        IVeloRouter router; // Aerodrome Router contract
        address token0; // LP first token address
        address token1; // LP second token address
        uint256 decimalsA; // token0 decimals
        uint256 decimalsB; // token1 decimals
    }

    /// CONSTANTS ///

    /// @notice AERO contract address
    IERC20 public constant rewardToken =
        IERC20(0x940181a94A35A4569E4529A3CDfB74e38FD98631);
    /// @notice Whether AERO is an underlying token of the pair
    bool public immutable rewardTokenIsUnderlying;

    /// STORAGE ///

    /// @notice StrategyData packed configuration data
    StrategyData public strategyData;

    /// @notice Token => underlying token of the sAMM LP or not
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error AerodromeStableCToken__ChainIsNotSupported();
    error AerodromeStableCToken__StakingTokenIsNotAsset(
        address stakingToken
    );
    error AerodromeStableCToken__AssetIsNotStable();
    error AerodromeStableCToken__SlippageError();
    error AerodromeStableCToken__InvalidSwapper(address invalidSwapper);

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        IVeloGauge gauge,
        IVeloPairFactory pairFactory,
        IVeloRouter router
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        if (block.chainid != 8453) {
            revert AerodromeStableCToken__ChainIsNotSupported();
        }

        // Cache assigned asset address
        address _asset = asset();
        // Validate that we have the proper gauge linked with the proper LP
        // and pair factory
        if (gauge.stakingToken() != _asset) {
            revert AerodromeStableCToken__StakingTokenIsNotAsset(
                gauge.stakingToken()
            );
        }

        if (!IVeloPool(_asset).stable()) {
            revert AerodromeStableCToken__AssetIsNotStable();
        }

        // Query underlying token data from the pool
        strategyData.token0 = IVeloPool(_asset).token0();
        strategyData.token1 = IVeloPool(_asset).token1();
        // make sure token0 is AERO if one of underlying tokens is AERO
        // so that it can be used properly in harvest function.
        if (strategyData.token1 == address(rewardToken)) {
            strategyData.token1 = strategyData.token0;
            strategyData.token0 = address(rewardToken);
        }
        strategyData.decimalsA = 10 ** IERC20(strategyData.token0).decimals();
        strategyData.decimalsB = 10 ** IERC20(strategyData.token1).decimals();

        strategyData.gauge = gauge;
        strategyData.router = router;
        strategyData.pairFactory = pairFactory;

        isUnderlyingToken[strategyData.token0] = true;
        isUnderlyingToken[strategyData.token1] = true;

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
    ) external override returns (uint256 yield) {
        // Checks whether the caller can compound the vault yield
        _canCompound();

        // Vest pending rewards if there are any
        _vestIfNeeded();

        // can only harvest once previous reward period is done
        if (_checkVestStatus(_vaultData)) {

            _updateVestingPeriodIfNeeded();
            
            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim aerodrome rewards
            sd.gauge.getReward(address(this));

            {
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

                    // swap from AERO to underlying LP token if necessary
                    if (!rewardTokenIsUnderlying) {
                        SwapperLib.Swap memory swapData = abi.decode(
                            data,
                            (SwapperLib.Swap)
                        );

                        if (!centralRegistry.isSwapper(swapData.target)) {
                            revert AerodromeStableCToken__InvalidSwapper(
                                swapData.target
                            );
                        }

                        SwapperLib.swap(swapData);
                    }
                }
            }

            // One of underlying tokens is AERO
            // swap token0 to LP Token underlying tokens
            uint256 totalAmountA = IERC20(sd.token0).balanceOf(address(this));

            if (totalAmountA == 0) {
                revert AerodromeStableCToken__SlippageError();
            }

            // Cache asset so we don't need to pay gas multiple times
            address _asset = asset();
            (uint256 r0, uint256 r1, ) = IVeloPair(_asset).getReserves();
            (uint256 reserveA, uint256 reserveB) = sd.token0 ==
                IVeloPair(_asset).token0()
                ? (r0, r1)
                : (r1, r0);
            // Feed library pair factory, lpToken, and stable = true, plus calculated data
            uint256 swapAmount = VelodromeLib._optimalDeposit(
                address(sd.pairFactory),
                _asset,
                totalAmountA,
                reserveA,
                reserveB,
                sd.decimalsA,
                sd.decimalsB,
                true
            );
            // Query router and feed calculated data, and stable = true
            VelodromeLib._swapExactTokensForTokens(
                address(sd.router),
                _asset,
                sd.token0,
                sd.token1,
                swapAmount,
                true
            );
            totalAmountA -= swapAmount;

            // add liquidity to aerodrome lp with stable params
            yield = VelodromeLib._addLiquidity(
                address(sd.router),
                sd.token0,
                sd.token1,
                true,
                totalAmountA,
                IERC20(sd.token1).balanceOf(address(this)), // totalAmountB
                VelodromeLib.VELODROME_ADD_LIQUIDITY_SLIPPAGE
            );

            // deposit assets into aerodrome gauge
            _afterDeposit(yield, 0);

            // update vesting info
            // Cache vest period so we do not need to load it twice
            uint256 _vestPeriod = vestPeriod;
            _vaultData = _packVaultData(
                yield.mulDivDown(WAD, _vestPeriod),
                block.timestamp + _vestPeriod
            );

            emit Harvest(yield);
        }
        // else yield is zero
    }

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into aerodrome gauge pool
    /// @param assets The amount of assets to deposit
    function _afterDeposit(uint256 assets, uint256) internal override {
        IVeloGauge gauge = strategyData.gauge;
        SafeTransferLib.safeApprove(asset(), address(gauge), assets);
        gauge.deposit(assets);
    }

    /// @notice Withdraws specified amount of assets from aerodrome gauge pool
    /// @param assets The amount of assets to withdraw
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        strategyData.gauge.withdraw(assets);
    }

    /// @notice Gets the balance of assets inside aerodrome gauge pool
    /// @return The current balance of assets
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return strategyData.gauge.balanceOf(address(this));
    }

}
