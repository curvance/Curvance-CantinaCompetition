// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { CTokenCompounding, SafeTransferLib, IERC20, Math, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { IPendleRouter, ApproxParams } from "contracts/interfaces/external/pendle/IPendleRouter.sol";
import { IPMarket } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IPPrincipalToken } from "contracts/interfaces/external/pendle/IPPrincipalToken.sol";
import { IPYieldToken } from "contracts/interfaces/external/pendle/IPYieldToken.sol";
import { IStandardizedYield } from "contracts/interfaces/external/pendle/IStandardizedYield.sol";

contract PendleLPCToken is CTokenCompounding {
    using Math for uint256;

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

    StrategyData public strategyData; // position vault packed configuration

    mapping(address => bool) public isUnderlyingToken; // token => is underlying token

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error PendleLPCToken__Unauthorized();
    error PendleLPCToken__InvalidSwapper(
        uint256 index,
        address invalidSwapper
    );

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address lendtroller_,
        IPendleRouter router_
    ) CTokenCompounding(centralRegistry_, asset_, lendtroller_) {
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

    function reQueryRewardTokens() external {
        delete strategyData.rewardTokens;

        strategyData.rewardTokens = strategyData.lp.getRewardTokens();
    }

    function reQueryUnderlyingTokens() external {
        address[] memory underlyingTokens = strategyData.underlyingTokens;
        uint256 numUnderlyingTokens = underlyingTokens.length;
        for (uint256 i = 0; i < numUnderlyingTokens; ) {
            unchecked {
                isUnderlyingToken[underlyingTokens[i++]] = false;
            }
        }

        strategyData.underlyingTokens = strategyData.sy.getTokensIn();

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
        if (!centralRegistry.isHarvester(msg.sender)) {
            revert PendleLPCToken__Unauthorized();
        }

        if (_vaultStatus != 2) {
            _revert(_VAULT_NOT_ACTIVE_SELECTOR);
        }

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
                    protocolFee = rewardAmount.mulDivDown(harvestFee, 1e18);
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

                        SwapperLib.swap(swapDataArray[i]);
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

            // There is no gauge for pendle, so no _afterDeposit here
            // update vesting info
            _vaultData = _packVaultData(
                yield.mulDivDown(WAD, vestPeriod),
                block.timestamp + vestPeriod
            );

            emit Harvest(yield);
        }
        // else yield is zero
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Gets the balance of assets inside Aura reward pool
    /// @return The current balance of assets
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return IERC20(asset()).balanceOf(address(this));
    }
}
