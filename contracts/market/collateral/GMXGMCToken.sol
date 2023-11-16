// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompoundingBase, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/market/collateral/CTokenCompoundingBase.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { IReader } from "contracts/interfaces/external/gmx/IReader.sol";
import { IGMXDeposit } from "contracts/interfaces/external/gmx/IGMXDeposit.sol";
import { IGMXEventUtils } from "contracts/interfaces/external/gmx/IGMXEventUtils.sol";
import { IGMXExchangeRouter } from "contracts/interfaces/external/gmx/IGMXExchangeRouter.sol";

contract GMXGMPositionVault is CTokenCompoundingBase {
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

    error GMXGMCToken__Unauthorized();
    error GMXGMCToken__ChainIsNotSupported();
    error GMXGMCToken__MarketIsInvalid();
    error GMXGMCToken__CallerIsNotGMXDepositHandler();
    error GMXGMCToken__InvalidDepositKey();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        ERC20 asset_,
        address lendtroller_
    ) CTokenCompoundingBase(centralRegistry_, asset_, lendtroller_) {
        if (block.chainid != 42161) {
            revert GMXGMCToken__ChainIsNotSupported();
        }

        IReader.MarketProps memory market = IReader(GMX_READER).getMarket(
            GMX_DATASTORE,
            address(asset_)
        );

        if (
            market.longToken == address(0) && market.shortToken == address(0)
        ) {
            revert GMXGMCToken__MarketIsInvalid();
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
    function harvest(bytes calldata) external override returns (uint256) {
        if (!centralRegistry.isHarvester(msg.sender)) {
            revert GMXGMCToken__Unauthorized();
        }

        if (_vaultStatus != 2) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

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
            revert GMXGMCToken__CallerIsNotGMXDepositHandler();
        }
        if (!_isDepositKey[key]) {
            revert GMXGMCToken__InvalidDepositKey();
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

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

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
