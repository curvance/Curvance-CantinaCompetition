// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, SafeTransferLib, IERC20, Math, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";

import { WAD } from "contracts/libraries/Constants.sol";

import { IReader } from "contracts/interfaces/external/gmx/IReader.sol";
import { IGMXDeposit } from "contracts/interfaces/external/gmx/IGMXDeposit.sol";
import { IGMXEventUtils } from "contracts/interfaces/external/gmx/IGMXEventUtils.sol";
import { IGMXExchangeRouter } from "contracts/interfaces/external/gmx/IGMXExchangeRouter.sol";

contract GMCToken is CTokenCompounding {
    using Math for uint256;

    /// STORAGE ///

    /// @notice The address of GMX Deposit Vault.
    address public gmxDepositVault;

    /// @notice The address of GMX Exchange Router.
    address public gmxExchangeRouter;

    /// @notice The address of GMX Router.
    address public gmxRouter;

    /// @notice The address of GMX Datastore.
    address public gmxDataStore;

    /// @notice The address of GMX Deposit Handler.
    address public gmxDepositHandler;

    /// @notice An array of underlying tokens.
    /// First element is long token and second one is short token.
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

    /// @notice Harvests and compounds outstanding vault rewards and
    ///         vests pending rewards.
    /// @dev Only callable by Gelato Network bot.
    function harvest(
        bytes calldata
    ) external override returns (uint256 yield) {
        // Checks whether the caller can compound the vault yield
        _canCompound();

        // Vest pending rewards if there are any
        _vestIfNeeded();

        // Can only harvest once previous reward period is done.
        if (_checkVestStatus(_vaultData)) {
            _updateVestingPeriodIfNeeded();

            // Claim GM pool rewards.
            uint256[] memory rewardAmounts = _claimReward();

            for (uint256 i = 0; i < 2; ++i) {
                if (rewardAmounts[i] > 0) {
                    // Take protocol fee.
                    uint256 protocolFee = rewardAmounts[i].mulDivDown(
                        centralRegistry.protocolHarvestFee(),
                        1e18
                    );
                    rewardAmounts[i] -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        underlyingTokens[i],
                        centralRegistry.feeAccumulator(),
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

            for (uint256 i = 0; i < 2; ) {
                SafeTransferLib.safeApprove(
                    underlyingTokens[i],
                    gmxRouter,
                    rewardAmounts[i]
                );
                data[++i] = abi.encodeWithSelector(
                    IGMXExchangeRouter.sendTokens.selector,
                    underlyingTokens[i],
                    gmxDepositVault,
                    rewardAmounts[i]
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
            // Return a 1 for harvester to recognize success
            yield = 1;
        }
    }

    // @dev Called by GMX deposit handler after a deposit execution.
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

        // Update vesting info.
        // Cache vest period so we do not need to load it twice.
        uint256 _vestPeriod = vestPeriod;
        _vaultData = _packVaultData(
            yield.mulDivDown(WAD, _vestPeriod),
            block.timestamp + _vestPeriod
        );

        delete _isDepositKey[key];

        emit Harvest(yield);
    }

    /// @notice Set GMX Deposit Vault address
    function setGMXDepositVault(address newDepositVault) external {
        _checkDaoPermissions();

        _setGMXDepositVault(newDepositVault);
    }

    /// @notice Set GMX Exchange Router address
    function setGMXExchangeRouter(address newExchangeRouter) external {
        _checkDaoPermissions();

        _setGMXExchangeRouter(newExchangeRouter);
    }

    /// @notice Set GMX Router address
    function setGMXRouter(address newRouter) external {
        _checkDaoPermissions();

        _setGMXRouter(newRouter);
    }

    /// @notice Set GMX DataStore address
    function setGMXDataStore(address newDataStore) external {
        _checkDaoPermissions();

        _setGMXDataStore(newDataStore);
    }

    /// @notice Set GMX Deposit Handler address
    function setGMXDepositHandler(address newDepositHandler) external {
        _checkDaoPermissions();

        _setGMXDepositHandler(newDepositHandler);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Set GMX Deposit Vault address
    function _setGMXDepositVault(address newDepositVault) internal {
        if (newDepositVault == address(0)) {
            revert GMCToken__GMXDepositVaultIsZeroAddress();
        }

        gmxDepositVault = newDepositVault;
    }

    /// @notice Set GMX Exchange Router address
    function _setGMXExchangeRouter(address newExchangeRouter) internal {
        if (newExchangeRouter == address(0)) {
            revert GMCToken__GMXExchangeRouterIsZeroAddress();
        }

        gmxExchangeRouter = newExchangeRouter;
    }

    /// @notice Set GMX Router address
    function _setGMXRouter(address newRouter) internal {
        if (newRouter == address(0)) {
            revert GMCToken__GMXRouterIsZeroAddress();
        }

        gmxRouter = newRouter;
    }

    /// @notice Set GMX DataStore address
    function _setGMXDataStore(address newDataStore) internal {
        if (newDataStore == address(0)) {
            revert GMCToken__GMXDataStoreIsZeroAddress();
        }

        gmxDataStore = newDataStore;
    }

    /// @notice Set GMX Deposit Handler address
    function _setGMXDepositHandler(address newDepositHandler) internal {
        if (newDepositHandler == address(0)) {
            revert GMCToken__GMXDepositHandlerIsZeroAddress();
        }

        gmxDepositHandler = newDepositHandler;
    }

    // INTERNAL POSITION LOGIC

    /// @notice Gets the balance of assets inside GM pool.
    /// @return The current balance of assets.
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Claim rewards from GM pool.
    function _claimReward() internal returns (uint256[] memory rewardAmounts) {
        // claim GM pool rewards
        address[] memory markets = new address[](2);
        markets[0] = asset();
        markets[1] = asset();

        rewardAmounts = IGMXExchangeRouter(gmxExchangeRouter).claimFundingFees(
            markets,
            underlyingTokens,
            address(this)
        );
    }
}
