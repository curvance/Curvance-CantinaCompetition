// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { FixedPointMathLib, SafeTransferLib, IERC20, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";
import { CTokenCompoundingWithExitFee } from "contracts/market/collateral/CTokenCompoundingWithExitFee.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";
import { IStashWrapper } from "contracts/interfaces/external/aura/IStashWrapper.sol";

contract MockAuraCTokenWithExitFee is CTokenCompoundingWithExitFee {
    /// TYPES ///

    struct StrategyData {
        IBalancerVault balancerVault; // Balancer vault contract
        bytes32 balancerPoolId; // Balancer Pool Id
        uint256 pid; // Aura Pool Id
        IBaseRewardPool rewarder; // Aura Rewarder contract
        IBooster booster; // Aura Booster contract
        address[] rewardTokens; // Aura reward assets
        address[] underlyingTokens; // Balancer LP underlying assets
    }

    /// CONSTANTS ///

    /// @notice These addresses are for ethereum mainnet so make sure to update
    ///         them if balancer/aura is being supported on another chain
    address private constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address private constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    /// STORAGE ///

    /// @notice StrategyData packed configuration data
    StrategyData public strategyData;

    /// @notice Token => underlying token of the BPT or not
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error AuraCToken__InvalidVaultConfig();
    error AuraCToken__InvalidSwapper(uint256 index, address invalidSwapper);

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        uint256 pid_,
        address rewarder_,
        address booster_,
        uint256 exitFee_
    )
        CTokenCompoundingWithExitFee(
            centralRegistry_,
            asset_,
            marketManager_,
            exitFee_
        )
    {
        strategyData.pid = pid_;
        strategyData.booster = IBooster(booster_);

        // query actual aura pool configuration data
        (address pidToken, , , address balRewards, , bool shutdown) = IBooster(
            booster_
        ).poolInfo(strategyData.pid);

        // validate that the pool is still active and that the lp token
        // and rewarder in aura matches what we are configuring for
        if (pidToken != asset() || shutdown || balRewards != rewarder_) {
            revert AuraCToken__InvalidVaultConfig();
        }

        strategyData.rewarder = IBaseRewardPool(rewarder_);
        strategyData.balancerVault = IBalancerVault(
            IBalancerPool(pidToken).getVault()
        );
        strategyData.balancerPoolId = IBalancerPool(pidToken).getPoolId();

        // add BAL as a reward token, then let aura tell you what rewards
        // the vault will receive
        strategyData.rewardTokens.push() = BAL;
        // add AURA as a reward token, since some vaults do not list AURA
        // as a reward token
        strategyData.rewardTokens.push() = AURA;

        uint256 extraRewardsLength = IBaseRewardPool(rewarder_)
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ) {
            unchecked {
                address rewardToken = IStashWrapper(
                    IRewards(IBaseRewardPool(rewarder_).extraRewards(i++))
                        .rewardToken()
                ).baseToken();

                if (rewardToken != AURA && rewardToken != BAL) {
                    strategyData.rewardTokens.push() = rewardToken;
                }
            }
        }

        // query liquidity pools underlying tokens from the balancer vault
        (address[] memory underlyingTokens, , ) = strategyData
            .balancerVault
            .getPoolTokens(strategyData.balancerPoolId);
        strategyData.underlyingTokens = underlyingTokens;

        uint256 numUnderlyingTokens = strategyData.underlyingTokens.length;
        for (uint256 i; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[strategyData.underlyingTokens[i++]] = true;
            }
        }
    }

    /// EXTERNAL FUNCTIONS ///

    // PERMISSIONED FUNCTIONS

    function reQueryRewardTokens() external {
        delete strategyData.rewardTokens;

        // add BAL as a reward token, then let aura tell you what rewards
        // the vault will receive
        strategyData.rewardTokens.push() = BAL;
        // add AURA as a reward token, since some vaults do not list AURA
        // as a reward token
        strategyData.rewardTokens.push() = AURA;
        IBaseRewardPool rewarder = strategyData.rewarder;

        uint256 extraRewardsLength = rewarder.extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ) {
            unchecked {
                address rewardToken = IStashWrapper(
                    IRewards(rewarder.extraRewards(i++)).rewardToken()
                ).baseToken();

                if (rewardToken != AURA && rewardToken != BAL) {
                    strategyData.rewardTokens.push() = rewardToken;
                }
            }
        }
    }

    function reQueryUnderlyingTokens() external {
        address[] memory underlyingTokens = strategyData.underlyingTokens;
        uint256 numUnderlyingTokens = underlyingTokens.length;
        for (uint256 i = 0; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[underlyingTokens[i++]] = false;
            }
        }

        (underlyingTokens, , ) = strategyData.balancerVault.getPoolTokens(
            strategyData.balancerPoolId
        );
        strategyData.underlyingTokens = underlyingTokens;

        numUnderlyingTokens = underlyingTokens.length;
        for (uint256 i = 0; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[underlyingTokens[i++]] = true;
            }
        }
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

            // claim aura rewards
            sd.rewarder.getReward(address(this), true);

            (SwapperLib.Swap[] memory swapDataArray, uint256 minLPAmount) = abi
                .decode(data, (SwapperLib.Swap[], uint256));

            {
                // Use scoping to avoid stack too deep
                uint256 numRewardTokens = sd.rewardTokens.length;
                address rewardToken;
                uint256 rewardAmount;
                uint256 protocolFee;
                // Cache Central registry values so we dont pay gas multiple times
                address feeAccumulator = centralRegistry.feeAccumulator();
                uint256 harvestFee = centralRegistry.protocolHarvestFee();

                for (uint256 i; i < numRewardTokens; ++i) {
                    rewardToken = sd.rewardTokens[i];
                    rewardAmount = IERC20(rewardToken).balanceOf(
                        address(this)
                    );

                    if (rewardAmount == 0) {
                        continue;
                    }

                    // take protocol fee
                    protocolFee = FixedPointMathLib.mulDiv(
                        rewardAmount,
                        harvestFee,
                        1e18
                    );
                    rewardAmount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        rewardToken,
                        feeAccumulator,
                        protocolFee
                    );

                    // swap from rewardToken to underlying LP token if necessary
                    if (!isUnderlyingToken[rewardToken]) {
                        if (
                            !centralRegistry.isSwapper(swapDataArray[i].target)
                        ) {
                            revert AuraCToken__InvalidSwapper(
                                i,
                                swapDataArray[i].target
                            );
                        }

                        SwapperLib.swap(centralRegistry, swapDataArray[i]);
                    }
                }
            }

            // prep adding liquidity to balancer
            {
                // Use scoping to avoid stack too deep
                uint256 numUnderlyingTokens = sd.underlyingTokens.length;
                address[] memory assets = new address[](numUnderlyingTokens);
                uint256[] memory maxAmountsIn = new uint256[](
                    numUnderlyingTokens
                );
                address underlyingToken;

                for (uint256 i; i < numUnderlyingTokens; ++i) {
                    underlyingToken = sd.underlyingTokens[i];
                    assets[i] = underlyingToken;
                    maxAmountsIn[i] = IERC20(underlyingToken).balanceOf(
                        address(this)
                    );

                    SwapperLib._approveTokenIfNeeded(
                        underlyingToken,
                        address(sd.balancerVault),
                        maxAmountsIn[i]
                    );
                }

                // deposit assets into balancer
                sd.balancerVault.joinPool(
                    sd.balancerPoolId,
                    address(this),
                    address(this),
                    IBalancerVault.JoinPoolRequest(
                        assets,
                        maxAmountsIn,
                        abi.encode(
                            IBalancerVault
                                .JoinKind
                                .EXACT_TOKENS_IN_FOR_BPT_OUT,
                            maxAmountsIn,
                            minLPAmount
                        ),
                        false // do not use internal balances
                    )
                );
            }

            // deposit assets into aura
            yield = IERC20(asset()).balanceOf(address(this));
            _afterDeposit(yield, 0);

            // Update vesting info, query `vestPeriod` here to cache it.
            _setNewVaultData(yield, vestPeriod);

            emit Harvest(yield);
        }
        // else yield is zero
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Deposits specified amount of assets into Aura booster contract
    /// @param assets The amount of assets to deposit
    function _afterDeposit(uint256 assets, uint256) internal override {
        IBooster booster = strategyData.booster;
        SafeTransferLib.safeApprove(asset(), address(booster), assets);
        booster.deposit(strategyData.pid, assets, true);
    }

    /// @notice Withdraws specified amount of assets from Aura reward pool
    /// @param assets The amount of assets to withdraw
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        strategyData.rewarder.withdrawAndUnwrap(assets, false);
    }
}
