// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { CErc20Storage } from "@compound/CTokenInterfaces.sol";
import { CToken } from "@compound/CToken.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Uint32Array } from "src/libraries/Uint32Array.sol";
import { IYearnVault } from "src/interfaces/Yearn/IYearnVault.sol";

// Curve imports
import { ICurvePool } from "src/interfaces/ICurvePool.sol";
import { ICurveToken } from "src/interfaces/ICurveToken.sol";

// Aave imports
import { IAaveToken } from "src/interfaces/IAaveToken.sol";

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
        //TODO ^^^^^^
        uint128 rewardRate; // Vested rewards distributed per second.
        uint64 lastAccrualTimestamp; // Last timestamp when vested tokens were claimed.
        uint64 endTimestamp; // The end time stamp for when all current rewards are vested.
        Platform platform;
        bytes positionData; // Stores arbritrary data for the position.
        address asset; // The underlying asset in a position.
    }
    mapping(address => mapping(uint32 => uint256)) public operatorPositionShares;
    uint32[] public activePositions; // Array of all active positions.
    mapping(uint32 => Position) public positions;
    ///@dev 0 position id is reserved for empty

    uint32 public constant REWARD_PERIOD = 7 days;

    struct Operator {
        address owner; // What address can make changes to how this operator invests into positions.
        bool isOperator; // Bool indicating whether this operator has been set up.
        address underlying;
        uint256 holdingBalance;
        uint256 openPositions; // Positions operator currently has funds in.
        uint256 positionRatios; // Desired ratio for funds in positions. Could maybe allow a position to be just this contract, where it allows for cheaper use deposit/withdraws, and keepers perform batched TXs.
        //TODO if positionRatios do not add up to 100, then remainder is designated for holding position.
    }

    mapping(address => Operator) public operators;
    uint32 public positionCount;

    function addPosition(
        address _asset,
        Platform _platform,
        bytes memory _positionData
    ) external onlyOwner {
        uint32 positionId = positionCount + 1;
        if (activePositions.contains(positionId)) revert("Position already present");
        activePositions.push(positionId);
        positions[positionId] = Position({
            totalSupply: 0,
            totalBalance: 0,
            rewardRate: 0,
            lastAccrualTimestamp: uint64(block.timestamp),
            endTimestamp: type(uint64).max,
            platform: _platform,
            positionData: _positionData,
            asset: _asset
        });
        positionCount++;
    }

    ///@dev operators can only be in positions with the SAME ASSET.
    function addOperator(
        address _operator,
        address _owner,
        address _underlying,
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
            underlying: _underlying,
            holdingBalance: 0,
            openPositions: _positions,
            positionRatios: _positionRatios
        });
    }

    /**
     * Will add to positions rewardQueue based off either
     * if Accrual Type == OVERTIME
     *      Compare stored balance of this contract (in assets) to current balance, the difference is yield earned, send platform fees to a yield manager?
     * else if Accrual Type == HARVEST
     *      Harvset pending rewards convert them to underlying, the amount of underlying is the yield earned, send fees to a yield manager?
     * This function will update the positions `rewardRate` `lastAccrualTimestamp` `endTimestamp`
     * This function will send platform fees to the rewards contract
     * This function will set aside a percent of yield to be saved for this contract to be converted into LINK to fund upkeeps.
     */
    function _checkPointRewards(address position) internal {
        // I think this function would update the lastAccrualTimestamp, then basically make the current balance into the balance + pending
    }

    /**
     * Takes underlying token and deposits it into the underlying protocol
     * returns the amount of shares
     */
    function deposit(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        require(operators[operator].isOperator, "Only Operators can deposit.");
        //TODO could coordinate with Zeus to have this transfer from user themselves, then users approve this contract. But this could get sketchy if an operator went rogue;
        ERC20(operators[operator].underlying).safeTransferFrom(operator, address(this), amount);

        // Deposit assets into operator holding position.
        operators[operator].holdingBalance += amount;

        return amount;
    }

    function withdraw(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        require(operators[operator].isOperator, "Only Operators can withdraw.");
        //TODO could coordinate with Zeus to have this transfer from user themselves, then users approve this contract. But this could get sketchy if an operator went rogue;

        // Withdraw assets from the holding positions.
        //TODO this should withdraw from positions in order.
        console.log("Balance", ERC20(operators[operator].underlying).balanceOf(address(this)));
        operators[operator].holdingBalance -= amount;

        ERC20(operators[operator].underlying).transfer(operator, 100e18 + 0);

        return amount;
    }

    /**
     * Updates a positions totalBalance, lastAccrualTimestamp, and determines the new Reward Rate, and sets new end timestamp.
     */
    function harvestPosition(uint32 _positionId) public {
        Position storage p = positions[_positionId];
        _updatePositionBalance(p); // Updates totalBalance and lastAccrualTimestamp
        if (p.platform == Platform.YEARN) {
            _harvestYearnPosition(p);
        }
    }

    //TODO I think the deposit and withdraw functions need to confirm the amount was deposited and the amount was withdrawn!
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
                _depositToYearn(p, _amount);
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

            if (p.platform == Platform.YEARN) {
                _withdrawFromYearn(p, _amount);
            }

            // Now that pending rewards have been accounted for shares are more expensive.
            // Find shares owed to operator.
            uint256 assetsPerShare = (1e18 * p.totalBalance) / p.totalSupply;
            uint256 operatorShares = ((1e18 * _amount) / assetsPerShare);
            operatorPositionShares[_operator][_positionId] -= operatorShares;
            p.totalSupply -= operatorShares;
            p.totalBalance -= _amount;
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

    function _depositToYearn(Position storage p, uint256 _amount) internal {
        address vaultAddress = abi.decode(p.positionData, (address));
        IYearnVault vault = IYearnVault(vaultAddress);
        ERC20(p.asset).safeApprove(address(vault), _amount);
        vault.deposit(_amount);
    }

    function _harvestYearnPosition(Position storage p) internal {
        // Since yearn tokens accrue rewards in real time, this function is really just returning the difference in new yield to yield already accounted for.
        // totalAssets = current stored balance + pending + realized reward balance.
        address vaultAddress = abi.decode(p.positionData, (address));
        IYearnVault vault = IYearnVault(vaultAddress);
        uint128 currentPendingRewards;
        if (p.rewardRate > 0) {
            currentPendingRewards = (p.endTimestamp - p.lastAccrualTimestamp) * p.rewardRate;
        }
        uint256 assetsAccountedFor = p.totalBalance + currentPendingRewards;
        //TODO might need to use the vault decimals.
        uint128 currentBalance = uint128((vault.balanceOf(address(this)) * vault.pricePerShare()) / 1e18);
        if (assetsAccountedFor > currentBalance) return;
        else {
            uint256 yield = currentBalance - assetsAccountedFor; // yearn token balanceOf this address * the exchange rate to the underlying - totalAssets
            p.rewardRate = uint128((yield + currentPendingRewards) / REWARD_PERIOD);
            p.endTimestamp = uint64(block.timestamp) + REWARD_PERIOD;
            // lastAccrualTimestamp was already updated by _updatePositionBalance;
            console.log("Information");
            console.log(p.rewardRate);
            console.log(p.lastAccrualTimestamp);
            console.log(p.endTimestamp);
        }
    }

    function _withdrawFromYearn(Position storage p, uint256 _amount) internal {
        address vaultAddress = abi.decode(p.positionData, (address));
        IYearnVault vault = IYearnVault(vaultAddress);
        uint256 shares = (10**vault.decimals() * _amount) / vault.pricePerShare();
        vault.withdraw(shares);
    }

    //TODO I think this needs to calculate earnings before
    // function _depositToConvex(uint128 _amount) internal returns (uint256) {
    //     //This only has the logic to put assets into Convex.
    // }

    // function _harvestConvexPosition(Position memory p) internal {}

    // function _withdrawFromConvex(uint128 _amount) internal returns (uint256) {
    //     // this only has the logic to remove assets from convex.
    // }

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
}
