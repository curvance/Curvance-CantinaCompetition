// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompoundingBase, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/market/collateral/CTokenCompoundingBase.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { VelodromeLib } from "contracts/market/zapper/protocols/VelodromeLib.sol";

import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract VelodromeVolatileCToken is CTokenCompoundingBase {
    using Math for uint256;

    /// TYPES ///

    struct StrategyData {
        IVeloGauge gauge; // Velodrome Gauge contract
        IVeloPairFactory pairFactory; // Velodrome Pair Factory contract
        IVeloRouter router; // Velodrome Router contract
        address token0; // LP first token address
        address token1; // LP second token address
    }

    /// CONSTANTS ///

    // Optimism VELO contract address
    ERC20 public constant rewardToken =
        ERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    // Whether VELO is an underlying token of the pair
    bool public immutable rewardTokenIsUnderlying;

    /// STORAGE ///

    StrategyData public strategyData; // position vault packed configuration

    /// Token => underlying token of the vAMM LP or not
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error VelodromeVolatileCToken__Unauthorized();
    error VelodromeVolatileCToken__StakingTokenIsNotAsset(
        address stakingToken
    );
    error VelodromeVolatileCToken__AssetIsNotStable();
    error VelodromeVolatileCToken__SlippageError();
    error VelodromeVolatileCToken__InvalidSwapper(
        address invalidSwapper
    );

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        ERC20 asset_,
        address lendtroller_,
        IVeloGauge gauge,
        IVeloPairFactory pairFactory,
        IVeloRouter router
    ) CTokenCompoundingBase(centralRegistry_, asset_, lendtroller_) {
        // Cache assigned asset address
        address _asset = asset();
        // Validate that we have the proper gauge linked with the proper LP
        // and pair factory
        if (gauge.stakingToken() != _asset) {
            revert VelodromeVolatileCToken__StakingTokenIsNotAsset(
                gauge.stakingToken()
            );
        }

        if (IVeloPool(_asset).stable()) {
            revert VelodromeVolatileCToken__AssetIsNotStable();
        }

        // Query underlying token data from the pool
        strategyData.token0 = IVeloPool(_asset).token0();
        strategyData.token1 = IVeloPool(_asset).token1();
        // make sure token0 is VELO if one of underlying tokens is VELO
        // so that it can be used properly in harvest function.
        if (strategyData.token1 == address(rewardToken)) {
            strategyData.token1 = strategyData.token0;
            strategyData.token0 = address(rewardToken);
        }
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
        if (!centralRegistry.isHarvester(msg.sender)) {
            revert VelodromeVolatileCToken__Unauthorized();
        }

        if (_vaultIsActive == 1) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

        uint256 pending = _calculatePendingRewards();

        if (pending > 0) {
            // claim vested rewards
            _vestRewards(_totalAssets + pending);
        }

        // can only harvest once previous reward period is done
        if (_checkVestStatus(_vaultData)) {

            if (pendingVestUpdate.updateNeeded) {
                vestPeriod = pendingVestUpdate.newVestPeriod;
                pendingVestUpdate.updateNeeded = false;
            }
            
            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim velodrome rewards
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

                    // swap from VELO to underlying LP token if necessary
                    if (!rewardTokenIsUnderlying) {
                        SwapperLib.Swap memory swapData = abi.decode(
                            data,
                            (SwapperLib.Swap)
                        );

                        if (!centralRegistry.isSwapper(swapData.target)) {
                            revert VelodromeVolatileCToken__InvalidSwapper(
                                swapData.target
                            );
                        }

                        SwapperLib.swap(swapData);
                    }
                }
            }

            // token0 is VELO of one of underlying tokens is VELO
            // swap token0 to LP Token underlying tokens
            uint256 totalAmountA = ERC20(sd.token0).balanceOf(address(this));
            if (totalAmountA == 0) {
                revert VelodromeVolatileCToken__SlippageError();
            }

            // Cache asset so we don't need to pay gas multiple times
            address _asset = asset();
            (uint256 r0, uint256 r1, ) = IVeloPair(_asset).getReserves();
            uint256 reserveA = sd.token0 == IVeloPair(_asset).token0()
                ? r0
                : r1;

            // On Volatile Pair we only need to input factory, lptoken, amountA, reserveA, stable = false
            // Decimals are unused and amountB is unused so we can pass 0
            uint256 swapAmount = VelodromeLib._optimalDeposit(
                address(sd.pairFactory),
                _asset,
                totalAmountA,
                reserveA,
                0,
                0,
                0,
                false
            );
            // Can pass as normal with stable = false
            VelodromeLib._swapExactTokensForTokens(
                address(sd.router),
                _asset,
                sd.token0,
                sd.token1,
                swapAmount,
                false
            );
            totalAmountA -= swapAmount;

            // add liquidity to velodrome lp with stable = false
            yield = VelodromeLib._addLiquidity(
                address(sd.router),
                sd.token0,
                sd.token1,
                false,
                totalAmountA,
                ERC20(sd.token1).balanceOf(address(this)), // totalAmountB
                VelodromeLib.VELODROME_ADD_LIQUIDITY_SLIPPAGE
            );

            // deposit assets into velodrome gauge
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

    /// @notice Deposits specified amount of assets into velodrome gauge pool
    /// @param assets The amount of assets to deposit
    function _afterDeposit(uint256 assets, uint256) internal override {
        IVeloGauge gauge = strategyData.gauge;
        SafeTransferLib.safeApprove(asset(), address(gauge), assets);
        gauge.deposit(assets);
    }

    /// @notice Withdraws specified amount of assets from velodrome gauge pool
    /// @param assets The amount of assets to withdraw
    function _beforeWithdraw(uint256 assets, uint256) internal override {
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

}
