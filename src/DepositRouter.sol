// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { PriceRouter } from "src/PricingOperations/PriceRouter.sol";

import { Math } from "src/utils/Math.sol";
import { Uint32Array } from "src/libraries/Uint32Array.sol";

// External interfaces
import { IYearnVault } from "src/interfaces/Yearn/IYearnVault.sol";
import { IBooster } from "src/interfaces/Convex/IBooster.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { ICurveFi } from "src/interfaces/Curve/ICurveFi.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Curvance Deposit Router
 * @notice Provides a universal interface allowing Curvance contracts to deposit and withdraw assets from:
 *         Convex
 *         Yearn
 * @author crispymangoes
 */
// Send some percent of rewards to CVE Rewarder, then keep the rest here to vest rewards
//Keepers and data feeds to automate harvesting, self funding upkeeps
contract DepositRouter is Ownable, KeeperCompatibleInterface {
    using Uint32Array for uint32[];
    using SafeTransferLib for ERC20;
    using Math for uint256;

    enum Platform {
        CONVEX
    }

    struct DepositData {
        address asset;
        uint8 coinsCount;
        uint8 targetIndex;
        bool useUnderlying;
    }

    // Position Storage.
    struct Position {
        uint256 totalSupply; // total amount of outstanding shares, used with `balance` to determine a share price.
        uint256 totalBalance; // total balance of all operators in position. Think this needs to be totalBalance of all assets in the position.
        uint128 rewardRate; // Vested rewards distributed per second.
        uint64 lastAccrualTimestamp; // Last timestamp when vested tokens were claimed.
        uint64 endTimestamp; // The end time stamp for when all current rewards are vested.
        Platform platform;
        ERC20 asset; // The underlying asset in a position.
        bytes positionData; // Stores arbritrary data for the position.
        address[8] swapPools;
        uint16[8] froms; // Store swapping information `from` asset
        uint16[8] tos; // Store swapping information `to` asset
        DepositData depositData;
    }

    PriceRouter public priceRouter;

    uint32[] public activePositions; // Array of all active positions.
    mapping(uint32 => Position) public positions;
    uint32 public positionCount;
    ///@dev 0 position id is reserved for holding

    uint32 public constant REWARD_PERIOD = 7 days;

    // Operator Storage.
    struct Operator {
        address owner; // What address can make changes to how this operator invests into positions.
        bool isOperator; // Bool indicating whether this operator has been set up.
        bool allowRebalancing;
        ERC20 asset;
        uint32[8] openPositions; // Positions operator currently has funds in. 0th postion is always the holding position.
        uint32[8] positionRatios; // Desired ratio for funds in positions. Could maybe allow a position to be just this contract, where it allows for cheaper use deposit/withdraws, and keepers perform batched TXs.
        //^^ 8 decimals
        uint64 minimumImbalanceDeltaForUpkeep; //minimum change in imbalance to allow a performupkeep to be performed IE 30%, 8 decimals
        uint64 minimumValueToRebalance; // The minimum dollar value of assets to rebalance. // 8 decimals
        //^^ if a rebalance operation is trying to move less than the minimum, then it is skipped.
        uint64 lastRebalance; // Timestamp of the last time this operators positions were rebalanced.
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

    //============================================ onlyOwner Functions ===========================================
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
            froms: _froms,
            tos: _tos,
            depositData: _depositData
        });
        positionCount++;
    }

    ///@dev operators can only be in positions with the SAME ASSET.
    function addOperator(
        address _operator,
        address _owner,
        ERC20 _asset,
        uint32[8] memory _positions,
        uint32[8] memory _positionRatios,
        uint64 _minimumImbalanceDeltaForUpkeep,
        uint64 _minimumValueToRebalance,
        uint64 _minimumTimeBetweenUpkeeps
    ) external onlyOwner {
        require(!operators[_operator].isOperator, "Operator already added.");
        //Positions are assumed to be packed to the front, IE you can not have a zero position between two non zero positions.
        // There should at the very least be position id 1 in the positions value.
        ///@dev position index 0 is the holding postion, where users funds are always deposited.
        require(_positions.length > 0, "0 is an invalid positions");
        // Loop through _positions and make sure it is valid.
        bool endPositionFound;
        for (uint32 i = 0; i < 8; i++) {
            uint32 positionId = _positions[i];
            if (i == 0) {
                // Make sure zero index is holding position.
                if (positionId != 0) revert("First Position must be the holding position");
            } else if (endPositionFound) {
                // If the end position is found enforce that all subsequent positions are zero.
                if (positionId != 0) revert("Invalid Position array!");
            } else {
                // Scan through the array until the end is found.
                if (positionId == 0) endPositionFound = true;
                else {
                    // Make sure position is valid.
                    if (positionId > positionCount) revert("Invalid Position array!!");
                    // Make sure operator is adding a position with the correct asset.
                    if (positions[positionId].asset != _asset) revert("Invalid Position array!!!");
                }
            }
        }
        operators[_operator] = Operator({
            owner: _owner,
            isOperator: true,
            allowRebalancing: false,
            asset: _asset,
            openPositions: _positions,
            positionRatios: _positionRatios,
            minimumImbalanceDeltaForUpkeep: _minimumImbalanceDeltaForUpkeep,
            minimumValueToRebalance: _minimumValueToRebalance,
            lastRebalance: uint64(block.timestamp),
            minimumTimeBetweenUpkeeps: _minimumTimeBetweenUpkeeps
        });
    }

    //========================================= Operator Owner Functions ========================================
    function changePositions(
        address _operator,
        uint32[8] calldata _positions,
        uint32[8] calldata _positionRatios
    ) external {
        require(operators[_operator].isOperator, "Only Operators can deposit.");
        require(operators[_operator].owner == msg.sender, "Not the Operator Owner");
        uint256 operatorBalanceBefore = _balanceOf(_operator);
        operators[_operator].openPositions = _positions;
        uint256 operatorBalanceAfter = _balanceOf(_operator);
        if (operatorBalanceAfter != operatorBalanceBefore) revert("Unclean positions.");
        //TODO this check might revert if moving from a position that does not perfectly track balances(YEARN) to positions that do(holding or CONVEX).
        //TODO make sure ratios add up to 1e8, also that a non zero ratio corresponds to an actual position.
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
        require(operators[_operator].isOperator, "Only Operators can deposit.");
        require(operators[_operator].owner == msg.sender, "Not the Operator Owner");
        performRebalances(_operator, from, to, amount);
    }

    //============================================ Operator Functions ===========================================
    /**
     * Takes underlying token and deposits it into the underlying protocol
     * returns the amount of shares
     */
    function deposit(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        require(operators[operator].isOperator, "Only Operators can deposit.");
        operators[operator].asset.safeTransferFrom(operator, address(this), amount);

        // Deposit assets into operator holding position.
        operatorPositionShares[operator][0] += amount;

        return amount;
    }

    function withdraw(uint256 amount) public returns (uint256) {
        address operator = msg.sender;
        require(operators[operator].isOperator, "Only Operators can withdraw.");

        // Withdraw assets from positions in order.
        uint256 freeCash = operatorPositionShares[operator][0];
        for (uint32 i = 1; i < 8; i++) {
            if (freeCash < amount) {
                uint256 positionBalance = operatorPositionShares[operator][i];
                // Need to withdraw from a position to the holding position.
                uint256 amountToWithdraw = (freeCash + positionBalance) < amount ? positionBalance : amount - freeCash;
                _withdrawFromPosition(operator, 0, amountToWithdraw);
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
     * @notice Operators will use a Chainlink Keeper to rebalance their positions
     * @notice The protocol(Curvance) will provide a keeper to harvest positions.
     */
    /**
     * @notice So I think the plan is to have keepers call this, and harvest functions.
     * Maybe have two different keepers, one dedicated to harvesting rewards, and another
     */
    //TODO make internal
    function rebalance(
        address _operator,
        uint32 _fromPosition,
        uint32 _toPosition,
        uint256 _amount
    ) public {
        if (_fromPosition == _toPosition) revert("Invalid Rebalance");
        _withdrawFromPosition(_operator, _fromPosition, _amount);
        _depositToPosition(_operator, _toPosition, _amount);
    }

    //TODO make internal
    function performRebalances(
        address operator,
        uint32[8] memory from,
        uint32[8] memory to,
        uint256[8] memory amount
    ) public {
        for (uint8 i; i < 8; i++) {
            // Assume rebalances are front loaded, so finding a zero amount breaks out of the for loop.
            if (amount[i] == 0) break;
            console.log("Rebalancing from", from[i]);
            console.log("Rebalancing to", to[i]);
            console.log("Rebalance Amount", amount[i]);
            rebalance(operator, from[i], to[i], amount[i]);
        }
    }

    function _depositToPosition(
        address _operator,
        uint32 _positionId,
        uint256 _amount
    ) internal {
        if (_positionId == 0) {
            // Depositing into holding position.
            operatorPositionShares[_operator][0] += _amount;
        } else {
            Position storage p = positions[_positionId];
            _updatePositionBalance(p); // This will take pending rewards and add it to p.totalBalance
            // So it needs to update totalBalance, and lastAccrualTimestamp

            if (p.platform == Platform.CONVEX) {
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
            operatorPositionShares[_operator][0] -= _amount;
        } else {
            Position storage p = positions[_positionId];
            _updatePositionBalance(p); // This will take pending rewards and add it to p.totalBalance
            // So it needs to update totalBalance, and lastAccrualTimestamp
            uint256 actualWithdraw;

            if (p.platform == Platform.CONVEX) {
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
            if (actualWithdraw > _amount) operatorPositionShares[_operator][0] += actualWithdraw - _amount;
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

    //============================================ Public Functions ===========================================
    /**
     * Updates a positions totalBalance, lastAccrualTimestamp, and determines the new Reward Rate, and sets new end timestamp.
     */
    function harvestPosition(uint32 _positionId) public {
        Position storage p = positions[_positionId];
        _updatePositionBalance(p); // Updates totalBalance and lastAccrualTimestamp
        if (p.platform == Platform.CONVEX) {
            _harvestConvexPosition(p);
        }
    }

    //============================================ Chainlink Automation Functions ===========================================
    //TODO minimum value check on upkeep could screw with the minmum delta change enforcement
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData) {
        address target = abi.decode(checkData, (address));
        if (target == address(this) || target == address(0)) {
            // Run harvest upkeep
            //TODO I think the checkData would store a range of position ids to check?
            // Check it against like a min harvestable dollar value?
        } else {
            // Run operator position management upkeep.
            Operator memory operator = operators[target];
            require(operator.isOperator, "Address is not an operator.");
            // Make sure enough time has passed.
            if (block.timestamp < (operator.lastRebalance + operator.minimumTimeBetweenUpkeeps))
                return (false, abi.encode(0));

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
        //Does all the heavy lifting to determine is a rebalance is needed, and where money should move.
        // Also has an alternative mode for harvesting positions.
    }

    //TODO this function can be made so it is only callable by keepers
    function performUpkeep(bytes calldata performData) external {
        address target = abi.decode(performData, (address));
        if (target == address(this) || target == address(0)) {
            // Run harvest upkeep
        } else {
            Operator memory operator = operators[target];
            require(operator.isOperator, "Address is not an operator.");
            if (block.timestamp < (operator.lastRebalance + operator.minimumTimeBetweenUpkeeps))
                revert("Minimum time not met.");
            (, uint32[8] memory from, uint32[8] memory to, uint256[8] memory amount) = abi.decode(
                performData,
                (address, uint32[8], uint32[8], uint256[8])
            );
            uint256 imbalanceBefore = _findOperatorPositionImbalance(target);
            performRebalances(target, from, to, amount);
            uint256 imbalanceAfter = _findOperatorPositionImbalance(target);
            // Underflow is desired, if imbalance increases, this TX should revert from underflow.
            if (imbalanceBefore - imbalanceAfter < operator.minimumImbalanceDeltaForUpkeep) revert("Delta too small.");
            //TODO for position management this function should check the current imbalance, then perform all rebalance calls, and check imbalance again.
            // If imbalance has decreased by some set amount call is gucci otherwise revert.
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
        console.log("Imbalance", positionImbalance);
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
        //TODO use price feed to determine minimum value that can be withdrawn from a position.
        uint256 minimumAmountToRebalance;

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

    //============================================ Yearn Integration Functions ===========================================
    ///@notice Yearn is not currently used.
    // Needs to return the actual backing of tokens in the protocol.
    /**
     * @notice Balances are based off of sharePrice * Shares.
     * @dev Pricing inspired by Mai Finance yvOracle.
     *      https://ftmscan.com/address/0x530cd67a5898a20501cfcf74a3c68e21831d744c#code
     */
    // function _depositToYearn(Position storage p, uint256 _amount) internal returns (uint256 amountDeposited) {
    //     address vaultAddress = abi.decode(p.positionData, (address));
    //     IYearnVault vault = IYearnVault(vaultAddress);
    //     p.asset.safeApprove(address(vault), _amount);
    //     uint256 shares = vault.deposit(_amount);
    //     amountDeposited = (shares * vault.pricePerShare()) / 10**vault.decimals();
    // }

    /**
     * @notice Yearn compounds rewards to increase share price over time.
     *         So in order to determine yield, we need to compare our
     *         last stored balance + pending rewards to the current balance.
     */
    // function _harvestYearnPosition(Position storage p) internal {
    //     address vaultAddress = abi.decode(p.positionData, (address));
    //     IYearnVault vault = IYearnVault(vaultAddress);

    //     // Find current pending rewards that have not been distributed yet.
    //     uint128 currentPendingRewards;
    //     if (p.rewardRate > 0) {
    //         currentPendingRewards = (p.endTimestamp - p.lastAccrualTimestamp) * p.rewardRate;
    //     }
    //     uint256 assetsAccountedFor = p.totalBalance + currentPendingRewards;

    //     // Get this contracts current position worth based off share price.
    //     uint256 currentBalance = (vault.balanceOf(address(this)) * vault.pricePerShare()) / 10**vault.decimals();

    //     //This happens when
    //     if (assetsAccountedFor > currentBalance) return;
    //     else {
    //         //TODO take platform fee
    //         uint256 yield = currentBalance - assetsAccountedFor; // yearn token balanceOf this address * the exchange rate to the underlying - totalAssets
    //         p.rewardRate = uint128((yield + currentPendingRewards) / REWARD_PERIOD);
    //         p.endTimestamp = uint64(block.timestamp) + REWARD_PERIOD;
    //         // lastAccrualTimestamp was already updated by _updatePositionBalance;
    //     }
    // }

    // function _withdrawFromYearn(Position storage p, uint256 _amount) internal returns (uint256 amountWithdrawn) {
    //     address vaultAddress = abi.decode(p.positionData, (address));
    //     IYearnVault vault = IYearnVault(vaultAddress);
    //     uint256 shares = (10**vault.decimals() * _amount) / vault.pricePerShare();
    //     uint256 balanceBefore = p.asset.balanceOf(address(this));
    //     vault.withdraw(shares);
    //     amountWithdrawn = p.asset.balanceOf(address(this)) - balanceBefore;
    // }

    /**
     * @notice Used by Keepers to determine pending yield from a yearn position in order to see if it is worth harvesting.
     */
    // function _pendingYearnYieldWorth(Position storage p) internal returns (uint256) {}

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
        DepositData memory depositData = p.depositData;
        ERC20 assetToDeposit = ERC20(depositData.asset);
        uint256 depositBalance = assetToDeposit.balanceOf(address(this));
        //TODO need to take platform fee.
        for (uint8 i = 0; i < 8; i++) {
            address pool;
            if ((pool = p.swapPools[i]) == address(0)) break;
            if (rewardBalances[i] < 0.01e18) continue; // Don't swap dust.
            _sellOnCurve(pool, p.froms[i], p.tos[i], rewardBalances[i], rewardTokens[i]);
        }

        depositBalance = assetToDeposit.balanceOf(address(this)) - depositBalance;

        // Add liquidity to pool.
        if (depositBalance > 0) {
            uint256 yield = p.asset.balanceOf(address(this));
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

    /**
     * @notice Used by Keepers to determine pending yield from a convex position in order to see if it is worth harvesting.
     */
    function _pendingConvexYieldWorth(Position storage p) internal returns (uint256) {}

    //============================================ Balance Of Functions ===========================================
    // CToken `getCashPrior` should call this.
    function balanceOf(address _operator) public view returns (uint256) {
        require(operators[_operator].isOperator, "Address is not an operator.");
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
        // Calculates balance + pending balance, does not facotr in pending rewards to be harvested.
    }

    function _calcOperatorBalance(address _operator, uint32 _positionId) internal view returns (uint256) {
        uint256 operatorShares = operatorPositionShares[_operator][_positionId];
        if (_positionId == 0) return operatorShares;
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
