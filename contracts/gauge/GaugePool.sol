// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugeController, GaugeErrors, IGaugePool } from "contracts/gauge/GaugeController.sol";

import { DENOMINATOR } from "contracts/libraries/Constants.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/external/ReentrancyGuard.sol";

import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";

contract GaugePool is GaugeController, ERC165, ReentrancyGuard {
    /// TYPES ///

    struct UserRewardInfo {
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    /// CONSTANTS ///

    /// @notice Scalar for math
    uint256 internal constant PRECISION = 1e36;
    address public lendtroller; // Lendtroller linked

    /// STORAGE ///

    uint256 public firstDeposit;
    // cToken => total supply
    mapping(address => uint256) public totalSupply;
    // cToken => user => balance
    mapping(address => mapping(address => uint256)) public balanceOf;
    // cToken => lastRewardTimestamp
    mapping(address => uint256) public poolLastRewardTimestamp;
    // Reward tokens attached
    address[] public rewardTokens;
    // epoch => rewardToken => rewardPerSec
    mapping(uint256 => mapping(address => uint256)) private _epochRewardPerSec;
    // cToken => rewardToken => accRewardPerShare
    mapping(address => mapping(address => uint256))
        public poolAccRewardPerShare;
    // cToken => user => rewardToken => info
    mapping(address => mapping(address => mapping(address => UserRewardInfo)))
        public userDebtInfo;

    /// EVENTS ///

    event AddExtraReward(address newReward);
    event RemoveExtraReward(address newReward);
    event Deposit(address user, address token, uint256 amount);
    event Withdraw(address user, address token, uint256 amount);
    event Claim(address user, address token);

    constructor(
        ICentralRegistry centralRegistry_
    ) GaugeController(centralRegistry_) {
        rewardTokens.push(cve);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Initializes the gauge with a starting time based on the next epoch
    /// @dev    Can only be called once, to start the gauge system
    /// @param lendtroller_ The address to be configured as a lending market
    function start(address lendtroller_) external {
        _checkDaoPermissions();

        if (startTime != 0) {
            revert GaugeErrors.AlreadyStarted();
        }

        // Validate that the lendtroller we are setting is actually a lending market
        if (!centralRegistry.isLendingMarket(lendtroller_)) {
            revert GaugeErrors.InvalidAddress();
        }

        if (
            !ERC165Checker.supportsInterface(
                address(lendtroller_),
                type(ILendtroller).interfaceId
            )
        ) {
            revert GaugeErrors.InvalidAddress();
        }

        startTime = veCVE.nextEpochStartTime();
        lendtroller = lendtroller_;
    }

    /// @notice Adds a new reward to the gauge system
    /// @param newReward The address of new reward token to be added
    function addExtraReward(address newReward) external {
        _checkDaoPermissions();

        if (newReward == address(0)) {
            revert GaugeErrors.InvalidAddress();
        }

        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            if (rewardTokens[i] == newReward) {
                revert GaugeErrors.InvalidAddress();
            }
        }

        rewardTokens.push(newReward);

        emit AddExtraReward(newReward);
    }

    /// @notice Removes an extra reward from the gauge system
    /// @param index The index of the extra reward
    /// @param newReward The address of the extra reward to be removed
    function removeExtraReward(uint256 index, address newReward) external {
        // Cannot remove CVE
        if (newReward == cve) {
            revert GaugeErrors.Unauthorized();
        }

        _checkDaoPermissions();

        if (newReward != address(rewardTokens[index])) {
            revert GaugeErrors.InvalidAddress();
        }

        // If the extra reward is not the last one in the array,
        // copy its data down and then pop
        if (index != (rewardTokens.length - 1)) {
            rewardTokens[index] = rewardTokens[rewardTokens.length - 1];
        }
        rewardTokens.pop();

        emit RemoveExtraReward(newReward);
    }

    function setRewardPerSec(
        uint256 epoch,
        address rewardToken,
        uint256 newRewardPerSec
    ) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert GaugeErrors.Unauthorized();
        }

        if (!(epoch == 0 && startTime == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 prevRewardPerSec = _epochRewardPerSec[epoch][rewardToken];
        _epochRewardPerSec[epoch][rewardToken] = newRewardPerSec;

        if (prevRewardPerSec > newRewardPerSec) {
            SafeTransferLib.safeTransfer(
                rewardToken,
                msg.sender,
                EPOCH_WINDOW * (prevRewardPerSec - newRewardPerSec)
            );
        } else {
            SafeTransferLib.safeTransferFrom(
                rewardToken,
                msg.sender,
                address(this),
                EPOCH_WINDOW * (newRewardPerSec - prevRewardPerSec)
            );
        }
    }

    /// @notice Returns reward emissions of a token
    /// @param token Pool token address
    /// @param epoch The epoch number
    /// @param rewardToken The reward token address
    function rewardAllocation(
        address token,
        uint256 epoch,
        address rewardToken
    ) public view returns (uint256) {
        if (rewardToken == cve) {
            return _epochInfo[epoch].poolWeights[token];
        } else {
            return
                (EPOCH_WINDOW *
                    _epochRewardPerSec[epoch][rewardToken] *
                    _epochInfo[epoch].poolWeights[token]) /
                _epochInfo[epoch].totalWeights;
        }
    }

    /// @notice Returns pending reward of user
    /// @param token Pool token address
    /// @param user User address
    /// @param rewardToken Reward token address
    function pendingRewards(
        address token,
        address user,
        address rewardToken
    ) public view returns (uint256) {
        uint256 accRewardPerShare = poolAccRewardPerShare[token][rewardToken];
        uint256 lastRewardTimestamp = poolLastRewardTimestamp[token];
        uint256 totalDeposited = totalSupply[token];
        if (lastRewardTimestamp == 0) {
            lastRewardTimestamp = startTime;
        }

        if (block.timestamp > lastRewardTimestamp && totalDeposited != 0) {
            uint256 lastEpoch = epochOfTimestamp(lastRewardTimestamp);
            uint256 currentEpoch = currentEpoch();
            uint256 reward;
            while (lastEpoch < currentEpoch) {
                uint256 endTimestamp = epochEndTime(lastEpoch);

                // update rewards from lastRewardTimestamp to endTimestamp
                reward =
                    ((endTimestamp - lastRewardTimestamp) *
                        rewardAllocation(token, lastEpoch, rewardToken)) /
                    EPOCH_WINDOW;
                accRewardPerShare =
                    accRewardPerShare +
                    (reward * (PRECISION)) /
                    totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            // update rewards from lastRewardTimestamp to current timestamp
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    rewardAllocation(token, lastEpoch, rewardToken)) /
                EPOCH_WINDOW;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (PRECISION)) /
                totalDeposited;
        }

        UserRewardInfo memory info = userDebtInfo[token][user][rewardToken];
        return
            info.rewardPending +
            (balanceOf[token][user] * accRewardPerShare) /
            (PRECISION) -
            info.rewardDebt;
    }

    /// @notice Returns pending rewards of user
    /// @param token Pool token address
    /// @param user User address
    function pendingRewards(
        address token,
        address user
    ) external view returns (uint256[] memory results) {
        results = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            results[i] = pendingRewards(token, user, rewardTokens[i]);
        }
    }

    /// @notice Deposit into gauge pool
    /// @param token Pool token address
    /// @param user User address
    /// @param amount Amounts to deposit
    function deposit(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        if (
            msg.sender != token || !ILendtroller(lendtroller).isListed(token)
        ) {
            revert GaugeErrors.InvalidToken();
        }

        updatePool(token);

        _calcPending(user, token);

        balanceOf[token][user] += amount;
        totalSupply[token] += amount;

        if (firstDeposit == 0) {
            // if first deposit, the new rewards from gauge start to this point will be unallocated rewards
            firstDeposit = block.timestamp;
            updatePool(token);

            for (uint256 i = 0; i < rewardTokens.length; ++i) {
                address rewardToken = rewardTokens[i];
                uint256 unallocatedRewards = (poolAccRewardPerShare[token][
                    rewardToken
                ] * totalSupply[token]) / PRECISION;
                if (unallocatedRewards > 0) {
                    SafeTransferLib.safeTransfer(
                        rewardToken,
                        centralRegistry.daoAddress(),
                        unallocatedRewards
                    );
                }
            }
        }

        _calcDebt(user, token);

        emit Deposit(user, token, amount);
    }

    /// @notice Withdraw from gauge pool
    /// @param token Pool token address
    /// @param user The user address
    /// @param amount Amounts to withdraw
    function withdraw(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }
        if (block.timestamp < startTime) {
            revert GaugeErrors.NotStarted();
        }

        if (
            msg.sender != token || !ILendtroller(lendtroller).isListed(token)
        ) {
            revert GaugeErrors.InvalidToken();
        }

        if (balanceOf[token][user] < amount) {
            revert GaugeErrors.InvalidAmount();
        }

        updatePool(token);
        _calcPending(user, token);

        balanceOf[token][user] -= amount;
        totalSupply[token] -= amount;

        _calcDebt(user, token);

        emit Withdraw(user, token, amount);
    }

    /// @notice Claim rewards from gauge pool
    /// @param token Pool token address
    function claim(address token) external nonReentrant {
        if (block.timestamp < startTime) {
            revert GaugeErrors.NotStarted();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        bool hasRewards = false;
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            uint256 rewards = userDebtInfo[token][msg.sender][rewardToken]
                .rewardPending;
            if (rewards > 0) {
                hasRewards = true;
                SafeTransferLib.safeTransfer(rewardToken, msg.sender, rewards);
            }

            userDebtInfo[token][msg.sender][rewardToken].rewardPending = 0;
        }
        if (!hasRewards) {
            revert GaugeErrors.NoReward();
        }

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token);
    }

    /// @notice Claim rewards from gauge pool
    /// @param token Pool token address
    function claimAndExtendLock(
        address token,
        uint256 lockIndex,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        if (block.timestamp < startTime) {
            revert GaugeErrors.NotStarted();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userDebtInfo[token][msg.sender][cve].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        userDebtInfo[token][msg.sender][cve].rewardPending = 0;

        uint256 currentLockBoost = centralRegistry.lockBoostMultiplier();
        // If theres a current lock boost, recognize their bonus rewards
        if (currentLockBoost > 0) {
            uint256 boostedRewards = (rewards * currentLockBoost) /
                DENOMINATOR;
            ICVE(cve).mintLockBoost(boostedRewards - rewards);
            rewards = boostedRewards;
        }

        SafeTransferLib.safeApprove(cve, address(veCVE), rewards);
        veCVE.increaseAmountAndExtendLockFor(
            msg.sender,
            rewards,
            lockIndex,
            continuousLock,
            rewardsData,
            params,
            aux
        );

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token);
    }

    /// @notice Claim rewards from gauge pool
    /// @param token Pool token address
    function claimAndLock(
        address token,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        if (block.timestamp < startTime) {
            revert GaugeErrors.NotStarted();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        uint256 rewards = userDebtInfo[token][msg.sender][cve].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        userDebtInfo[token][msg.sender][cve].rewardPending = 0;

        uint256 currentLockBoost = centralRegistry.lockBoostMultiplier();
        // If theres a current lock boost, recognize their bonus rewards
        if (currentLockBoost > 0) {
            uint256 boostedRewards = (rewards * currentLockBoost) /
                DENOMINATOR;
            ICVE(cve).mintLockBoost(boostedRewards - rewards);
            rewards = boostedRewards;
        }

        SafeTransferLib.safeApprove(cve, address(veCVE), rewards);
        veCVE.createLockFor(
            msg.sender,
            rewards,
            continuousLock,
            rewardsData,
            params,
            aux
        );

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token);
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Update reward variables of the given pool to be up-to-date
    /// @param token Pool token address
    function updatePool(address token) public override {
        if (block.timestamp <= startTime) {
            return;
        }

        uint256 _lastRewardTimestamp = poolLastRewardTimestamp[token];
        if (_lastRewardTimestamp == 0) {
            _lastRewardTimestamp = startTime;
        }

        if (block.timestamp <= _lastRewardTimestamp) {
            return;
        }

        uint256 totalDeposited = totalSupply[token];
        if (totalDeposited == 0) {
            return;
        }

        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            uint256 lastRewardTimestamp = _lastRewardTimestamp;
            address rewardToken = rewardTokens[i];
            uint256 accRewardPerShare = poolAccRewardPerShare[token][
                rewardToken
            ];
            uint256 lastEpoch = epochOfTimestamp(lastRewardTimestamp);
            uint256 currentEpoch = currentEpoch();
            uint256 reward;

            while (lastEpoch < currentEpoch) {
                uint256 endTimestamp = epochEndTime(lastEpoch);

                // update rewards from lastRewardTimestamp to endTimestamp
                reward =
                    ((endTimestamp - lastRewardTimestamp) *
                        rewardAllocation(token, lastEpoch, rewardToken)) /
                    EPOCH_WINDOW;
                accRewardPerShare =
                    accRewardPerShare +
                    (reward * (PRECISION)) /
                    totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            // update rewards from lastRewardTimestamp to current timestamp
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    rewardAllocation(token, lastEpoch, rewardToken)) /
                EPOCH_WINDOW;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (PRECISION)) /
                totalDeposited;

            poolAccRewardPerShare[token][rewardToken] = accRewardPerShare;
        }

        // update pool storage
        poolLastRewardTimestamp[token] = block.timestamp;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IGaugePool).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Calculate user's pending rewards
    function _calcPending(address user, address token) internal {
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            UserRewardInfo storage info = userDebtInfo[token][user][
                rewardToken
            ];
            info.rewardPending +=
                (balanceOf[token][user] *
                    poolAccRewardPerShare[token][rewardToken]) /
                (PRECISION) -
                info.rewardDebt;
        }
    }

    /// @notice Calculate user's debt amount for reward calculation
    function _calcDebt(address user, address token) internal {
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            UserRewardInfo storage info = userDebtInfo[token][user][
                rewardToken
            ];
            info.rewardDebt =
                (balanceOf[token][user] *
                    poolAccRewardPerShare[token][rewardToken]) /
                (PRECISION);
        }
    }
}
