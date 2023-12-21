// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";

import { EXP_SCALE } from "contracts/libraries/Constants.sol";
import { IReader } from "contracts/interfaces/external/gmx/IReader.sol";
import { IGMXDeposit } from "contracts/interfaces/external/gmx/IGMXDeposit.sol";
import { IGMXEventUtils } from "contracts/interfaces/external/gmx/IGMXEventUtils.sol";
import { IGMXExchangeRouter } from "contracts/interfaces/external/gmx/IGMXExchangeRouter.sol";

contract GMXGMPositionVault is BasePositionVault {
    using Math for uint256;

    /// CONSTANTS ///

    /// @notice The address of GMX Deposit Vault.
    address public constant GMX_DEPOSIT_VAULT =
        0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;

    /// @notice The address of GMX Exchange Router.
    address public constant GMX_EXCHANGE_ROUTER =
        0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8;

    /// @notice The address of GMX Router.
    address public constant GMX_ROUTER =
        0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;

    /// @notice The address of GMX Reader.
    address public constant GMX_READER =
        0xf60becbba223EEA9495Da3f606753867eC10d139;

    /// @notice The address of GMX Datastore.
    address public constant GMX_DATASTORE =
        0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;

    address public constant GMX_DEPOSIT_HANDLER =
        0x9Dc4f12Eb2d8405b499FB5B8AF79a5f64aB8a457;

    /// STORAGE ///

    /// @notice An array of underlying tokens.
    /// First element is long token and second one is short token.
    address[] public underlyingTokens;

    mapping(bytes32 => bool) internal _isDepositKey;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error GMXPositionVault__ChainIsNotSupported();
    error GMXPositionVault__MarketIsInvalid();
    error GMXPositionVault__CallerIsNotGMXDepositHandler();
    error GMXPositionVault__InvalidDepositKey();

    /// CONSTRUCTOR ///

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_
    ) BasePositionVault(asset_, centralRegistry_) {
        if (block.chainid != 42161) {
            revert GMXPositionVault__ChainIsNotSupported();
        }

        IReader.MarketProps memory market = IReader(GMX_READER).getMarket(
            GMX_DATASTORE,
            address(asset_)
        );

        if (
            market.longToken == address(0) && market.shortToken == address(0)
        ) {
            revert GMXPositionVault__MarketIsInvalid();
        }

        underlyingTokens.push(market.longToken);
        underlyingTokens.push(market.shortToken);
    }

    /// EXTERNAL FUNCTIONS ///

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards and
    ///         vests pending rewards.
    /// @dev Only callable by Gelato Network bot.
    function harvest(
        bytes calldata
    ) external override onlyHarvestor returns (uint256) {
        if (_vaultIsActive == 1) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

        uint256 pending = _calculatePendingRewards();

        if (pending > 0) {
            // Claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest once previous reward period is done.
        if (_checkVestStatus(_vaultData)) {
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
                GMX_DEPOSIT_VAULT,
                0.01e18
            );

            for (uint256 i = 0; i < 2; ) {
                SafeTransferLib.safeApprove(
                    underlyingTokens[i],
                    GMX_ROUTER,
                    rewardAmounts[i]
                );
                data[++i] = abi.encodeWithSelector(
                    IGMXExchangeRouter.sendTokens.selector,
                    underlyingTokens[i],
                    GMX_DEPOSIT_VAULT,
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

            bytes[] memory results = IGMXExchangeRouter(GMX_EXCHANGE_ROUTER)
                .multicall{ value: 0.01e18 }(data);
            _isDepositKey[bytes32(results[3])] = true;
        }
    }

    // @dev Called by GMX deposit handler after a deposit execution.
    function afterDepositExecution(
        bytes32 key,
        IGMXDeposit.Props memory,
        IGMXEventUtils.EventLogData memory eventData
    ) external {
        if (msg.sender != GMX_DEPOSIT_HANDLER) {
            revert GMXPositionVault__CallerIsNotGMXDepositHandler();
        }
        if (!_isDepositKey[key]) {
            revert GMXPositionVault__InvalidDepositKey();
        }

        uint256 yield = eventData.uintItems.items[0].value;

        _deposit(yield);

        // Update vesting info.
        // Cache vest period so we do not need to load it twice.
        uint256 _vestPeriod = vestPeriod;
        _vaultData = _packVaultData(
            yield.mulDivDown(EXP_SCALE, _vestPeriod),
            block.timestamp + _vestPeriod
        );

        delete _isDepositKey[key];

        emit Harvest(yield);
    }

    receive() external payable {}

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into GM pool.
    /// @param assets The amount of assets to deposit.
    function _deposit(uint256 assets) internal override {}

    /// @notice Withdraws specified amount of assets from GM pool.
    /// @param assets The amount of assets to withdraw.
    function _withdraw(uint256 assets) internal override {}

    /// @notice Gets the balance of assets inside GM pool.
    /// @return The current balance of assets.
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return ERC20(asset()).balanceOf(address(this));
    }

    /// @notice Pre calculation logic for migration start.
    /// @param newVault The new vault address.
    function _migrationStart(
        address newVault
    ) internal override returns (bytes memory) {
        _claimReward();

        for (uint256 i = 0; i < 2; ++i) {
            SafeTransferLib.safeApprove(
                underlyingTokens[i],
                newVault,
                type(uint256).max
            );
        }
    }

    /// @notice Claim rewards from GM pool.
    function _claimReward() internal returns (uint256[] memory rewardAmounts) {
        // claim GM pool rewards
        address[] memory markets = new address[](2);
        markets[0] = asset();
        markets[1] = asset();

        rewardAmounts = IGMXExchangeRouter(GMX_EXCHANGE_ROUTER)
            .claimFundingFees(markets, underlyingTokens, address(this));
    }
}
