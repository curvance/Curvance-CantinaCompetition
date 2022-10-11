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
import { DoubleEndedQueue } from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

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
    using EnumerableSet for EnumerableSet.AddressSet;
    enum Platform {
        CONVEX, // you are not given an asset
        YEARN // you are given an asset
    }
    enum AccrualType {
        OVERTIME, // Share price increase
        HARVEST, // Harvesting rewards
        REBASE // Rebasing token like aTokens, would probs need to be treated like an overtime, and somehow internally store the share price?
    }
    struct Position {
        Platform platform;
        AccrualType accrueType;
        uint256 totalSupply;
        uint256 balance;
        uint256 lastAccrualTimestamp; // All values in the Queue will share the same timestamp.
        DoubleEndedQueue.Bytes32Deque rewardQueue;
        // Position Queue is made up of Bytes32 values where first 128 bits are the tokens per second, and the second half is the end timestamp.
    }

    /**
     * Keepers scan through activePostions array, and check if pending rewards(or share price difference) is greater than some minimum
     */
    EnumerableSet.AddressSet private activePositions;

    // Maps address of an underlying to position information
    mapping(uint256 => Position) private positions;

    function addPosition(address position, Platform platform) external onlyOwner {
        if (activePositions.contains(position)) revert("Position already present");
        //^^^ above would revert if 2 positions used the same address, like a Curve 3Pool position and a Convex 3 pool position
    }

    /**
     * Will add to positions rewardQueue based off either
     * if Accrual Type == OVERTIME
     *      Compare stored balance of this contract (in assets) to current balance, the difference is yield earned, send platform fees to a yield manager?
     * else if Accrual Type == HARVEST
     *      Harvset pending rewards convert them to underlying, the amount of underlying is the yield earned, send fees to a yield manager?
     * This function will add an entry to rewardQueue
     * This function will send platform fees to the rewards contract
     * This function will set aside a percent of yield to be saved for this contract to be converted into LINK to fund upkeeps.
     */
    function _checkPointRewards(address position) internal {
        // Add new rewards to end of Queue
    }

    /**
     * Takes underlying token and deposits it into the underlying protocol
     * returns the amount of shares
     */
    function depositTo(address position, uint256 amount) public returns (uint256) {
        if (!activePositions.contains(position)) revert("Invalid position");
        //needs to check if any rewards are due, and remove old rewards so maybe _rewardsDue needs to write to state, then I make a seperate function for viewing balances?
    }

    /**
     * Calculates vested reward tokens without writing to state.
     */
    function _rewardsDue(address position) internal view returns (uint256 rewards) {}

    function balanceOf(address position) external view returns (uint256) {
        // Calculates balance + pending balance from reward queue, does not facotr in pending rewards to be harvested.
    }

    // returns the underlying asset
    // function underlying(uint256 pid) public view returns (address) {
    //     return positions[pid].underlying;
    // }
}
