// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, SafeTransferLib, ERC20 } from "@solmate/mixins/ERC4626.sol";
import { Math } from "src/utils/Math.sol";
import { PriceRouter } from "src/PricingOperations/PriceRouter.sol";

// External interfaces
import { IBooster } from "src/interfaces/Convex/IBooster.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { ICurveFi } from "src/interfaces/Curve/ICurveFi.sol";
import { ICurveSwaps } from "src/interfaces/Curve/ICurveSwaps.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";

contract PositionVault is ERC4626 {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                        REWARD/HARVESTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // Internal stored total assets, not accounting for
    uint256 internal _totalAssets;
    uint128 internal _rewardRate;
    uint64 internal _vestingPeriodEnd;
    uint64 internal _lastVestClaim;

    /**
     * @notice Fee taken on harvesting rewards.
     * @dev 18 decimals
     */
    uint64 public platformFee = 0.2e18;

    /**
     * @notice Address where fees are sent.
     */
    address public feeAccumulator;

    /**
     * @notice Contract to get pricing information.
     */
    PriceRouter public priceRouter;

    /**
     * @notice Period newly harvested rewards are vested over.
     */
    uint32 public constant REWARD_PERIOD = 7 days;

    function _harvest() internal {
        // TODO this might need the ability to vest rewards.
        // Can only harvest is previous reward period is done.
        if (_rewardRate > 0 && _lastVestClaim >= _vestingPeriodEnd) {
            // Harvest convex position.
            rewarder.getReward(address(this), true);

            // Save token balances
            uint256 rewardTokenCount = 2 + rewarder.extraRewardsLength();
            ERC20[] memory rewardTokens = new ERC20[](rewardTokenCount);
            rewardTokens[0] = CRV;
            rewardTokens[1] = CVX;
            uint256[] memory rewardBalances = new uint256[](rewardTokenCount);
            rewardBalances[0] = CRV.balanceOf(address(this));
            rewardBalances[1] = CVX.balanceOf(address(this));
            for (uint256 i = 2; i < rewardTokenCount; i++) {
                rewardTokens[i] = ERC20(rewarder.extraRewards(i - 2));
                rewardBalances[i] = rewardTokens[i].balanceOf(address(this));
            }

            // Store USD value in.
            uint256 valueIn;
            uint256 ethOut;
            address[4] memory pools;
            for (uint256 i = 0; i < rewardTokenCount; i++) {
                // Take platform fee
                uint256 fee = rewardBalances[i].mulDivDown(platformFee, 1e18);
                rewardBalances[i] -= fee;
                rewardTokens[i].safeTransfer(feeAccumulator, fee);

                uint256 valueInUSD = rewardBalances[i].mulDivDown(
                    priceRouter.getPriceInUSD(rewardTokens[i]),
                    10**rewardTokens[i].decimals()
                );
                CurveSwapParams memory swapParams = abitraryToETH[rewardTokens[i]];
                if (valueInUSD >= swapParams.minUSDValueToSwap) {
                    valueIn += valueInUSD;
                    // Perform Swap into ETH.
                    ethOut += curveRegistryExchange.exchange_multiple(
                        swapParams.route,
                        swapParams.swapParams,
                        swapParams.assets,
                        0,
                        pools,
                        address(this)
                    );
                }
            }
            // Take upkeep fee.

            // Convert assets back into asset.
            CurveSwapParams memory swapParams = abitraryToETH[WETH];
            uint256 assetsOut = curveRegistryExchange.exchange_multiple(
                swapParams.route,
                swapParams.swapParams,
                swapParams.assets,
                0,
                pools,
                address(this)
            );
            // Deposit assets to Curve, using depositData?
            _addLiquidityToCurve(assetsOut);

            // Deposit Assets to Convex.
            assetsOut = asset.balanceOf(address(this));
            afterDeposit(assetsOut);

            // Update _rewardRate
            _rewardRate = uint128(assetsOut / REWARD_PERIOD);
            // Update _vestingPeriodEnd
            _vestingPeriodEnd = uint64(block.timestamp) + REWARD_PERIOD;
            // Update _lastVestClaim
            _lastVestClaim = uint64(block.timestamp);
        } else revert("Can not harvest now");
    }

    function _calculatePendingRewards() internal view returns (uint256 pendingRewards) {
        // Used by totalAssets
        uint64 currentTime = uint64(block.timestamp);
        if (_rewardRate > 0 && _lastVestClaim < _vestingPeriodEnd) {
            // There are pending rewards.
            pendingRewards = currentTime < _vestingPeriodEnd
                ? (_rewardRate * (currentTime - _lastVestClaim))
                : (_rewardRate * (_vestingPeriodEnd - _lastVestClaim));
        } // else there are no pending rewards.
    }

    function _vestRewards(uint256 _ta) internal {
        // Update some reward timestamp.
        _lastVestClaim = uint64(block.timestamp);

        // Set internal balance equal to totalAssets value
        _totalAssets = _ta;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewDeposit.
        require((shares = _previewDeposit(assets, ta)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        if (pending > 0) _vestRewards(ta);
        afterDeposit(assets);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        assets = _previewMint(shares, ta); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        if (pending > 0) _vestRewards(ta);
        afterDeposit(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        shares = _previewWithdraw(assets, ta); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        if (pending > 0) _vestRewards(ta);
        beforeWithdraw(assets);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = _previewRedeem(shares, ta)) != 0, "ZERO_ASSETS");

        if (pending > 0) _vestRewards(ta);
        beforeWithdraw(assets);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        // Returns stored internal balance + pending rewards that are vested.
        return _totalAssets + _calculatePendingRewards();
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, totalSupply);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        return _previewMint(shares, totalAssets());
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _previewWithdraw(assets, totalAssets());
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function _convertToShares(uint256 assets, uint256 _ta) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply;

        shares = totalShares == 0 ? assets.changeDecimals(asset.decimals(), 18) : assets.mulDivDown(totalShares, _ta);
    }

    function _convertToAssets(uint256 shares, uint256 _ta) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply;

        assets = totalShares == 0 ? shares.changeDecimals(18, asset.decimals()) : shares.mulDivDown(_ta, totalShares);
    }

    function _previewDeposit(uint256 assets, uint256 _ta) internal view returns (uint256) {
        return _convertToShares(assets, _ta);
    }

    function _previewMint(uint256 shares, uint256 _ta) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply;

        assets = totalShares == 0 ? shares.changeDecimals(18, asset.decimals()) : shares.mulDivUp(_ta, totalShares);
    }

    function _previewWithdraw(uint256 assets, uint256 _ta) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply;

        shares = totalShares == 0 ? assets.changeDecimals(asset.decimals(), 18) : assets.mulDivUp(totalShares, _ta);
    }

    function _previewRedeem(uint256 shares, uint256 _ta) internal view returns (uint256) {
        return _convertToAssets(shares, _ta);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    // Should be set during initialization of clone.
    uint256 public pid;
    IBaseRewardPool public rewarder;
    IBooster private booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    function beforeWithdraw(uint256 assets) internal {
        IBaseRewardPool rewardPool = IBaseRewardPool(rewarder);
        rewardPool.withdrawAndUnwrap(assets, false);
    }

    function afterDeposit(uint256 assets) internal {
        asset.safeApprove(address(booster), assets);
        booster.deposit(pid, assets, true);
    }

    /**
     * @notice Curve registry exchange contract.
     */
    ICurveSwaps public curveRegistryExchange; // 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7

    // So we store the swap path from each reward token to ETH.
    // Then store a swap path from ETH to the final token we need.

    struct CurveSwapParams {
        address[9] route;
        uint256[3][4] swapParams;
        uint256 assets;
        ERC20 assetIn;
        uint96 minUSDValueToSwap;
    }

    // Stores swapping information to go from an arbitrary reward token to ETH.
    mapping(ERC20 => CurveSwapParams) public abitraryToETH;

    // Stores swapping information to go from ETH to target token to supply liquidity on Curve
    mapping(ERC20 => CurveSwapParams) public ethToTarget;

    /**
     * @notice Allows caller to make swaps using the Curve Exchange.
     * @param swapData bytes variable storing the following swap information
     *      address[9] route: array of [initial token, pool, token, pool, token, ...] that specifies the swap route on Curve.
     *      uint256[3][4] swapParams: multidimensional array of [i, j, swap type]
     *          where i and j are the correct values for the n'th pool in `_route` and swap type should be
     *              1 for a stableswap `exchange`,
     *              2 for stableswap `exchange_underlying`,
     *              3 for a cryptoswap `exchange`,
     *              4 for a cryptoswap `exchange_underlying`
            ERC20 assetIn: the asset being swapped
            uint256 assets: the amount of assetIn you want to swap with
     *      uint256 assetsOutMin: the minimum amount of assetOut tokens you want from the swap
     * @param receiver the address assetOut token should be sent to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithCurve(bytes memory swapData, address receiver) public returns (uint256 amountOut) {
        (
            address[9] memory route,
            uint256[3][4] memory swapParams,
            ERC20 assetIn,
            uint256 assets,
            uint256 assetsOutMin
        ) = abi.decode(swapData, (address[9], uint256[3][4], ERC20, uint256, uint256));

        // Transfer assets to this contract to swap.
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        address[4] memory pools;

        // Execute the stablecoin swap.
        assetIn.safeApprove(address(curveRegistryExchange), assets);
        amountOut = curveRegistryExchange.exchange_multiple(route, swapParams, assets, assetsOutMin, pools, receiver);
    }

    // Data related to Curve LP deposits.
    ERC20 private targetAsset;
    uint8 private coinsLength;
    uint8 private targetIndex;
    bool private useUnderlying = false;
    address private pool;

    /**
     * @notice Attempted to deposit into an unsupported Curve Pool.
     */
    error DepositRouter__UnsupportedCurveDeposit();

    function _addLiquidityToCurve(uint256 amount) internal {
        targetAsset.approve(pool, amount);
        if (coinsLength == 2) {
            uint256[2] memory amounts;
            amounts[targetIndex] = amount;
            if (useUnderlying) {
                ICurveFi(pool).add_liquidity(amounts, 0, true);
            } else {
                ICurveFi(pool).add_liquidity(amounts, 0);
            }
        } else if (coinsLength == 3) {
            uint256[3] memory amounts;
            amounts[targetIndex] = amount;
            if (useUnderlying) {
                ICurveFi(pool).add_liquidity(amounts, 0, true);
            } else {
                ICurveFi(pool).add_liquidity(amounts, 0);
            }
        } else if (coinsLength == 4) {
            uint256[4] memory amounts;
            amounts[targetIndex] = amount;
            if (useUnderlying) {
                ICurveFi(pool).add_liquidity(amounts, 0, true);
            } else {
                ICurveFi(pool).add_liquidity(amounts, 0);
            }
        } else revert DepositRouter__UnsupportedCurveDeposit();
    }
}
