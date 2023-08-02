// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { VelodromeLib } from "contracts/market/zapper/protocols/VelodromeLib.sol";

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
    ) public override onlyHarvestor vaultActive returns (uint256 yield) {
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
                    SwapperLib.swap(swapData);
                }
            }

            // deposit into velodrome
            yield = VelodromeLib.enterVelodrome(
                address(sd.router),
                address(sd.pairFactory),
                asset(),
                0
            );

            (uint256 lpPrice, ) = getPriceRouter().getPrice(
                asset(),
                true,
                true
            );
            uint256 valueOut = yield.mulDivDown(lpPrice, 10 ** 18);

            // check for slippage
            require(
                valueOut > valueIn.mulDivDown(1e18 - maxSlippage, 1e18),
                "VelodromeVolatilePositionVault: bad slippage"
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
}
