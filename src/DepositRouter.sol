// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Math } from "src/utils/Math.sol";
import { Uint32Array } from "src/libraries/Uint32Array.sol";

import { IYearnVault } from "src/interfaces/Yearn/IYearnVault.sol";
import { IBooster } from "src/interfaces/Convex/IBooster.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { ICurveFi } from "src/interfaces/Curve/ICurveFi.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Curvance Deposit Router
 * @notice Provides a universal interface allowing Curvance contracts to deposit and withdraw assets from:
 *         Convex
 *         Yearn
 * @author crispymangoes
 */
//TODO store positions in an OZ uint256 enumerable set?
//TODO need to vest rewards overtime
// Send some percent of rewards to CVE Rewarder, then keep the rest here to vest rewards
//Keepers and data feeds to automate harvesting, self funding upkeeps
//TODO so positions can be an underlying that accrues overtime, or one that needs to be harvested
contract DepositRouter is Ownable {
    using Uint32Array for uint32[];
    using SafeERC20 for ERC20;
    enum Platform {
        CONVEX, // you are not given an asset
        YEARN // you are given an asset
    }
    enum AccrualType {
        OVERTIME, // Share price increase
        HARVEST, // Harvesting rewards
        REBASE // Rebasing token like aTokens, would probs need to be treated like an overtime, and somehow internally store the share price?
    }

    //TODO might need a harvest function, and harveest params, and maybe a harvest swap path?
    struct Position {
        uint256 totalSupply; // total amount of outstanding shares, used with `balance` to determine a share price.
        uint256 totalBalance; // total balance of all operators in position. Think this needs to be totalBalance of all assets in the position.
        uint128 rewardRate; // Vested rewards distributed per second.
        uint64 lastAccrualTimestamp; // Last timestamp when vested tokens were claimed.
        uint64 endTimestamp; // The end time stamp for when all current rewards are vested.
        Platform platform;
        bytes positionData; // Stores arbritrary data for the position.
        ERC20 asset; // The underlying asset in a position.
        address[8] swapPools;
        uint256 fromAndTos; // to[7], from[7], .....to[1], from[1], to[0], from[0]
        uint256 depositData; // bool(useUnderlying), uint8(targetIndex), uint8(coinsCount), address(asset to deposit)
    }
    mapping(address => mapping(uint32 => uint256)) public operatorPositionShares;
    uint32[] public activePositions; // Array of all active positions.
    mapping(uint32 => Position) public positions;
    ///@dev 0 position id is reserved for empty

    uint32 public constant REWARD_PERIOD = 7 days;

    struct Operator {
        address owner; // What address can make changes to how this operator invests into positions.
        bool isOperator; // Bool indicating whether this operator has been set up.
        ERC20 asset;
        uint256 holdingBalance;
        uint256 openPositions; // Positions operator currently has funds in.
        uint256 positionRatios; // Desired ratio for funds in positions. Could maybe allow a position to be just this contract, where it allows for cheaper use deposit/withdraws, and keepers perform batched TXs.
        //TODO if positionRatios do not add up to 100, then remainder is designated for holding position.
    }

    mapping(address => Operator) public operators;
    uint32 public positionCount;

    function addPosition(
        ERC20 _asset,
        Platform _platform,
        bytes memory _positionData,
        address[8] memory _swapPools,
        uint256 _fromAndTos,
        uint256 _depositData
    ) external onlyOwner {
        uint32 positionId = positionCount + 1;
        if (activePositions.contains(positionId)) revert("Position already present");
        //TODO do some sanity checks for fromAndTos, and depositData, and swapPools.
        activePositions.push(positionId);
        positions[positionId] = Position({
            totalSupply: 0,
            totalBalance: 0,
            rewardRate: 0,
            lastAccrualTimestamp: uint64(block.timestamp),
            endTimestamp: type(uint64).max,
            platform: _platform,
            positionData: _positionData,
            asset: _asset,
            swapPools: _swapPools,
            fromAndTos: _fromAndTos,
            depositData: _depositData
        });
        positionCount++;
    }

    ///@dev operators can only be in positions with the SAME ASSET.
    function addOperator(
        address _operator,
        address _owner,
        ERC20 _asset,
        uint256 _positions,
        uint256 _positionRatios
    ) external onlyOwner {
        require(!operators[_operator].isOperator, "Operator already added.");
        //Positions are assumed to be packed to the front, IE you can not have a zero position between two non zero positions.
        // There should at the very least be position id 1 in the positions value.
        ///@dev position index 0 is the holding postion, where users funds are always deposited.
        require(_positions > 0, "0 is an invalid positions");
        // Loop through _positions and make sure it is valid.
        for (uint32 i = 0; i < 8; i++) {
            uint32 positionId = uint32(_positions >> (32 * i));
            if (positionId == 0) {
                require(uint256(_positions >> (32 * i)) == 0, "Positions must be packed to the front.");
            }
        }
        operators[_operator] = Operator({
            owner: _owner,
            isOperator: true,
            asset: _asset,
            holdingBalance: 0,
            openPositions: _positions,
            positionRatios: _positionRatios
        });
    }

    //============================================ Operator Functions ===========================================
    /**
     * Takes underlying token and deposits it into the underlying protocol
     * returns the amount of shares
     */
    function deposit(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        require(operators[operator].isOperator, "Only Operators can deposit.");
        //TODO could coordinate with Zeus to have this transfer from user themselves, then users approve this contract. But this could get sketchy if an operator went rogue;
        operators[operator].asset.safeTransferFrom(operator, address(this), amount);

        // Deposit assets into operator holding position.
        operators[operator].holdingBalance += amount;

        return amount;
    }

    function withdraw(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        // require(operators[operator].isOperator, "Only Operators can withdraw.");
        //TODO could coordinate with Zeus to have this transfer from user themselves, then users approve this contract. But this could get sketchy if an operator went rogue;

        // Withdraw assets from the holding positions.
        //TODO this should withdraw from positions in order.
        operators[operator].holdingBalance -= amount;
        operators[operator].asset.safeTransfer(operator, amount);

        return amount;
    }

    //============================================ Position Management Functions ===========================================
    /**
     * Updates a positions totalBalance, lastAccrualTimestamp, and determines the new Reward Rate, and sets new end timestamp.
     */
    function harvestPosition(uint32 _positionId) public {
        Position storage p = positions[_positionId];
        _updatePositionBalance(p); // Updates totalBalance and lastAccrualTimestamp
        if (p.platform == Platform.YEARN) {
            _harvestYearnPosition(p);
        } else if (p.platform == Platform.CONVEX) {
            _harvestConvexPosition(p);
        }
    }

    /**
     * @notice So I think the plan is to have keepers call this, and harvest functions.
     * Maybe have two different keepers, one dedicated to harvesting rewards, and another
     */
    function rebalance(
        address _operator,
        uint32 _fromPosition,
        uint32 _toPosition,
        uint256 _amount
    ) public {
        _withdrawFromPosition(_operator, _fromPosition, _amount);
        _depositToPosition(_operator, _toPosition, _amount);
    }

    function _depositToPosition(
        address _operator,
        uint32 _positionId,
        uint256 _amount
    ) internal {
        if (_positionId == 0) {
            // Depositing into holding position.
            operators[_operator].holdingBalance += _amount;
        } else {
            Position storage p = positions[_positionId];
            _updatePositionBalance(p); // This will take pending rewards and add it to p.totalBalance
            // So it needs to update totalBalance, and lastAccrualTimestamp

            if (p.platform == Platform.YEARN) {
                // Set _amount to actual backing of tokens in protocol.
                _amount = _depositToYearn(p, _amount);
            } else if (p.platform == Platform.CONVEX) {
                // Set _amount to actual backing of tokens in protocol.
                _amount = _depositToConvex(p, _amount);
            }

            // Now that pending rewards have been accounted for shares are more expensive.
            // Find shares owed to operator.
            uint256 sharesPerAsset = p.totalBalance == 0 ? 1e18 : (1e18 * p.totalSupply) / p.totalBalance;
            uint256 operatorShares = (_amount * sharesPerAsset) / 1e18;
            operatorPositionShares[_operator][_positionId] += operatorShares;
            p.totalSupply += operatorShares;
            p.totalBalance += _amount;
        }
    }

    function _withdrawFromPosition(
        address _operator,
        uint32 _positionId,
        uint256 _amount
    ) internal {
        if (_positionId == 0) {
            // Withdrawing from holding position.
            operators[_operator].holdingBalance -= _amount;
        } else {
            Position storage p = positions[_positionId];
            _updatePositionBalance(p); // This will take pending rewards and add it to p.totalBalance
            // So it needs to update totalBalance, and lastAccrualTimestamp
            uint256 actualWithdraw;

            if (p.platform == Platform.YEARN) {
                actualWithdraw = _withdrawFromYearn(p, _amount);
            } else if (p.platform == Platform.CONVEX) {
                actualWithdraw = _withdrawFromConvex(p, _amount);
            }

            require(actualWithdraw >= _amount, "Incomplete Withdraw.");

            // Now that pending rewards have been accounted for shares are more expensive.
            // Find shares owed to operator.
            uint256 assetsPerShare = (1e18 * p.totalBalance) / p.totalSupply;
            uint256 operatorShares = ((1e18 * _amount) / assetsPerShare);
            operatorPositionShares[_operator][_positionId] -= operatorShares;
            p.totalSupply -= operatorShares;
            p.totalBalance -= _amount;

            // If overwithdraw, credit operators holding position.
            if (actualWithdraw > _amount) operators[_operator].holdingBalance += actualWithdraw - _amount;
        }
    }

    function _updatePositionBalance(Position storage p) internal {
        //This takes the
        uint128 pendingRewards;
        uint64 time = uint64(block.timestamp);
        if (time > p.endTimestamp) {
            pendingRewards = (p.endTimestamp - p.lastAccrualTimestamp) * p.rewardRate;
        } else {
            pendingRewards = (time - p.lastAccrualTimestamp) * p.rewardRate;
        }
        p.lastAccrualTimestamp = time;
        p.totalBalance += pendingRewards;
    }

    //============================================ Yearn Integration Functions ===========================================
    // Needs to return the actual backing of tokens in the protocol.
    /**
     * @notice Balances are based off of sharePrice * Shares.
     * @dev Pricing inspired by Mai Finance yvOracle.
     *      https://ftmscan.com/address/0x530cd67a5898a20501cfcf74a3c68e21831d744c#code
     */
    function _depositToYearn(Position storage p, uint256 _amount) internal returns (uint256 amountDeposited) {
        address vaultAddress = abi.decode(p.positionData, (address));
        IYearnVault vault = IYearnVault(vaultAddress);
        p.asset.safeApprove(address(vault), _amount);
        uint256 shares = vault.deposit(_amount);
        amountDeposited = (shares * vault.pricePerShare()) / 10**vault.decimals();
    }

    /**
     * @notice Yearn compounds rewards to increase share price over time.
     *         So in order to determine yield, we need to compare our
     *         last stored balance + pending rewards to the current balance.
     */
    function _harvestYearnPosition(Position storage p) internal {
        address vaultAddress = abi.decode(p.positionData, (address));
        IYearnVault vault = IYearnVault(vaultAddress);

        // Find current pending rewards that have not been distributed yet.
        uint128 currentPendingRewards;
        if (p.rewardRate > 0) {
            currentPendingRewards = (p.endTimestamp - p.lastAccrualTimestamp) * p.rewardRate;
        }
        uint256 assetsAccountedFor = p.totalBalance + currentPendingRewards;

        // Get this contracts current position worth based off share price.
        uint256 currentBalance = (vault.balanceOf(address(this)) * vault.pricePerShare()) / 10**vault.decimals();

        //This happens when
        if (assetsAccountedFor > currentBalance) return;
        else {
            //TODO take platform fee
            uint256 yield = currentBalance - assetsAccountedFor; // yearn token balanceOf this address * the exchange rate to the underlying - totalAssets
            p.rewardRate = uint128((yield + currentPendingRewards) / REWARD_PERIOD);
            p.endTimestamp = uint64(block.timestamp) + REWARD_PERIOD;
            // lastAccrualTimestamp was already updated by _updatePositionBalance;
        }
    }

    function _withdrawFromYearn(Position storage p, uint256 _amount) internal returns (uint256 amountWithdrawn) {
        address vaultAddress = abi.decode(p.positionData, (address));
        IYearnVault vault = IYearnVault(vaultAddress);
        uint256 shares = (10**vault.decimals() * _amount) / vault.pricePerShare();
        uint256 balanceBefore = p.asset.balanceOf(address(this));
        vault.withdraw(shares);
        amountWithdrawn = p.asset.balanceOf(address(this)) - balanceBefore;
    }

    //============================================ Convex Integration Functions ===========================================
    IBooster private booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    /**
     * @notice There is no share conversion with Convex, so what you put in is what you can take out.
     */
    function _depositToConvex(Position storage p, uint256 _amount) internal returns (uint256) {
        uint256 pid = abi.decode(p.positionData, (uint256));
        p.asset.safeApprove(address(booster), _amount);
        booster.deposit(pid, _amount, true);
        return _amount;
    }

    //TODO YEARN does ZERO checks for value in vs value out when handling rewards.
    function _harvestConvexPosition(Position storage p) internal {
        IBaseRewardPool rewardPool;
        {
            (, address rewardPoolAddress) = abi.decode(p.positionData, (uint256, address));
            rewardPool = IBaseRewardPool(rewardPoolAddress);
        }

        // Calculate starting reward balances to find actual harvested amount.
        // Gas intensive but safer considering this address could have positions that use the reward tokens.
        uint256 rewardTokenCount = 2 + rewardPool.extraRewardsLength();
        ERC20[] memory rewardTokens = new ERC20[](rewardTokenCount);
        rewardTokens[0] = CRV;
        rewardTokens[1] = CVX;
        uint256[] memory rewardBalances = new uint256[](rewardTokenCount);
        rewardBalances[0] = CRV.balanceOf(address(this));
        rewardBalances[1] = CVX.balanceOf(address(this));
        for (uint256 i = 2; i < rewardTokenCount; i++) {
            rewardTokens[i] = ERC20(rewardPool.extraRewards(i - 2));
            rewardBalances[i] = rewardTokens[i].balanceOf(address(this));
        }
        rewardPool.getReward(address(this), true);

        for (uint256 i = 0; i < rewardTokenCount; i++) {
            rewardBalances[i] = ERC20(rewardTokens[i]).balanceOf(address(this)) - rewardBalances[i];
        }
        // harvests rewards and immediately adds them back to the convex pool.
        uint256 depositData = p.depositData;
        ERC20 assetToDeposit = ERC20(address(uint160(depositData)));
        uint256 depositBalance = assetToDeposit.balanceOf(address(this));
        //TODO need to take platform fee.
        uint256 fromAndTos = p.fromAndTos;
        for (uint8 i = 0; i < 16; i = i + 2) {
            address pool;
            if ((pool = p.swapPools[i / 2]) == address(0)) break;
            if (rewardBalances[i / 2] < 0.01e18) continue; // Don't swap dust.
            uint8 from = uint8(fromAndTos >> (8 * i));
            uint8 to = uint8(fromAndTos >> (8 * (i + 1)));
            _sellOnCurve(pool, from, to, rewardBalances[i / 2], rewardTokens[i / 2]);
        }

        depositBalance = assetToDeposit.balanceOf(address(this)) - depositBalance;

        // Add liquidity to pool.
        if (depositBalance > 0) {
            uint256 yield = p.asset.balanceOf(address(this));
            (, , address curvePool) = abi.decode(p.positionData, (uint256, address, address));

            _addLiquidityToCurve(
                assetToDeposit,
                uint8(depositData >> 160),
                uint8(depositData >> 168),
                (uint8(depositData >> 176) == 1),
                depositBalance,
                curvePool
            );

            yield = p.asset.balanceOf(address(this)) - yield;

            _depositToConvex(p, yield);

            // Use price router to get value in vs value out and make sure it is within slippage tolerance.

            uint128 currentPendingRewards;
            if (p.rewardRate > 0) {
                currentPendingRewards = (p.endTimestamp - p.lastAccrualTimestamp) * p.rewardRate;
            }
            // The amount of LP tokens received.
            p.rewardRate = uint128((yield + currentPendingRewards) / REWARD_PERIOD);
            p.endTimestamp = uint64(block.timestamp) + REWARD_PERIOD;
        }
    }

    function _withdrawFromConvex(Position storage p, uint256 _amount) internal returns (uint256 amountWithdrawn) {
        (, address reward) = abi.decode(p.positionData, (uint256, address));
        IBaseRewardPool rewardPool = IBaseRewardPool(reward);
        rewardPool.withdrawAndUnwrap(_amount, false);
        amountWithdrawn = _amount;
    }

    // CToken `getCashPrior` should call this.
    function balanceOf(address _operator) public view returns (uint256) {
        require(operators[_operator].isOperator, "Address is not an operator.");
        return _balanceOf(_operator);
    }

    function _balanceOf(address _operator) internal view returns (uint256 balance) {
        uint256 _positions = operators[_operator].openPositions;
        // Loop through all positions and query balance.
        for (uint256 i = 0; i < 8; i++) {
            uint32 positionId = uint32(_positions >> (32 * i)); //might need to do unchecked
            if (positionId == 0) break;
            else balance += _calcOperatorBalance(_operator, positionId);
        }
        // Add holding position balance.
        balance += operators[_operator].holdingBalance;
        // Calculates balance + pending balance, does not facotr in pending rewards to be harvested.
    }

    function _calcOperatorBalance(address _operator, uint32 _positionId) internal view returns (uint256) {
        uint256 operatorShares = operatorPositionShares[_operator][_positionId];
        Position memory p = positions[_positionId];
        if (p.totalSupply == 0) return 0;
        uint64 currentTime = uint64(block.timestamp);
        uint256 pendingBalance = currentTime < p.endTimestamp
            ? (p.rewardRate * (currentTime - p.lastAccrualTimestamp))
            : (p.rewardRate * (p.endTimestamp - p.lastAccrualTimestamp));
        uint256 assetsPerShare = (1e18 * (p.totalBalance + pendingBalance)) / p.totalSupply;
        return (operatorShares * assetsPerShare) / 1e18;
    }

    // returns the underlying asset
    // function underlying(uint256 pid) public view returns (address) {
    //     return positions[pid].underlying;
    // }

    //============================================ Curve Integration Functions ===========================================
    function _sellOnCurve(
        address pool,
        uint128 from,
        uint128 to,
        uint256 amount,
        ERC20 sellAsset
    ) internal {
        sellAsset.approve(pool, amount);
        ICurveFi(pool).exchange(from, to, amount, 0, false);
    }

    function _addLiquidityToCurve(
        ERC20 assetToDeposit,
        uint8 coinsLength,
        uint8 targetIndex,
        bool useUnderlying,
        uint256 amount,
        address pool
    ) internal {
        assetToDeposit.approve(pool, amount);
        uint256[4] memory amounts;
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
        } else revert("Unsupported deposit");
    }
}
