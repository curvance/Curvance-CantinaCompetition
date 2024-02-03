// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { CTokenCompounding, FixedPointMathLib, SafeTransferLib, IERC20, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";
import { IStashWrapper } from "contracts/interfaces/external/aura/IStashWrapper.sol";

contract AuraCToken is CTokenCompounding {
    /// TYPES ///

    /// @param balancerVault Address for Balancer Vault.
    /// @param balancerPoolId Bytes32 encoded Balancer pool id.
    /// @param pid Aura pool id value.
    /// @param rewarder Address for Aura Rewarder contract.
    /// @param booster Address for Aura Booster contract.
    /// @param rewardTokens Array of Aura reward tokens.
    /// @param underlyingTokens Balancer LP underlying tokens.
    struct StrategyData {
        IBalancerVault balancerVault;
        bytes32 balancerPoolId;
        uint256 pid;
        IBaseRewardPool rewarder;
        IBooster booster;
        address[] rewardTokens;
        address[] underlyingTokens;
    }

    /// CONSTANTS ///

    /// @dev These addresses are for Ethereum mainnet so make sure to update
    ///      them if Balancer/Aura is being supported on another chain
    address private constant _BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address private constant _AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    /// STORAGE ///

    //// @notice StrategyData packed configuration data.
    StrategyData public strategyData;

    /// @notice Whether a particular token address is an underlying token
    ///         of this BPT.
    /// @dev Token => Is underlying token.
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
        address booster_
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        strategyData.pid = pid_;
        strategyData.booster = IBooster(booster_);

        // Query actual Aura pool configuration data.
        (address pidToken, , , address balRewards, , bool shutdown) = IBooster(
            booster_
        ).poolInfo(strategyData.pid);

        // Validate that the pool is still active and that the lp token
        // and rewarder in Aura matches what we are configuring for.
        if (pidToken != asset() || shutdown || balRewards != rewarder_) {
            revert AuraCToken__InvalidVaultConfig();
        }

        strategyData.rewarder = IBaseRewardPool(rewarder_);
        strategyData.balancerVault = IBalancerVault(
            IBalancerPool(pidToken).getVault()
        );
        strategyData.balancerPoolId = IBalancerPool(pidToken).getPoolId();

        // Add BAL as a reward token, then let Aura tell you what rewards
        // the vault will receive.
        strategyData.rewardTokens.push() = _BAL;
        // Add AURA as a reward token, since some vaults do not list AURA
        // as a reward token.
        strategyData.rewardTokens.push() = _AURA;

        uint256 extraRewardsLength = IBaseRewardPool(rewarder_)
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ) {
            unchecked {
                address rewardToken = IStashWrapper(
                    IRewards(IBaseRewardPool(rewarder_).extraRewards(i++))
                        .rewardToken()
                ).baseToken();

                if (rewardToken != _AURA && rewardToken != _BAL) {
                    strategyData.rewardTokens.push() = rewardToken;
                }
            }
        }

        // Query liquidity pools underlying tokens from the Balancer vault.
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

    /// @notice Requeries reward tokens directly from Aura smart contracts.
    /// @dev This can be permissionless since this data is 1:1 with dependent
    ///      contracts and takes no parameters.
    function reQueryRewardTokens() external {
        delete strategyData.rewardTokens;

        // Add BAL as a reward token, then let Aura tell you what rewards
        // the vault will receive.
        strategyData.rewardTokens.push() = _BAL;
        // Add AURA as a reward token, since some vaults do not list AURA
        // as a reward token.
        strategyData.rewardTokens.push() = _AURA;

        IBaseRewardPool rewarder = strategyData.rewarder;
        uint256 extraRewardsLength = rewarder.extraRewardsLength();

        for (uint256 i; i < extraRewardsLength; ) {
            unchecked {
                address rewardToken = IStashWrapper(
                    IRewards(rewarder.extraRewards(i++)).rewardToken()
                ).baseToken();

                if (rewardToken != _AURA && rewardToken != _BAL) {
                    strategyData.rewardTokens.push() = rewardToken;
                }
            }
        }
    }

    /// @notice Requeries underlying tokens directly from Aura smart contracts.
    /// @dev This can be permissionless since this data is 1:1 with dependent
    ///      contracts  and takes no parameters.
    function reQueryUnderlyingTokens() external {
        address[] memory currentTokens = strategyData.underlyingTokens;
        uint256 numCurrentTokens = currentTokens.length;

        // Remove `isUnderlyingToken` mapping value from current
        // flagged underlying tokens.
        for (uint256 i; i < numCurrentTokens; ) {
            unchecked {
                isUnderlyingToken[currentTokens[i++]] = false;
            }
        }

        // Query underlying tokens from Balancer contracts.
        (currentTokens, , ) = strategyData.balancerVault.getPoolTokens(
            strategyData.balancerPoolId
        );
        strategyData.underlyingTokens = currentTokens;
        numCurrentTokens = currentTokens.length;

        // Add `isUnderlyingToken` mapping value to new
        // flagged underlying tokens.
        for (uint256 i = 0; i < numCurrentTokens; ) {
            unchecked {
                isUnderlyingToken[strategyData.underlyingTokens[i++]] = true;
            }
        }
    }

    /// @notice Returns this strategies reward tokens.
    function rewardTokens() external view returns (address[] memory) {
        return strategyData.rewardTokens;
    }

    /// @notice Returns this strategies base assets underlying tokens.
    function underlyingTokens() external view returns (address[] memory) {
        return strategyData.underlyingTokens;
    }

    /// PUBLIC FUNCTIONS ///

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards.
    /// @dev Only callable by Gelato Network bot.
    /// @param data Byte array for aggregator swap data.
    /// @return yield The amount of new assets acquired from compounding
    ///               vault yield.
    function harvest(
        bytes calldata data
    ) external override returns (uint256 yield) {
        // Checks whether the caller can compound the vault yield.
        _canCompound();

        // Vest pending rewards if there are any.
        _vestIfNeeded();

        // Can only harvest once previous reward period is done.
        if (_checkVestStatus(_vaultData)) {
            _updateVestingPeriodIfNeeded();

            // Cache strategy data.
            StrategyData memory sd = strategyData;

            // Claim pending Aura rewards.
            sd.rewarder.getReward(address(this), true);

            (SwapperLib.Swap[] memory swapDataArray, uint256 minLPAmount) = abi
                .decode(data, (SwapperLib.Swap[], uint256));

            {
                // Use scoping to avoid stack too deep.
                uint256 numRewardTokens = sd.rewardTokens.length;
                address rewardToken;
                uint256 rewardAmount;
                uint256 protocolFee;
                // Cache DAO Central Registry values to minimize runtime
                // gas costs.
                address feeAccumulator = centralRegistry.feeAccumulator();
                uint256 harvestFee = centralRegistry.protocolHarvestFee();

                for (uint256 i; i < numRewardTokens; ++i) {
                    rewardToken = sd.rewardTokens[i];
                    rewardAmount = IERC20(rewardToken).balanceOf(
                        address(this)
                    );

                    // If there are no pending rewards for this token,
                    // can skip to next reward token.
                    if (rewardAmount == 0) {
                        continue;
                    }

                    // Take protocol fee for veCVE lockers and auto
                    // compounding bot.
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

                    // Swap from rewardToken to underlying LP token, if necessary.
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

            // Prep liquidity for Balancer Pool.
            {
                // Use scoping to avoid stack too deep.
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

                // Deposit assets into Balancer Pool.
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

            // Deposit assets into Aura.
            yield = IERC20(asset()).balanceOf(address(this));
            _afterDeposit(yield, 0);

            // Update vesting info, query `vestPeriod` here to cache it.
            _setNewVaultData(yield, vestPeriod);

            emit Harvest(yield);
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Deposits specified amount of assets into Aura
    ///         booster contract.
    /// @param assets The amount of assets to deposit.
    function _afterDeposit(uint256 assets, uint256) internal override {
        IBooster booster = strategyData.booster;
        SafeTransferLib.safeApprove(asset(), address(booster), assets);
        booster.deposit(strategyData.pid, assets, true);
    }

    /// @notice Withdraws specified amount of assets from Aura reward pool.
    /// @param assets The amount of assets to withdraw.
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        strategyData.rewarder.withdrawAndUnwrap(assets, false);
    }
}
