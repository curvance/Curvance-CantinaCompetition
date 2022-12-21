// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, SafeTransferLib, ERC20 } from "@solmate/mixins/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { PriceRouter } from "src/PricingOperations/PriceRouter.sol";

import { Math } from "src/utils/Math.sol";
import { Uint32Array } from "src/libraries/Uint32Array.sol";

// External interfaces
import { IBooster } from "src/interfaces/Convex/IBooster.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { ICurveFi } from "src/interfaces/Curve/ICurveFi.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";

import { console } from "@forge-std/Test.sol"; //TODO remove this

/**
 * @title Curvance Deposit Router
 * @notice Provides a universal interface allowing Curvance contracts to deposit and withdraw assets from:
 *         Convex
 * @author crispymangoes
 */
//TODO add events
// TODO I think it would be best to create a position watch dog, that basically allows ANYONE to harvest positions, but when it harvests positions, then
// It is able to take a fee in ETH to self fund itself.
// I think the position watch dog address would be stored here?
contract DepositRouterV2 is Ownable {
    using Uint32Array for uint32[];
    using SafeTransferLib for ERC20;
    using Math for uint256;

    // TODO should probs make a lib that helps with managin this array.
    ERC4626[] public positions;

    function getPositions() external view returns (ERC4626[] memory) {
        return positions;
    }

    mapping(ERC4626 => bool) public isPositionUsed;

    /**
     * @notice Minimum harvetable yield in USD required for a keeper to harvest a position.
     * @dev 8 decimals
     */
    uint64 public minYieldForHarvest = 100e8;

    /**
     * @notice Maximum gas price contract is willing to pay to harveset positions.
     */
    uint64 public maxGasPriceForHarvest = 10e9;

    /**
     * @notice Fee taken on harvesting rewards.
     * @dev 18 decimals
     */
    uint64 public platformFee = 0.2e18;

    /**
     * @notice Address where fees are sent.
     */
    address public feeAccumulator;

    // TODO we either need to record share balances of msg.senders, OR restrict deposit/withdraws to only the proper market.
    mapping(address => bool) public onlyOperator;

    constructor() {}

    //============================================ onlyOwner Functions ===========================================
    /**
     * @notice Allows `owner` to add new positions to this contract.
     * @dev see `Position` struct for description of inputs.
     */
    function addPosition(ERC4626 _position) external onlyOwner {
        if (isPositionUsed[_position]) revert("Position already used");
        positions.push(_position);
    }

    //============================================ User Functions ===========================================
    /**
     * Takes underlying token and deposits it into the underlying protocol
     * returns the amount of shares
     */
    function deposit(uint256 amount, ERC4626 _position) public returns (uint256) {
        if (!isPositionUsed[_position]) revert("Position not used");
        // transfer asset in.
        _position.asset().safeTransferFrom(msg.sender, address(this), amount);

        // deposit it into ERC4626 vault.
        _position.deposit(amount, address(this));

        return amount;
    }

    function withdraw(uint256 amount, ERC4626 _position) public returns (uint256) {
        // TODO could send the assets here or direclty to caller.
        _position.withdraw(amount, msg.sender, address(this));

        return amount;
    }

    //============================================ Balance Of Functions ===========================================
    // CToken `getCashPrior` should call this.
    function balanceOf(address _user, uint32 _positionId) public view returns (uint256) {}
}
