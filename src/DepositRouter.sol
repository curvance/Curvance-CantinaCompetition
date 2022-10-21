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
        uint128 totalSupply; // total amount of outstanding shares, used with `balance` to determine a share price.
        uint128 totalBalance; // total balance of all operators in position.
        uint128 rewardRate; // Vested rewards distributed per second.
        uint64 lastAccrualTimestamp; // Last timestamp when vested tokens were claimed.
        uint64 endTimestamp; // The end time stamp for when all current rewards are vested.
        Platform platform;
        AccrualType accrueType; // Tells the keeper how to harvest this position
        address asset; // The underlying asset in a position.
    }
    mapping(address => mapping(uint32 => uint128)) public operatorPositionShares;
    uint32[] public activePositions; // Array of all active positions.
    mapping(uint32 => Position) public positions;
    ///@dev 0 position id is reserved for empty

    struct Operator {
        address owner; // What address can make changes to how this operator invests into positions.
        bool isOperator; // Bool indicating whether this operator has been set up.
        uint128 sharesOutstanding;
        address underlying;
        uint256 openPositions; // Positions operator currently has funds in.
        uint256 positionRatios; // Desired ratio for funds in positions. Could maybe allow a position to be just this contract, where it allows for cheaper use deposit/withdraws, and keepers perform batched TXs.
    }

    mapping(address => Operator) public operators;

    function addPosition(
        address _asset,
        Platform _platform,
        AccrualType _accrueType,
        uint32 _positionId
    ) external onlyOwner {
        if (activePositions.contains(_positionId)) revert("Position already present");
        activePositions.push(_positionId);
        positions[_positionId] = Position({
            totalSupply: 0,
            totalBalance: 0,
            rewardRate: 0,
            lastAccrualTimestamp: uint64(block.timestamp),
            endTimestamp: type(uint64).max,
            platform: _platform,
            accrueType: _accrueType,
            asset: _asset
        });
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
        ///@dev position id 1 is the holding postion, where users funds are always deposited.
        require(_positions > 0, "0 is an invalid positions");
        operators[_operator] = Operator({
            owner: _owner,
            isOperator: true,
            sharesOutstanding: 0,
            underlying: _underlying,
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
    function depositTo(uint256 amount) public returns (uint256 userShares) {
        address operator = msg.sender;
        require(operators[operator].isOperator, "Only Operators can deposit.");
        //TODO could coordinate with Zeus to have this transfer from user themselves, then users approve this contract. But this could get sketchy if an operator went rogue;
        ERC20(operators[operator].underlying).safeTransferFrom(operator, address(this), amount);
        // Find shares owed to user.
        userShares = (amount * _balanceOf(operator)) / operators[operator].sharesOutstanding;

        // Deposit assets into operator holding position.
        uint32 holdingPosition = uint32(operators[operator].openPositions); //TODO need unchecked?
        _depositToPosition(operator, holdingPosition);
    }

    /**
     * Calculates vested reward tokens without writing to state.
     * I think technically this function could be used in normal deposit functions? Like do we really need to update the balance, and the lastAccrualTimestamp every time someone deposits or withdraws?
     * Well we do need to update the balance cuz funds are moving in and out
     */
    function _rewardsDue(address position) internal view returns (uint256 rewards) {}

    function _depositToPosition(address _operator, uint32 _positionId) internal returns (uint128 shares) {
        Position memory p = positions[_positionId];

        if (p.platform == Platform.CONVEX) _depositToConvex();
        else if (p.platform == Platform.YEARN) _depositToYearn();

        // Give operator credit
        operatorPositionShares[_operator][_positionId] += shares;
    }

    function _depositToConvex() internal {
        //I think these need to write to the pool position?
    }

    function _withdrawFromConvex() internal {}

    function _depositToYearn() internal {}

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
        // Calculates balance + pending balance, does not facotr in pending rewards to be harvested.
    }

    function _calcOperatorBalance(address _operator, uint32 _positionId) internal view returns (uint256) {
        uint128 operatorShares = operatorPositionShares[_operator][_positionId];
        Position memory p = positions[_positionId];
        uint64 currentTime = uint64(block.timestamp);
        uint256 pendingBalance = currentTime > p.endTimestamp
            ? (p.rewardRate * (p.endTimestamp - p.lastAccrualTimestamp)) / 1e18
            : (p.rewardRate * (currentTime - p.lastAccrualTimestamp)) / 1e18;
        return ((p.totalBalance + pendingBalance) * operatorShares) / p.totalSupply;
    }

    // returns the underlying asset
    // function underlying(uint256 pid) public view returns (address) {
    //     return positions[pid].underlying;
    // }
}
