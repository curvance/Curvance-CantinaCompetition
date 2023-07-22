// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, PriceRouter } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";



contract AuraPositionVault is BasePositionVault {
    using Math for uint256;

    /// EVENTS ///
    event SetApprovedTarget(address target, bool isApproved);
    event HarvestSlippageChanged(uint64 slippage);
    event Harvest(uint256 yield);

    /// ERRORS ///
    error ConvexPositionVault__UnsupportedCurveDeposit();
    error AuraPositionVault__BadSlippage();
    error ConvexPositionVault__WatchdogNotSet();
    error ConvexPositionVault__LengthMismatch();

    /// STORAGE ///

    /// @notice Balancer vault contract.
    IBalancerVault public balancerVault;

    /// @notice Balancer Pool Id.
    bytes32 public balancerPoolId;

    /// @notice Aura Pool Id.
    uint256 public pid;

    /// @notice Aura Rewarder contract.
    IBaseRewardPool public rewarder;

    /// @notice Aura Booster contract.
    IBooster public booster;

    /// @notice Aura reward assets.
    address[] public rewardTokens;

    /// @notice Balancer LP underlying assets.
    address[] public underlyingTokens;
    mapping(address => bool) public isUnderlyingToken;

    /// @notice Is approved target for swap.
    mapping(address => bool) public isApprovedTarget;

    /// @notice Mainnet token contracts important for this vault.
    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant BAL =
        ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    ERC20 private constant AURA =
        ERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);


    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        address balancerVault_,
        bytes32 balancerPoolId_,
        address[] memory underlyingTokens_,
        uint256 pid_,
        address rewarder_,
        address booster_,
        address[] memory rewardTokens_
    ) BasePositionVault(asset_, centralRegistry_) {

        uint256 numUnderlyingTokens = underlyingTokens_.length;

        for (uint256 i; i < numUnderlyingTokens; ++i) {
            isUnderlyingToken[underlyingTokens_[i]] = true;
        }

        balancerVault = IBalancerVault(balancerVault_);
        balancerPoolId = balancerPoolId_;
        underlyingTokens = underlyingTokens_;
        pid = pid_;
        rewarder = IBaseRewardPool(rewarder_);
        booster = IBooster(booster_);
        rewardTokens = rewardTokens_;

    }

    /// PERMISSIONED FUNCTIONS ///
    function setIsApprovedTarget(
        address _target,
        bool _isApproved
    ) external onlyDaoPermissions {
        isApprovedTarget[_target] = _isApproved;
    }

    function setRewardTokens(
        address[] calldata _rewardTokens
    ) external onlyDaoPermissions {
        rewardTokens = _rewardTokens;
    }

    /// REWARD AND HARVESTING LOGIC ///
    function harvest(
        bytes memory data
    ) public override vaultActive nonReentrant returns (uint256 yield) {

        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // We need to claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest once previous reward period is done.
        if (
            vaultData.lastVestClaim >=
            vaultData.vestingPeriodEnd
        ) {
            // Harvest aura position.
            rewarder.getReward(address(this), true);

            // Claim extra rewards
            uint256 rewardTokenCount = 2 + rewarder.extraRewardsLength();
            for (uint256 i = 2; i < rewardTokenCount; ++i) {
                IRewards extraReward = IRewards(rewarder.extraRewards(i - 2));
                extraReward.getReward();
            }

            uint256 valueIn;

            {
                SwapperLib.Swap[] memory swapDataArray = abi.decode(
                    data,
                    (SwapperLib.Swap[])
                );

                // swap assets to one of pool token
                uint256 numRewardTokens = rewardTokens.length;
                address reward;
                uint256 amount;
                uint256 protocolFee;
                uint256 rewardPrice;

                for (uint256 i = 0; i < numRewardTokens; ++i) {
                    reward = rewardTokens[i];
                    amount = ERC20(reward).balanceOf(address(this));
                    if (amount == 0) {
                        continue;
                    } 

                    // Take platform fee
                    protocolFee = amount.mulDivDown(
                        positionVaultMetaData.platformFee,
                        1e18
                    );
                    amount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        reward,
                        positionVaultMetaData.feeAccumulator,
                        protocolFee
                    );

                    (rewardPrice, ) = positionVaultMetaData
                        .priceRouter
                        .getPrice(reward, true, true);

                    valueIn += amount.mulDivDown(
                        rewardPrice,
                        10 ** ERC20(reward).decimals()
                    );

                    if (!isUnderlyingToken[reward]) {
                        SwapperLib.swap(
                            swapDataArray[i],
                            centralRegistry.priceRouter(),
                            10000 // swap for 100% slippage, we have slippage check later for global level
                        );
                    }
                }
            }

            // add liquidity to balancer
            uint256 valueOut;
            uint256 numUnderlyingTokens = underlyingTokens.length;
            address[] memory assets = new address[](numUnderlyingTokens);
            uint256[] memory maxAmountsIn = new uint256[](numUnderlyingTokens);
            address underlyingToken;
            uint256 assetPrice;

            for (uint256 i = 0; i < numUnderlyingTokens; ++i) {
                underlyingToken = underlyingTokens[i];
                assets[i] = underlyingToken;
                maxAmountsIn[i] = ERC20(underlyingToken).balanceOf(
                    address(this)
                );
                SwapperLib.approveTokenIfNeeded(
                    underlyingToken,
                    address(balancerVault),
                    maxAmountsIn[i]
                );

                (assetPrice, ) = positionVaultMetaData.priceRouter.getPrice(
                    underlyingToken,
                    true,
                    true
                );

                valueOut += maxAmountsIn[i].mulDivDown(
                    assetPrice,
                    10 ** ERC20(underlyingToken).decimals()
                );
            }

            // Compare value in vs value out.
            if (
                valueOut <
                valueIn.mulDivDown(
                    1e18 - (positionVaultMetaData.upkeepFee + harvestSlippage),
                    1e18
                )
            ) revert AuraPositionVault__BadSlippage();

            balancerVault.joinPool(
                balancerPoolId,
                address(this),
                address(this),
                IBalancerVault.JoinPoolRequest(
                    assets,
                    maxAmountsIn,
                    abi.encode(
                        IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                        maxAmountsIn,
                        1
                    ),
                    false // Don't use internal balances
                )
            );

            // deposit Assets to Aura.
            yield = ERC20(asset()).balanceOf(address(this));
            _deposit(yield);

            // update Vesting info.
            vaultData.rewardRate = uint128(
                yield.mulDivDown(rewardOffset, vestPeriod)
            );
            vaultData.vestingPeriodEnd = uint64(block.timestamp + vestPeriod);
            vaultData.lastVestClaim = uint64(block.timestamp);
            emit Harvest(yield);
        } 
        // else yield is zero.
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 assets) internal override {
        IBaseRewardPool rewardPool = IBaseRewardPool(rewarder);
        rewardPool.withdrawAndUnwrap(assets, false);
    }

    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(asset(), address(booster), assets);
        booster.deposit(pid, assets, true);
    }

    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        IBaseRewardPool rewardPool = IBaseRewardPool(rewarder);
        return rewardPool.balanceOf(address(this));
    }
}
