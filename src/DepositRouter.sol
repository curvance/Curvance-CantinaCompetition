// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
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
contract DepositRouter is Ownable, KeeperCompatibleInterface {
    using Uint32Array for uint32[];
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /**
     * @notice Platforms supported by the Deposit Router.
     */
    enum Platform {
        CONVEX
    }

    /**
     * @notice Deposit Data to facilitate depositing into Curve pools.
     * @param asset the Curve pool token
     * @param coinsCount the amount of coins in the Curve pool
     * @param targetIndex the index `asset` is in the pool's `coins` array
     * @param useUnderlying bool indicating whether this contract needs to pass in
     *                      a false value for `add_liquidity`s `useUnderlying` value
     */
    struct DepositData {
        address asset;
        uint8 coinsCount;
        uint8 targetIndex;
        bool useUnderlying;
    }

    /**
     * @notice Position accounting and configuration data.
     * @dev Position harvesting can have at most 8 swaps on Curve.
     * @param totalSupply total amount of outstanding shares, used with `totalBalance` to determine a share price
     * @param totalBalance cached total balance of all operators in position
     * @param rewardRate rate rewards vest, given in [token/second] with token.decimals()
     * @param lastAccrualTimestamp last timestamp when vested tokens were claimed
     * @param endTimestamp timestamp for when all current rewards are vested
     * @param platform platform position is on
     * @param asset ERC20 asset position uses
     * @param positionData arbitrary data needed to support position deposits/withdraws
     * @param swapPools Curve pools used for harvest swaps
     * @param froms from index in Curve pools for harvest swaps
     * @param tos to index in Curve pools for harvest swaps
     * @param depositData data used to facilitate deposits into Curve pools
     */
    struct Position {
        uint256 totalSupply;
        uint256 totalBalance;
        uint128 rewardRate;
        uint64 lastAccrualTimestamp;
        uint64 endTimestamp;
        Platform platform;
        ERC20 asset;
        bytes positionData;
        address[8] swapPools;
        uint16[8] froms;
        uint16[8] tos;
        DepositData depositData;
    }

    /**
     * @notice Array of all position ids.
     */
    uint32[] public activePositions;

    function getActivePositions() external view returns (uint32[] memory) {
        return activePositions;
    }

    /**
     * @notice Maps a position id to its `Position` data
     */
    mapping(uint32 => Position) public positions;

    /**
     * @notice Current number of positions.
     * @dev Position id ZERO is Reserved to indicate the holding position.
     */
    uint32 public positionCount;

    /**
     * @notice Period newly harvested rewards are vested over.
     */
    uint32 public constant REWARD_PERIOD = 7 days;

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

    /**
     * @notice Operator configuration data.
     * @dev Opeartors can have at most 8 open positions.
     * @param owner address capable of performing owner actions regarding this operator
     * @param asset ERC20 asset operator uses
     * @param isOperator bool used to indicate a valid operator address
     * @param allowRebalancing bool used to turn operator position balancing on/off
     * @param maxGasForRebalance highest gas price operator is willing to pay for a rebalance
     * @param openPositions array of position ids operator is in
     *                      @dev Index ZERO must be ZERO for holding position.
     * @param positionRatios array of values <= 1 which determine the balance of liquidity between `openPositions`
     *                       @dev values have 8 decimals
     * @param minimumImbalanceDeltaForUpkeep minimum change in imbalance to allow a `performUpkeep` to be performed
     *                                       @dev must be < 1, with 8 decimals
     * @param minimumValueToRebalance the minimum dollar value of assets to rebalance
     *                                @dev Useful to not move dust to/from positions during rebalancing
     * @param lastRebalance timestamp of the last time this operators positions were rebalanced
     * @param minimumTimeBetweenUpkeeps minimum time in seconds between upkeeps
     */
    struct Operator {
        address owner;
        ERC20 asset;
        bool isOperator;
        bool allowRebalancing;
        uint64 maxGasForRebalance;
        uint32[8] openPositions;
        uint32[8] positionRatios;
        uint64 minimumImbalanceDeltaForUpkeep;
        uint64 minimumValueToRebalance;
        uint64 lastRebalance;
        uint64 minimumTimeBetweenUpkeeps;
    }

    /**
     * @notice Map an address to its operator data.
     */
    mapping(address => Operator) public operators;

    /**
     * @notice Keep track of an operators shares in each position.
     */
    mapping(address => mapping(uint32 => uint256)) public operatorPositionShares;

    /**
     * @notice Contract to get pricing information.
     */
    PriceRouter public immutable priceRouter;

    constructor(PriceRouter _priceRouter) {
        priceRouter = _priceRouter;
    }

    //============================================ onlyOwner Functions ===========================================
    /**
     * @notice Allows `owner` to add new positions to this contract.
     * @dev see `Position` struct for description of inputs.
     */
    function addPosition(
        ERC20 _asset,
        Platform _platform,
        bytes memory _positionData,
        address[8] calldata _swapPools,
        uint16[8] calldata _froms,
        uint16[8] calldata _tos,
        DepositData calldata _depositData
    ) external onlyOwner {
        uint32 positionId = positionCount + 1;
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
            froms: _froms,
            tos: _tos,
            depositData: _depositData
        });
        positionCount++;
    }

    /**
     * @notice Position array provided has errors in it.
     */
    error DepositRouter__InvalidPositionArray();

    /**
     * @notice Provided ratios do not sum to one.
     */
    error DepositRouter_RatiosDoNotSumToOne();

    function _validatePositionsAndRatios(
        uint32[8] memory _positions,
        uint32[8] memory _positionRatios,
        ERC20 _asset
    ) internal view {
        ///@dev position index 0 is the holding postion, where users funds are always deposited.
        if (_positions.length == 0) revert DepositRouter__InvalidPositionArray();
        // Loop through _positions and make sure it is valid.
        bool endPositionFound;
        uint256 totalRatio;
        for (uint32 i = 0; i < 8; i++) {
            uint32 positionId = _positions[i];
            totalRatio += _positionRatios[i];
            if (i == 0) {
                // Make sure zero index is holding position.
                if (positionId != 0) revert DepositRouter__InvalidPositionArray();
            } else if (endPositionFound) {
                // If the end position is found enforce that all subsequent positions are zero.
                // Enforce that no liquidity will be moved to remaining positions.
                if (positionId != 0 || _positionRatios[i] != 0) revert DepositRouter__InvalidPositionArray();
            } else {
                // Scan through the array until the end is found.
                if (positionId == 0) endPositionFound = true;
                else {
                    // Make sure position is valid.
                    if (positionId > positionCount) revert DepositRouter__InvalidPositionArray();
                    // Make sure operator is adding a position with the correct asset.
                    if (positions[positionId].asset != _asset) revert DepositRouter__InvalidPositionArray();
                }
            }
        }
        if (totalRatio != 1e8) revert DepositRouter_RatiosDoNotSumToOne();
    }

    /**
     * @notice Attempted to add an operator that already existed.
     * @param operator the address of the operator that exists
     */
    error DepositRouter__OperatorExists(address operator);

    /**
     * @notice Allows `owner` to add a new operator to this contract.
     * @dev see `Operator` struct for description of inputs.
     */
    function addOperator(
        address _operator,
        address _owner,
        ERC20 _asset,
        uint64 _maxGasForRebalance,
        uint32[8] memory _positions,
        uint32[8] memory _positionRatios,
        uint64 _minimumImbalanceDeltaForUpkeep,
        uint64 _minimumValueToRebalance,
        uint64 _minimumTimeBetweenUpkeeps
    ) external onlyOwner {
        if (operators[_operator].isOperator) revert DepositRouter__OperatorExists(_operator);
        _validatePositionsAndRatios(_positions, _positionRatios, _asset);
        operators[_operator] = Operator({
            owner: _owner,
            asset: _asset,
            isOperator: true,
            allowRebalancing: false,
            maxGasForRebalance: _maxGasForRebalance,
            openPositions: _positions,
            positionRatios: _positionRatios,
            minimumImbalanceDeltaForUpkeep: _minimumImbalanceDeltaForUpkeep,
            minimumValueToRebalance: _minimumValueToRebalance,
            lastRebalance: uint64(block.timestamp),
            minimumTimeBetweenUpkeeps: _minimumTimeBetweenUpkeeps
        });
    }

    /**
     * @notice Allows owner to change the minimum dollar value needed to harvest a position.
     * @param newYield the new minimum(in USD) needed for a keeper to harvest yield.
     * @dev 8 decimals
     */
    function adjustMinYieldForHarvest(uint64 newYield) external onlyOwner {
        minYieldForHarvest = newYield;
    }

    /**
     * @notice Allows owner to change the maximum gas keepers are willing to pay for harvest upkeeps.
     * @param newPrice the new max gas price
     * @dev Checked against Chainlinks ETH Fast Gas Feed.
     */
    function adjustMaxGasPriceForHarvest(uint64 newPrice) external onlyOwner {
        maxGasPriceForHarvest = newPrice;
    }

    /**
     * @notice Allows owner to change the fee accumulator address.
     */
    function setFeeAccumulator(address accumulator) external onlyOwner {
        feeAccumulator = accumulator;
    }

    //========================================= Operator Owner Functions ========================================

    /**
     * @notice Attempted action used an operator that does not exist.
     * @param operator the address of the operator that does not exist.
     */
    error DepositRouter__OperatorDoesNotExist(address operator);

    /**
     * @notice Attempted to perform an operator owner action when caller is not operator owner.
     * @param operator the operator address
     * @param caller the address of the caller
     */
    error DepositRouter__CallerDoesNotOperatorOwner(address operator, address caller);

    /**
     * @notice Position management lead to a change in operators balance.
     */
    error DepositRouter__UncleanPositions();

    function changePositions(
        address _operator,
        uint32[8] calldata _positions,
        uint32[8] calldata _positionRatios
    ) external {
        if (!operators[_operator].isOperator) revert DepositRouter__OperatorDoesNotExist(_operator);
        if (operators[_operator].owner != msg.sender)
            revert DepositRouter__CallerDoesNotOperatorOwner(_operator, msg.sender);

        _validatePositionsAndRatios(_positions, _positionRatios, operators[_operator].asset);
        uint256 operatorBalanceBefore = _balanceOf(_operator);
        operators[_operator].openPositions = _positions;
        uint256 operatorBalanceAfter = _balanceOf(_operator);
        if (operatorBalanceAfter != operatorBalanceBefore) revert DepositRouter__UncleanPositions();
    }

    /**
     * @notice Allows operator owner to make rebalances without enforcing rebalance checks.
     */
    function operatorOwnerRebalance(
        address _operator,
        uint32[8] calldata from,
        uint32[8] calldata to,
        uint256[8] calldata amount
    ) external {
        if (!operators[_operator].isOperator) revert DepositRouter__OperatorDoesNotExist(_operator);
        if (operators[_operator].owner != msg.sender)
            revert DepositRouter__CallerDoesNotOperatorOwner(_operator, msg.sender);
        uint256 operatorBalanceBefore = _balanceOf(_operator);
        _performRebalances(_operator, from, to, amount);
        uint256 operatorBalanceAfter = _balanceOf(_operator);
        // Check that operator did not move funds to an untracked position.
        if (operatorBalanceAfter != operatorBalanceBefore) revert DepositRouter__UncleanPositions();
    }

    function allowRebalancing(address _operator, bool _state) external {
        if (!operators[_operator].isOperator) revert DepositRouter__OperatorDoesNotExist(_operator);
        if (operators[_operator].owner != msg.sender)
            revert DepositRouter__CallerDoesNotOperatorOwner(_operator, msg.sender);
        operators[_operator].allowRebalancing = _state;
    }

    //============================================ Operator Functions ===========================================
    /**
     * Takes underlying token and deposits it into the underlying protocol
     * returns the amount of shares
     */
    function deposit(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        if (!operators[operator].isOperator) revert DepositRouter__OperatorDoesNotExist(operator);
        operators[operator].asset.safeTransferFrom(operator, address(this), amount);

        // Deposit assets into operator holding position.
        operatorPositionShares[operator][0] += amount;

        return amount;
    }

    function withdraw(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        if (!operators[operator].isOperator) revert DepositRouter__OperatorDoesNotExist(operator);
        // Withdraw assets from positions in order.
        uint256 freeCash = operatorPositionShares[operator][0];
        for (uint32 i = 1; i < 8; i++) {
            uint32 position = operators[operator].openPositions[i];
            if (position == 0) break;
            if (freeCash < amount) {
                uint256 positionBalance = _calcOperatorBalance(operator, position);
                // Need to withdraw from a position to the holding position.
                uint256 amountToWithdraw = (freeCash + positionBalance) < amount ? positionBalance : amount - freeCash;
                _withdrawFromPosition(operator, position, amountToWithdraw);
                freeCash += amountToWithdraw;
            } else {
                break;
            }
        }
        operatorPositionShares[operator][0] -= amount;
        operators[operator].asset.safeTransfer(operator, amount);

        return amount;
    }

    //============================================ Position Management Functions ===========================================

    /**
     * @notice Attempted rebalance is invalid.
     */
    error DepositRouter__InvalidRebalance();

    /**
     * @notice Operators will use a Chainlink Keeper to rebalance their positions
     * @notice The protocol(Curvance) will provide a keeper to harvest positions.
     */
    function _performRebalances(
        address _operator,
        uint32[8] memory _from,
        uint32[8] memory _to,
        uint256[8] memory _amount
    ) internal {
        for (uint8 i; i < 8; i++) {
            // Assume rebalances are front loaded, so finding a zero amount breaks out of the for loop.
            if (_amount[i] == 0) break;
            if (_from[i] == _to[i]) revert DepositRouter__InvalidRebalance();
            _withdrawFromPosition(_operator, _from[i], _amount[i]);
            _depositToPosition(_operator, _to[i], _amount[i]);
        }
    }

    function _depositToPosition(
        address _operator,
        uint32 _positionId,
        uint256 _amount
    ) internal {
        // Taking funds from the holding position and depositing to _positionId
        operatorPositionShares[_operator][0] -= _amount;

        Position storage p = positions[_positionId];
        _updatePositionBalance(p); // This will take pending rewards and add it to p.totalBalance
        // So it needs to update totalBalance, and lastAccrualTimestamp

        if (p.platform == Platform.CONVEX) {
            // Set _amount to actual backing of tokens in protocol.
            _amount = _depositToConvex(p, _amount);
        }

        // Now that pending rewards have been accounted for shares are more expensive.
        // Find shares owed to operator.
        uint256 operatorShares = _convertToShares(p, _amount);

        operatorPositionShares[_operator][_positionId] += operatorShares;
        p.totalSupply += operatorShares;
        p.totalBalance += _amount;
    }

    function _convertToShares(Position storage p, uint256 assets) internal view returns (uint256 shares) {
        uint256 totalShares = p.totalSupply;

        shares = totalShares == 0
            ? assets.changeDecimals(p.asset.decimals(), 18)
            : assets.mulDivDown(totalShares, p.totalBalance);
    }

    /**
     * @notice Attempted withdraw was unable to withdraw enough assets to cover liability.
     */
    error DepositRouter__IncompleteWithdraw();

    function _withdrawFromPosition(
        address _operator,
        uint32 _positionId,
        uint256 _amount
    ) internal {
        // Position zero is holding position so assets are already free.
        if (_positionId == 0) return;
        Position storage p = positions[_positionId];

        _updatePositionBalance(p); // This will take pending rewards and add it to p.totalBalance
        // So it needs to update totalBalance, and lastAccrualTimestamp
        uint256 actualWithdraw;

        if (p.platform == Platform.CONVEX) {
            actualWithdraw = _withdrawFromConvex(p, _amount);
        }
        if (actualWithdraw != _amount) revert DepositRouter__IncompleteWithdraw();

        // Now that pending rewards have been accounted for shares are more expensive.
        // Find shares owed by operator.
        uint256 assetsPerShare = p.totalBalance.mulDivDown(1e18, p.totalSupply);
        // Round up to favor protocol.
        // uint256 operatorShares = _amount.mulDivUp(1e18, assetsPerShare);
        uint256 operatorShares = _previewWithdraw(p, _amount);
        operatorPositionShares[_operator][_positionId] -= operatorShares;
        p.totalSupply -= operatorShares;
        p.totalBalance -= _amount;

        // Credit operators holding position balance.
        operatorPositionShares[_operator][0] += _amount;
    }

    function _previewWithdraw(Position storage p, uint256 assets) internal view returns (uint256 shares) {
        uint256 totalShares = p.totalSupply;

        shares = totalShares == 0
            ? assets.changeDecimals(p.asset.decimals(), 18)
            : assets.mulDivUp(totalShares, p.totalBalance);
    }

    /**
     * @notice Claims vested rewards.
     */
    function _updatePositionBalance(Position storage p) internal {
        uint128 pendingRewards;
        uint64 time = uint64(block.timestamp);
        if (p.lastAccrualTimestamp < p.endTimestamp) {
            // There are pending rewards.
            if (time > p.endTimestamp) {
                pendingRewards = (p.endTimestamp - p.lastAccrualTimestamp) * p.rewardRate;
                // All rewards have been vested and claimed.
                p.rewardRate = 0;
            } else {
                pendingRewards = (time - p.lastAccrualTimestamp) * p.rewardRate;
            }
            p.lastAccrualTimestamp = time;
            p.totalBalance += pendingRewards;
        }
    }

    /**
     * Updates a positions totalBalance, lastAccrualTimestamp, and determines the new Reward Rate, and sets new end timestamp.
     */
    function _harvestPosition(uint32 _positionId) internal returns (uint256 yield) {
        Position storage p = positions[_positionId];
        _updatePositionBalance(p); // Updates totalBalance and lastAccrualTimestamp
        if (p.platform == Platform.CONVEX) {
            yield = _harvestConvexPosition(p);
        }
    }

    //============================================ Chainlink Automation Functions ===========================================
    address public constant ETH_FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    //TODO minimum value check on upkeep could screw with the minmum delta change enforcement
    //TODO keepers simulate this function call. Need to add keeper base modifier that does not allow this function to be executed.
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData) {
        address target = abi.decode(checkData, (address));
        if (target == address(this) || target == address(0)) {
            // Check that gas is low enough to harvest.
            uint256 currentGasPrice = uint256(IChainlinkAggregator(ETH_FAST_GAS_FEED).latestAnswer());
            if (currentGasPrice > maxGasPriceForHarvest) return (false, abi.encode(0));

            // Run harvest upkeep
            (, uint256 start, uint256 end) = abi.decode(checkData, (address, uint256, uint256));
            uint256 maxYield;
            uint32 targetId = type(uint32).max;
            for (uint256 i = start; i < end; i++) {
                uint32 position = activePositions[i];
                uint256 yield = _harvestPosition(position);
                if (yield > maxYield) {
                    maxYield = yield;
                    targetId = position;
                }
            }
            if (targetId != type(uint32).max) {
                // Check that the yield is worth it.
                uint256 yieldValue = maxYield.mulDivDown(priceRouter.getPriceInUSD(positions[targetId].asset), 1e8);
                if (yieldValue > minYieldForHarvest) {
                    performData = abi.encode(target, targetId);
                    upkeepNeeded = true;
                }
            }
        } else {
            // Run operator position management upkeep.
            Operator memory operator = operators[target];
            if (!operator.isOperator) revert DepositRouter__OperatorDoesNotExist(target);
            // Make sure enough time has passed.
            if (block.timestamp < (operator.lastRebalance + operator.minimumTimeBetweenUpkeeps))
                return (false, abi.encode(0));

            // Make sure operator allows rebalancing.
            if (!operator.allowRebalancing) return (false, abi.encode(0));

            // Make sure gas price is below the operators set max.
            uint256 currentGasPrice = uint256(IChainlinkAggregator(ETH_FAST_GAS_FEED).latestAnswer());
            if (currentGasPrice > operator.maxGasForRebalance) return (false, abi.encode(0));

            uint256 imbalance = _findOperatorPositionImbalance(target);

            // Make sure Delta is enough to warrant an upkeep.
            if (imbalance < operator.minimumImbalanceDeltaForUpkeep) return (false, abi.encode(0));

            int256[8] memory positionWants = _findOptimalLiquidityImbalance(target);

            (uint32[8] memory from, uint32[8] memory to, uint256[8] memory amount) = _findOptimalLiquidityMovement(
                target,
                positionWants
            );
            upkeepNeeded = true;
            performData = abi.encode(target, from, to, amount);
        }
    }

    /**
     * @notice Attempted to rebalance positions of an operator that has turned off rebalancing.
     * @param operator the address of the operator
     */
    error DepositRouter__OperatorDoesNotAllowRebalancing(address operator);

    /**
     * @notice Attempted to rebalance an operator too soon.
     * @param timeToNextRebalance time in seconds until it is possible to rebalance
     */
    error DepositRouter__OperatorRebalanceRateLimit(uint64 timeToNextRebalance);

    /**
     * @notice Resulting rebalance was not significant enough.
     */
    error DepositRouter__ImbalanceDeltaTooSmall();

    //TODO this function can be made so it is only callable by keepers
    function performUpkeep(bytes calldata performData) external {
        address target = abi.decode(performData, (address));
        if (target == address(this) || target == address(0)) {
            // Run harvest upkeep
            (, uint32 id) = abi.decode(performData, (address, uint32));
            _harvestPosition(id);
        } else {
            Operator memory operator = operators[target];
            if (!operator.isOperator) revert DepositRouter__OperatorDoesNotExist(target);
            if (!operator.allowRebalancing) revert DepositRouter__OperatorDoesNotAllowRebalancing(target);
            uint64 earliestRebalance = operator.lastRebalance + operator.minimumTimeBetweenUpkeeps;
            if (block.timestamp < earliestRebalance)
                revert DepositRouter__OperatorRebalanceRateLimit(earliestRebalance - uint64(block.timestamp));
            (, uint32[8] memory from, uint32[8] memory to, uint256[8] memory amount) = abi.decode(
                performData,
                (address, uint32[8], uint32[8], uint256[8])
            );
            uint256 imbalanceBefore = _findOperatorPositionImbalance(target);
            _performRebalances(target, from, to, amount);
            uint256 imbalanceAfter = _findOperatorPositionImbalance(target);
            // Underflow is desired, if imbalance increases, this TX should revert from underflow.
            if (imbalanceBefore - imbalanceAfter < operator.minimumImbalanceDeltaForUpkeep)
                revert DepositRouter__ImbalanceDeltaTooSmall();
        }
    }

    /**
     * @notice Determines how "imbalanced" an operators positions are, using the operators position ratios and balances
     */
    uint8 private constant DECIMALS = 8;

    // This check is performed in checkupkeep to see if perform upkeep should be called.
    // Also performed before and after performUpkeep to make sure actions performed by keeper were valid.
    function _findOperatorPositionImbalance(address _operator) internal view returns (uint256) {
        Operator memory o = operators[_operator];
        uint32[8] memory _positions = o.openPositions;
        // Loop through all positions and query balance.
        uint256 operatorBalance;
        uint256[8] memory operatorPositionBalances;
        uint8 positionLength;
        for (uint256 i = 0; i < 8; i++) {
            uint32 positionId = _positions[i];
            // Check if we are at the end of the position array, by finding the first zero position not in index 0.
            if (positionId == 0 && i != 0) break;
            positionLength++;
            operatorPositionBalances[i] = _calcOperatorBalance(_operator, positionId);
            operatorBalance += operatorPositionBalances[i];
        }

        // Array of balances indicating how much of the underlying asset each position wants to get(+), or to get rid of(-)
        uint256 positionImbalance;
        uint32[8] memory _positionRatios = o.positionRatios;
        for (uint256 i = 0; i < positionLength; i++) {
            uint256 positionRatio = _positionRatios[i];
            // Want = target - actual.
            uint256 actual = operatorPositionBalances[i].mulDivDown(10**DECIMALS, operatorBalance);
            if (actual > positionRatio) positionImbalance += actual - positionRatio;
        }

        return positionImbalance;
    }

    // This is only used in perform upkeep.
    /**
     * @notice determines what positions want liquidity and which ones need to get rid of liquidity
     */
    function _findOptimalLiquidityImbalance(address _operator) internal view returns (int256[8] memory) {
        Operator memory o = operators[_operator];
        uint32[8] memory _positions = o.openPositions;
        // Loop through all positions and query balance.
        uint256 operatorBalance;
        uint256[8] memory operatorPositionBalances;
        uint8 positionLength;
        for (uint256 i = 0; i < 8; i++) {
            uint32 positionId = _positions[i];
            if (positionId == 0 && i != 0) break;
            positionLength++;
            operatorPositionBalances[i] = _calcOperatorBalance(_operator, positionId);
            operatorBalance += operatorPositionBalances[i];
        }

        // Array of balances indicating how much of the underlying asset each position wants to get(+), or to get rid of(-)
        int256[8] memory positionWants;
        uint32[8] memory _positionRatios = o.positionRatios;
        for (uint256 i = 0; i < positionLength; i++) {
            uint256 positionRatio = _positionRatios[i]; //might need to do unchecked
            // Want = target - actual.
            positionWants[i] =
                int256(positionRatio.mulDivDown(operatorBalance, 10**DECIMALS)) -
                int256(operatorPositionBalances[i]);
        }

        return positionWants;
    }

    /**
     * @notice given an array of liquidity imbalances, determine the optimal rebalance calls
     * @dev will only perform 8 rebalances in a single performUpkeep
     */
    function _findOptimalLiquidityMovement(address _operator, int256[8] memory liquidityImbalance)
        internal
        view
        returns (
            uint32[8] memory from,
            uint32[8] memory to,
            uint256[8] memory amount
        )
    {
        // Max of 8 rebalance calls in an operation
        Operator memory o = operators[_operator];
        uint256 minimumAmountToRebalance = uint256(10**o.asset.decimals()).mulDivDown(
            o.minimumValueToRebalance,
            priceRouter.getPriceInUSD(o.asset)
        );

        uint8 rebalanceIndex;
        uint32[8] memory _positions = o.openPositions;
        uint256 freeCash;
        // Loop through and check negative imbalances, positions that want to withdraw assets.
        for (uint8 i = 0; i < 8; i++) {
            if (liquidityImbalance[i] >= 0) continue;
            uint256 amountToWithdraw = uint256(liquidityImbalance[i] * -1);
            // Make sure we are moving a substantial amount of assets.
            if (amountToWithdraw < minimumAmountToRebalance) continue;

            freeCash += amountToWithdraw;

            if (i == 0) {
                // No rebalance needed
                continue;
            }
            // Know we have a negative imabalnce so we need to withdraw from this position.
            uint32 positionId = _positions[i];
            from[rebalanceIndex] = positionId;
            to[rebalanceIndex] = 0;
            amount[rebalanceIndex] = amountToWithdraw;
            rebalanceIndex++;
        }

        // Now low through again but this time to add deposit rebalances
        // Loop through and check positive imbalances, positions that want to deposit assets.
        for (uint8 i = 0; i < 8; i++) {
            if (freeCash == 0) break;
            if (liquidityImbalance[i] <= 0) continue;
            // Know we have a negative imabalnce so we need to withdraw from this position.

            uint256 amountToDeposit = uint256(liquidityImbalance[i]);
            amountToDeposit = freeCash > amountToDeposit ? amountToDeposit : freeCash;
            // Make sure we are moving a substantial amount of assets.
            if (amountToDeposit < minimumAmountToRebalance) continue;
            freeCash -= amountToDeposit;
            if (i == 0) {
                // No rebalance needed
                continue;
            }
            uint32 positionId = _positions[i];
            from[rebalanceIndex] = 0;
            to[rebalanceIndex] = positionId;
            amount[rebalanceIndex] = amountToDeposit;
            rebalanceIndex++;
        }
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

    /**
     * @notice Apply a 1% slippage to all harvest TXs.
     */
    uint256 public constant harvestSlippage = 0.01e18;

    error DepositRouter__HarvestSlippageCheckFailed();

    function _harvestConvexPosition(Position storage p) internal returns (uint256 yield) {
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
        // Take platform fees.
        for (uint256 i = 0; i < rewardTokenCount; i++) {
            uint256 fee = rewardBalances[i].mulDivDown(platformFee, 1e18);
            rewardBalances[i] -= fee;
            rewardTokens[i].safeTransfer(feeAccumulator, fee);
        }
        // harvests rewards and immediately adds them back to the convex pool.
        DepositData memory depositData = p.depositData;
        ERC20 assetToDeposit = ERC20(depositData.asset);
        uint256 depositBalance = assetToDeposit.balanceOf(address(this));
        for (uint8 i = 0; i < 8; i++) {
            address pool;
            if ((pool = p.swapPools[i]) == address(0)) break;
            if (rewardBalances[i] < 0.01e18) continue; // Don't swap dust.
            _sellOnCurve(pool, p.froms[i], p.tos[i], rewardBalances[i], rewardTokens[i]);
        }

        depositBalance = assetToDeposit.balanceOf(address(this)) - depositBalance;

        // Compare value in to value out
        {
            uint256 valueIn = priceRouter.getValues(rewardTokens, rewardBalances, assetToDeposit);
            if (depositBalance < valueIn.mulDivDown(1e18 - harvestSlippage, 1e18))
                revert DepositRouter__HarvestSlippageCheckFailed();
        }

        // Add liquidity to pool.
        if (depositBalance > 0) {
            yield = p.asset.balanceOf(address(this));
            (, , address curvePool) = abi.decode(p.positionData, (uint256, address, address));

            _addLiquidityToCurve(
                assetToDeposit,
                depositData.coinsCount,
                depositData.targetIndex,
                depositData.useUnderlying,
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

    //============================================ Balance Of Functions ===========================================
    // CToken `getCashPrior` should call this.
    function balanceOf(address _operator) public view returns (uint256) {
        if (!operators[_operator].isOperator) revert DepositRouter__OperatorDoesNotExist(_operator);
        return _balanceOf(_operator);
    }

    function _balanceOf(address _operator) internal view returns (uint256 balance) {
        uint32[8] memory _positions = operators[_operator].openPositions;
        // Loop through all positions and query balance.
        for (uint256 i = 0; i < 8; i++) {
            uint32 positionId = _positions[i];
            if (positionId == 0 && i != 0) break;
            balance += _calcOperatorBalance(_operator, positionId);
        }
        // Calculates balance + pending balance, does not factor in pending rewards to be harvested.
    }

    function _calcOperatorBalance(address _operator, uint32 _positionId) internal view returns (uint256) {
        uint256 operatorShares = operatorPositionShares[_operator][_positionId];
        if (_positionId == 0) return operatorShares;
        Position memory p = positions[_positionId];
        if (p.totalSupply == 0) return 0;
        uint64 currentTime = uint64(block.timestamp);
        uint256 pendingBalance;
        if (p.rewardRate > 0 && p.lastAccrualTimestamp < p.endTimestamp) {
            // There are pending rewards.
            pendingBalance = currentTime < p.endTimestamp
                ? (p.rewardRate * (currentTime - p.lastAccrualTimestamp))
                : (p.rewardRate * (p.endTimestamp - p.lastAccrualTimestamp));
        } // else there are no pending rewards.
        uint256 assetsPerShare = (p.totalBalance + pendingBalance).mulDivDown(1e18, p.totalSupply);
        // console.log("End Timestamp", p.endTimestamp);
        return _convertToAssets(operatorShares, (p.totalBalance + pendingBalance), p);
        // return operatorShares.mulDivDown(assetsPerShare, 1e18); //(operatorShares * assetsPerShare) / 1e18;
    }

    function _convertToAssets(
        uint256 shares,
        uint256 _totalAssets,
        Position memory p
    ) internal view returns (uint256 assets) {
        uint256 totalShares = p.totalSupply;

        assets = totalShares == 0
            ? shares.changeDecimals(18, p.asset.decimals())
            : shares.mulDivDown(_totalAssets, totalShares);
    }

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

    /**
     * @notice Attempted to deposit into an unsupported Curve Pool.
     */
    error DepositRouter__UnsupportedCurveDeposit();

    function _addLiquidityToCurve(
        ERC20 assetToDeposit,
        uint8 coinsLength,
        uint8 targetIndex,
        bool useUnderlying,
        uint256 amount,
        address pool
    ) internal {
        assetToDeposit.approve(pool, amount);
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
