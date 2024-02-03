// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, FixedPointMathLib, SafeTransferLib, IERC20, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";

import { IReader } from "contracts/interfaces/external/gmx/IReader.sol";
import { IGMXDeposit } from "contracts/interfaces/external/gmx/IGMXDeposit.sol";
import { IGMXEventUtils } from "contracts/interfaces/external/gmx/IGMXEventUtils.sol";
import { IGMXExchangeRouter } from "contracts/interfaces/external/gmx/IGMXExchangeRouter.sol";

contract GMCToken is CTokenCompounding {
    /// STORAGE ///

    /// @notice The address of GMX Deposit Vault.
    address gmxDepositVault;

    /// @notice The address of GMX Exchange Router.
    address gmxExchangeRouter;

    /// @notice The address of GMX Router.
    address gmxRouter;

    /// @notice The address of GMX Datastore.
    address gmxDataStore;

    /// @notice The address of GMX Deposit Handler.
    address gmxDepositHandler;

    /// @notice An array of underlying tokens.
    /// @dev First element is long token and second one is short token.
    address[] public underlyingTokens;

    mapping(bytes32 => bool) internal _isDepositKey;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error GMCToken__ChainIsNotSupported();
    error GMCToken__GMXDepositVaultIsZeroAddress();
    error GMCToken__GMXExchangeRouterIsZeroAddress();
    error GMCToken__GMXRouterIsZeroAddress();
    error GMCToken__GMXDataStoreIsZeroAddress();
    error GMCToken__GMXDepositHandlerIsZeroAddress();
    error GMCToken__MarketIsInvalid();
    error GMCToken__CallerIsNotGMXDepositHandler();
    error GMCToken__InvalidDepositKey();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        address gmxDepositVault_,
        address gmxExchangeRouter_,
        address gmxRouter_,
        address gmxReader_,
        address gmxDataStore_,
        address gmxDepositHandler_
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        // Make sure we are deploying this to Arbitrum.
        if (block.chainid != 42161) {
            revert GMCToken__ChainIsNotSupported();
        }

        _setGMXDepositVault(gmxDepositVault_);
        _setGMXExchangeRouter(gmxExchangeRouter_);
        _setGMXRouter(gmxRouter_);
        _setGMXDataStore(gmxDataStore_);
        _setGMXDepositHandler(gmxDepositHandler_);

        IReader.MarketProps memory market = IReader(gmxReader_).getMarket(
            gmxDataStore_,
            address(asset_)
        );

        // If the market is not properly configured, fail deployment.
        if (
            market.indexToken == address(0) ||
            market.longToken == address(0) ||
            market.shortToken == address(0)
        ) {
            revert GMCToken__MarketIsInvalid();
        }

        underlyingTokens.push(market.longToken);
        underlyingTokens.push(market.shortToken);
    }

    /// EXTERNAL FUNCTIONS ///

    receive() external payable {}

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards.
    /// @dev Only callable by Gelato Network bot.
    ///      Emits a {Harvest} event.
    /// @return yield The amount of new assets acquired from compounding
    ///               vault yield.
    function harvest(
        bytes calldata
    ) external override returns (uint256 yield) {
        // Checks whether the caller can compound the vault yield.
        _canCompound();

        // Vest pending rewards if there are any.
        _vestIfNeeded();

        // Can only harvest once previous reward period is done.
        if (_checkVestStatus(_vaultData)) {
            _updateVestingPeriodIfNeeded();

            // Claim pending GM pool rewards.
            uint256[] memory rewardAmounts = _claimReward();

            // Cache DAO Central Registry values to minimize runtime
            // gas costs.
            address feeAccumulator = centralRegistry.feeAccumulator();
            uint256 harvestFee = centralRegistry.protocolHarvestFee();

            for (uint256 i; i < 2; ++i) {
                // If there are no pending rewards for this token,
                // can skip to next reward token.
                if (rewardAmounts[i] > 0) {
                    // Take protocol fee for veCVE lockers and auto
                    // compounding bot.
                    uint256 protocolFee = FixedPointMathLib.mulDiv(
                        rewardAmounts[i],
                        harvestFee,
                        1e18
                    );
                    rewardAmounts[i] -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        underlyingTokens[i],
                        feeAccumulator,
                        protocolFee
                    );
                }
            }

            // Deposit claimed reward to GM pool.
            bytes[] memory data = new bytes[](4);

            data[0] = abi.encodeWithSelector(
                IGMXExchangeRouter.sendWnt.selector,
                gmxDepositVault,
                0.01e18
            );

            uint256 rewardAmount;
            for (uint256 i = 0; i < 2; ) {
                rewardAmount = rewardAmounts[i];
                SafeTransferLib.safeApprove(
                    underlyingTokens[i],
                    gmxRouter,
                    rewardAmount
                );
                data[++i] = abi.encodeWithSelector(
                    IGMXExchangeRouter.sendTokens.selector,
                    underlyingTokens[i],
                    gmxDepositVault,
                    rewardAmount
                );
            }
            data[3] = abi.encodeWithSelector(
                IGMXExchangeRouter.createDeposit.selector,
                IGMXExchangeRouter.CreateDepositParams(
                    address(this),
                    address(this),
                    address(0),
                    asset(),
                    underlyingTokens[0],
                    underlyingTokens[1],
                    new address[](0),
                    new address[](0),
                    0,
                    false,
                    0.01e18,
                    500000
                )
            );

            bytes[] memory results = IGMXExchangeRouter(gmxExchangeRouter)
                .multicall{ value: 0.01e18 }(data);
            _isDepositKey[bytes32(results[3])] = true;
            // Return a 1 for harvester to recognize success.
            yield = 1;
        }
    }

    /// @notice Used by GMX deposit handler to execute our desired asset
    ///         deposit.
    /// @dev Called by GMX deposit handler after a deposit execution.
    ///      Emits a {Harvest} event.
    /// @param key The deposit key.
    function afterDepositExecution(
        bytes32 key,
        IGMXDeposit.Props memory,
        IGMXEventUtils.EventLogData memory eventData
    ) external {
        if (msg.sender != gmxDepositHandler) {
            revert GMCToken__CallerIsNotGMXDepositHandler();
        }
        if (!_isDepositKey[key]) {
            revert GMCToken__InvalidDepositKey();
        }

        uint256 yield = eventData.uintItems.items[0].value;

        // Update vesting info, query `vestPeriod` here to cache it.
        _setNewVaultData(yield, vestPeriod);

        delete _isDepositKey[key];

        emit Harvest(yield);
    }

    /// @notice Sets the GMX Deposit Vault address.
    /// @param newDepositVault The new deposit vault address.
    function setGMXDepositVault(address newDepositVault) external {
        _checkDaoPermissions();

        _setGMXDepositVault(newDepositVault);
    }

    /// @notice Sets GMX Exchange Router address.
    /// @param newExchangeRouter The new exchange router address.
    function setGMXExchangeRouter(address newExchangeRouter) external {
        _checkDaoPermissions();

        _setGMXExchangeRouter(newExchangeRouter);
    }

    /// @notice Sets GMX Router address.
    /// @param newRouter The new GMX router address.
    function setGMXRouter(address newRouter) external {
        _checkDaoPermissions();

        _setGMXRouter(newRouter);
    }

    /// @notice Sets GMX Data Store address.
    /// @param newDataStore The new GMX Data Store address.
    function setGMXDataStore(address newDataStore) external {
        _checkDaoPermissions();

        _setGMXDataStore(newDataStore);
    }

    /// @notice Sets GMX Deposit Handler address.
    /// @param newDepositHandler The new GMX Deposit Handler address.
    function setGMXDepositHandler(address newDepositHandler) external {
        _checkDaoPermissions();

        _setGMXDepositHandler(newDepositHandler);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Sets the GMX Deposit Vault address.
    /// @param newDepositVault The new deposit vault address.
    function _setGMXDepositVault(address newDepositVault) internal {
        if (newDepositVault == address(0)) {
            revert GMCToken__GMXDepositVaultIsZeroAddress();
        }

        gmxDepositVault = newDepositVault;
    }

    /// @notice Sets GMX Exchange Router address.
    /// @param newExchangeRouter The new exchange router address.
    function _setGMXExchangeRouter(address newExchangeRouter) internal {
        if (newExchangeRouter == address(0)) {
            revert GMCToken__GMXExchangeRouterIsZeroAddress();
        }

        gmxExchangeRouter = newExchangeRouter;
    }

    /// @notice Sets GMX Router address.
    /// @param newRouter The new GMX router address.
    function _setGMXRouter(address newRouter) internal {
        if (newRouter == address(0)) {
            revert GMCToken__GMXRouterIsZeroAddress();
        }

        gmxRouter = newRouter;
    }

    /// @notice Sets GMX Data Store address.
    /// @param newDataStore The new GMX Data Store address.
    function _setGMXDataStore(address newDataStore) internal {
        if (newDataStore == address(0)) {
            revert GMCToken__GMXDataStoreIsZeroAddress();
        }

        gmxDataStore = newDataStore;
    }

    /// @notice Sets GMX Deposit Handler address.
    /// @param newDepositHandler The new GMX Deposit Handler address.
    function _setGMXDepositHandler(address newDepositHandler) internal {
        if (newDepositHandler == address(0)) {
            revert GMCToken__GMXDepositHandlerIsZeroAddress();
        }

        gmxDepositHandler = newDepositHandler;
    }

    // INTERNAL POSITION LOGIC

    /// @notice Claims rewards from the GM pool.
    /// @return rewardAmounts The reward amounts claimed from the GM pool.
    function _claimReward() internal returns (uint256[] memory rewardAmounts) {
        
        address[] memory markets = new address[](2);
        markets[0] = asset();
        markets[1] = asset();

        // Claim GM pool rewards.
        rewardAmounts = IGMXExchangeRouter(gmxExchangeRouter).claimFundingFees(
            markets,
            underlyingTokens,
            address(this)
        );
    }
}
