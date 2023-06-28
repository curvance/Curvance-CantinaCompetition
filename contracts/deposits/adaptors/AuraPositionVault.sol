// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, PriceRouter } from "./BasePositionVault.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

// External interfaces
import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";

contract AuraPositionVault is BasePositionVault {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                             STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Swap {
        address target;
        bytes call;
    }

    /**
     * @notice Balancer vault contract.
     */
    IBalancerVault public balancerVault;

    /**
     * @notice Balancer Pool Id.
     */
    bytes32 public balancerPoolId;

    /**
     * @notice Aura Pool Id.
     */
    uint256 public pid;

    /**
     * @notice Aura Rewarder contract.
     */
    IBaseRewardPool public rewarder;

    /**
     * @notice Aura Booster contract.
     */
    IBooster public booster;

    /**
     * @notice Aura reward assets.
     */
    address[] public rewardTokens;

    /**
     * @notice Balancer LP underlying assets.
     */
    address[] public underlyingTokens;
    mapping(address => bool) public isUnderlyingToken;

    /**
     * @notice Is approved target for swap.
     */
    mapping(address => bool) public isApprovedTarget;

    /**
     * @notice Mainnet token contracts important for this vault.
     */
    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant BAL =
        ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    ERC20 private constant AURA =
        ERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);

    // Owner needs to be able to set swap paths, deposit data, fee, fee accumulator
    /**
     * @notice Value out from harvest swaps must be greater than value in * 1 - (harvestSlippage + upkeepFee);
     */
    uint64 public harvestSlippage = 0.01e18;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SetApprovedTarget(address target, bool isApproved);
    event HarvestSlippageChanged(uint64 slippage);
    event Harvest(uint256 yield);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ConvexPositionVault__UnsupportedCurveDeposit();
    error AuraPositionVault__BadSlippage();
    error ConvexPositionVault__WatchdogNotSet();
    error ConvexPositionVault__LengthMismatch();

    /*//////////////////////////////////////////////////////////////
                              SETUP LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Vaults are designed to be deployed using Minimal Proxy Contracts, but they can be deployed normally,
     *         but `initialize` must ALWAYS be called either way.
     */
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        ICentralRegistry _centralRegistry
    ) BasePositionVault(_asset, _name, _symbol, _decimals, _centralRegistry) {}

    /**
     * @notice Initialize function to fully setup this vault.
     */
    function initialize(
        ERC20 _asset,
        ICentralRegistry _centralRegistry,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        BasePositionVault.PositionVaultMetaData calldata _metaData,
        bytes memory _initializeData
    ) public override initializer {
        super.initialize(
            _asset,
            _centralRegistry,
            _name,
            _symbol,
            _decimals,
            _metaData,
            _initializeData
        );
        (
            address _balancerVault,
            bytes32 _balancerPoolId,
            address[] memory _underlyingTokens,
            uint256 _pid,
            address _rewarder,
            address _booster,
            address[] memory _rewardTokens
        ) = abi.decode(
                _initializeData,
                (
                    address,
                    bytes32,
                    address[],
                    uint256,
                    address,
                    address,
                    address[]
                )
            );
        balancerVault = IBalancerVault(_balancerVault);
        balancerPoolId = _balancerPoolId;
        underlyingTokens = _underlyingTokens;
        for (uint256 i = 0; i < _underlyingTokens.length; i++) {
            isUnderlyingToken[_underlyingTokens[i]] = true;
        }
        pid = _pid;
        rewarder = IBaseRewardPool(_rewarder);
        booster = IBooster(_booster);
        rewardTokens = _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateHarvestSlippage(uint64 _slippage) external onlyDaoManager {
        harvestSlippage = _slippage;
        emit HarvestSlippageChanged(_slippage);
    }

    function setIsApprovedTarget(address _target, bool _isApproved)
        external
        onlyDaoManager
    {
        isApprovedTarget[_target] = _isApproved;
    }

    function setRewardTokens(address[] memory _rewardTokens)
        external
        onlyDaoManager
    {
        rewardTokens = _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvest(bytes memory data)
        public
        override
        whenNotShutdown
        nonReentrant
        returns (uint256 yield)
    {
        Swap[] memory swapDataArray = abi.decode(data, (Swap[]));

        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // We need to claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest once previous reward period is done.
        if (
            positionVaultAccounting._lastVestClaim >=
            positionVaultAccounting._vestingPeriodEnd
        ) {
            // Harvest aura position.
            rewarder.getReward(address(this), true);

            // Claim extra rewards
            uint256 rewardTokenCount = 2 + rewarder.extraRewardsLength();
            for (uint256 i = 2; i < rewardTokenCount; ++i) {
                IRewards extraReward = IRewards(rewarder.extraRewards(i - 2));
                extraReward.getReward();
            }

            // swap assets to one of pool token
            uint256 valueIn;
            for (uint256 i = 0; i < rewardTokens.length; ++i) {
                ERC20 reward = ERC20(rewardTokens[i]);
                uint256 amount = reward.balanceOf(address(this));
                if (amount == 0) continue;

                // Take platform fee
                uint256 protocolFee = amount.mulDivDown(
                    positionVaultMetaData.platformFee,
                    1e18
                );
                amount -= protocolFee;
                SafeTransferLib.safeTransfer(address(reward),
                    positionVaultMetaData.feeAccumulator,
                    protocolFee
                );

                uint256 valueInUSD = amount.mulDivDown(
                    positionVaultMetaData.priceRouter.getPriceUSD(address(reward)),
                    10**reward.decimals()
                );

                valueIn += valueInUSD;

                if (!isUnderlyingToken[address(reward)]) {
                    _swap(address(reward), swapDataArray[i]);
                }
            }

            // add liquidity to balancer
            uint256 valueOut;
            uint256 length = underlyingTokens.length;
            address[] memory assets = new address[](length);
            uint256[] memory maxAmountsIn = new uint256[](length);
            for (uint256 i = 0; i < length; ++i) {
                assets[i] = underlyingTokens[i];
                maxAmountsIn[i] = ERC20(assets[i]).balanceOf(address(this));
                _approveTokenIfNeeded(assets[i], address(balancerVault));

                valueOut += maxAmountsIn[i].mulDivDown(
                    positionVaultMetaData.priceRouter.getPriceUSD(
                        assets[i]
                    ),
                    10**ERC20(assets[i]).decimals()
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
            positionVaultAccounting._rewardRate = uint128(
                yield.mulDivDown(REWARD_SCALER, REWARD_PERIOD)
            );
            positionVaultAccounting._vestingPeriodEnd =
                uint64(block.timestamp) +
                REWARD_PERIOD;
            positionVaultAccounting._lastVestClaim = uint64(block.timestamp);
            emit Harvest(yield);
        } // else yield is zero.
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

    /**
     * @dev Swap input token
     * @param _inputToken The input asset address
     * @param _swapData The swap aggregation data
     */
    function _swap(address _inputToken, Swap memory _swapData) private {
        require(isApprovedTarget[_swapData.target], "invalid swap target");

        _approveTokenIfNeeded(_inputToken, address(_swapData.target));

        (bool success, bytes memory retData) = _swapData.target.call(
            _swapData.call
        );

        propagateError(success, retData, "swap");

        require(success == true, "calling swap got an error");
    }

    /**
     * @dev Approve token if needed
     * @param _token The token address
     * @param _spender The spender address
     */
    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (ERC20(_token).allowance(address(this), _spender) == 0) {
            SafeTransferLib.safeApprove(_token, _spender, type(uint256).max);
        }
    }

    /**
     * @dev Propagate error message
     * @param success If transaction is successful
     * @param data The transaction result data
     * @param errorMessage The custom error message
     */
    function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) public pure {
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }
}
