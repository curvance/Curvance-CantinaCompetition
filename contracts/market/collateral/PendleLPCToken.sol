// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { CTokenCompounding, FixedPointMathLib, SafeTransferLib, IERC20, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IPendleRouter, ApproxParams } from "contracts/interfaces/external/pendle/IPendleRouter.sol";
import { IPMarket } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IPPrincipalToken } from "contracts/interfaces/external/pendle/IPPrincipalToken.sol";
import { IPYieldToken } from "contracts/interfaces/external/pendle/IPYieldToken.sol";
import { IStandardizedYield } from "contracts/interfaces/external/pendle/IStandardizedYield.sol";

contract PendleLPCToken is CTokenCompounding {
    /// TYPES ///

    struct StrategyData {
        IPendleRouter router;
        IPMarket lp;
        IStandardizedYield sy;
        IPPrincipalToken pt;
        IPYieldToken yt;
        address[] rewardTokens;
        address[] underlyingTokens;
    }

    /// CONSTANTS ///

    /// STORAGE ///

    /// @notice StrategyData packed configuration data
    StrategyData public strategyData;

    /// @notice token => is underlying token
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error PendleLPCToken__InvalidSwapper(
        uint256 index,
        address invalidSwapper
    );

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        IPendleRouter router_
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        strategyData.router = router_;
        strategyData.lp = IPMarket(address(asset_));
        (strategyData.sy, strategyData.pt, strategyData.yt) = strategyData
            .lp
            .readTokens();

        strategyData.rewardTokens = strategyData.lp.getRewardTokens();

        strategyData.underlyingTokens = strategyData.sy.getTokensIn();
        uint256 numUnderlyingTokens = strategyData.underlyingTokens.length;
        for (uint256 i; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[strategyData.underlyingTokens[i++]] = true;
            }
        }
    }

    /// EXTERNAL FUNCTIONS ///

    // PERMISSIONED FUNCTIONS

    /// @notice Requeries reward tokens directly from Pendle smart contracts.
    /// @dev This can be permissionless since this data is 1:1 with dependent
    ///      contracts  and takes no parameters.
    function reQueryRewardTokens() external {
        delete strategyData.rewardTokens;

        strategyData.rewardTokens = strategyData.lp.getRewardTokens();
    }

    /// @notice Requeries underlying tokens directly from Pendle smart contracts.
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

        // Query underlying tokens from Pendle contracts.
        strategyData.underlyingTokens = strategyData.sy.getTokensIn();
        numCurrentTokens = strategyData.underlyingTokens.length;

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

            // claim Pendle rewards
            sd.lp.redeemRewards(address(this));

            (
                SwapperLib.Swap[] memory swapDataArray,
                uint256 minLPAmount,
                ApproxParams memory approx
            ) = abi.decode(data, (SwapperLib.Swap[], uint256, ApproxParams));

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
                    protocolFee = FixedPointMathLib.mulDiv(rewardAmount, harvestFee, 1e18);
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
                            revert PendleLPCToken__InvalidSwapper(
                                i,
                                swapDataArray[i].target
                            );
                        }

                        SwapperLib.swap(centralRegistry, swapDataArray[i]);
                    }
                }
            }

            // mint SY
            {
                uint256 numUnderlyingTokens = sd.underlyingTokens.length;
                address underlyingToken;
                uint256 balance;
                for (uint256 i; i < numUnderlyingTokens; ++i) {
                    underlyingToken = sd.underlyingTokens[i];

                    if (underlyingToken == address(0)) {
                        balance = address(this).balance;
                        if (balance > 0) {
                            sd.sy.deposit{ value: balance }(
                                address(this),
                                underlyingToken,
                                balance,
                                0
                            );
                        }
                    } else {
                        balance = IERC20(underlyingToken).balanceOf(
                            address(this)
                        );
                        if (balance > 0) {
                            SwapperLib._approveTokenIfNeeded(
                                underlyingToken,
                                address(sd.sy),
                                balance
                            );
                            sd.sy.deposit(
                                address(this),
                                underlyingToken,
                                balance,
                                0
                            );
                        }
                    }
                }
            }

            // add liquidity with SY
            {
                uint256 balance = sd.sy.balanceOf(address(this));
                SwapperLib._approveTokenIfNeeded(
                    address(sd.sy),
                    address(sd.router),
                    balance
                );

                (yield, ) = sd.router.addLiquiditySingleSy(
                    address(this),
                    address(sd.lp),
                    balance,
                    minLPAmount,
                    approx
                );
            }

            // Update vesting info, query `vestPeriod` here to cache it.
            _setNewVaultData(yield, vestPeriod);

            emit Harvest(yield);
        }
        // else yield is zero
    }
}
