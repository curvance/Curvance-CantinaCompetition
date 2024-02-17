// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugeController, GaugeErrors, IGaugePool } from "contracts/gauge/GaugeController.sol";

import { DENOMINATOR, WAD_SQUARED } from "contracts/libraries/Constants.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165 } from "contracts/libraries/external/ERC165.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICVE } from "contracts/interfaces/ICVE.sol";

contract GaugePool is GaugeController, ERC165, ReentrancyGuard {
    /// TYPES ///

    struct UserRewardInfo {
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    /// STORAGE ///

    /// @notice Address of the Market Manager linked to this Gauge Pool.
    address public marketManager;
    /// @notice Timestamp when the first first deposit occurred.
    uint256 public firstDeposit;
    /// @notice mToken => total supply.
    mapping(address => uint256) public totalSupply;
    /// @notice mToken => user => balance.
    mapping(address => mapping(address => uint256)) public balanceOf;
    /// @notice mToken => lastRewardTimestamp.
    mapping(address => uint256) public poolLastRewardTimestamp;
    /// @notice Reward tokens attached to this Gauge Pool.
    address[] public rewardTokens;
    /// @notice mToken => epoch => rewardToken => rewardPerSec.
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        private _epochRewardPerSec;
    /// @notice mToken => rewardToken => accRewardPerShare.
    mapping(address => mapping(address => uint256))
        public poolAccRewardPerShare;
    /// @notice mToken => user => rewardToken => info.
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

    /// @notice Initializes the gauge with a starting time based on the
    ///         next epoch.
    /// @dev    Can only be called once, to start the gauge system.
    /// @param marketManager_ The address to be set as a market manager.
    function start(address marketManager_) external {
        _checkDaoPermissions();

        if (startTime != 0) {
            revert GaugeErrors.AlreadyStarted();
        }

        // Validate that `marketManager_` is configured as a market manager
        // inside the Central Registry.
        if (!centralRegistry.isMarketManager(marketManager_)) {
            revert GaugeErrors.InvalidAddress();
        }

        startTime = veCVE.nextEpochStartTime();
        marketManager = marketManager_;
    }

    /// @notice Adds a new reward to the gauge system.
    /// @param newReward The address of new reward token to be added.
    function addExtraReward(address newReward) external {
        _checkDaoPermissions();

        if (newReward == address(0)) {
            revert GaugeErrors.InvalidAddress();
        }

        uint256 rewardTokensLength = rewardTokens.length;
        for (uint256 i; i < rewardTokensLength; ) {
            // Query rewardToken then increment i.
            if (rewardTokens[i++] == newReward) {
                revert GaugeErrors.InvalidAddress();
            }
        }

        rewardTokens.push(newReward);

        emit AddExtraReward(newReward);
    }

    /// @notice Removes an extra reward from the gauge system.
    /// @param index The index of the extra reward.
    /// @param newReward The address of the extra reward to be removed.
    function removeExtraReward(uint256 index, address newReward) external {
        _checkDaoPermissions();

        // Cannot remove CVE as a reward token.
        if (newReward == cve) {
            revert GaugeErrors.Unauthorized();
        }

        if (newReward != address(rewardTokens[index])) {
            revert GaugeErrors.InvalidAddress();
        }

        // If the extra reward is not the last one in the array,
        // copy its data down and then pop.
        uint256 rewardTokensLength = rewardTokens.length;
        if (index != (rewardTokensLength - 1)) {
            rewardTokens[index] = rewardTokens[rewardTokensLength - 1];
        }
        rewardTokens.pop();

        emit RemoveExtraReward(newReward);
    }

    /// @notice Returns the number of active reward tokens on the gauge pool,
    ///         for ease of integration by third parties.
    function getRewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    /// @notice Used to update gauge pool rewards for `rewardToken`, 
    ///         during `epoch` with `newRewardPerSec`.
    /// @dev This is only be used for updating partner gauge rewards.
    /// @param token The token to set rewards for.
    /// @param epoch The epoch to set rewards for, should be the next epoch.
    /// @param rewardToken The address of reward token to be updated.
    /// @param newRewardPerSec The `rewardToken` reward rate, in seconds.
    function setRewardPerSec(
        address token,
        uint256 epoch,
        address rewardToken,
        uint256 newRewardPerSec
    ) external {
        _checkDaoPermissions();

        // CVE rewards are only updated through the gauge system by
        // the protocol messaging hub in setEmissionRates().
        if (rewardToken == cve) {
            revert GaugeErrors.Unauthorized();
        }

        if (!(epoch == 0 && startTime == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 prevRewardPerSec = _epochRewardPerSec[token][epoch][rewardToken];
        _epochRewardPerSec[token][epoch][rewardToken] = newRewardPerSec;

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

    /// @notice Returns reward emissions of a token.
    /// @param token Pool token address that receives `rewardToken` overtime.
    /// @param epoch The epoch number.
    /// @param rewardToken The reward token address.
    function rewardAllocation(
        address token,
        uint256 epoch,
        address rewardToken
    ) public view returns (uint256) {
        if (rewardToken == cve) {
            return _epochInfo[epoch].poolWeights[token];
        }
        
        return
            (EPOCH_WINDOW *
                _epochRewardPerSec[token][epoch][rewardToken] *
                _epochInfo[epoch].poolWeights[token]) /
            _epochInfo[epoch].totalWeights;
        
    }

    /// @notice Returns pending reward of user.
    /// @param token Pool token address.
    /// @param user User address.
    /// @param rewardToken Reward token address.
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

                // update rewards from lastRewardTimestamp to endTimestamp.
                reward =
                    ((endTimestamp - lastRewardTimestamp) *
                        rewardAllocation(token, lastEpoch, rewardToken)) /
                    EPOCH_WINDOW;
                accRewardPerShare =
                    accRewardPerShare +
                    (reward * (WAD_SQUARED)) /
                    totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            // update rewards from lastRewardTimestamp to current timestamp.
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    rewardAllocation(token, lastEpoch, rewardToken)) /
                EPOCH_WINDOW;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (WAD_SQUARED)) /
                totalDeposited;
        }

        UserRewardInfo memory info = userDebtInfo[token][user][rewardToken];
        return
            info.rewardPending +
            (balanceOf[token][user] * accRewardPerShare) /
            (WAD_SQUARED) -
            info.rewardDebt;
    }

    /// @notice Returns pending rewards of user.
    /// @param token Pool token address.
    /// @param user User address.
    function pendingRewards(
        address token,
        address user
    ) external view returns (uint256[] memory results) {
        uint256 rewardTokensLength = rewardTokens.length;
        results = new uint256[](rewardTokensLength);

        for (uint256 i; i < rewardTokensLength; ++i) {
            results[i] = pendingRewards(token, user, rewardTokens[i]);
        }
    }

    /// @notice Deposit into gauge pool.
    /// @param token Pool token address.
    /// @param user User address.
    /// @param amount Amounts to deposit.
    function deposit(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        // Make sure the token is listed inside this market, 
        // and that the token is executing the deposit call.
        if (
            msg.sender != token ||
            !IMarketManager(marketManager).isListed(token)
        ) {
            revert GaugeErrors.InvalidToken();
        }

        updatePool(token);

        _calcPending(user, token);

        balanceOf[token][user] += amount;
        totalSupply[token] += amount;

        // If the gauge has not started yet no need to check whether
        // first deposit has been set.
        if (block.timestamp > startTime) {
            // If first deposit has not occurred we will need to send
            // excess rewards to the DAO.
            if (firstDeposit == 0) {
                // If first deposit, the new rewards from gauge start to this
                // point will be unallocated rewards.
                firstDeposit = block.timestamp;
                updatePool(token);

                uint256 rewardTokensLength = rewardTokens.length;
                for (uint256 i; i < rewardTokensLength; ) {
                    // Query rewardToken then increment i.
                    address rewardToken = rewardTokens[i++];
                    uint256 unallocatedRewards = (poolAccRewardPerShare[token][
                        rewardToken
                    ] * totalSupply[token]) / WAD_SQUARED;
                    if (unallocatedRewards > 0) {
                        SafeTransferLib.safeTransfer(
                            rewardToken,
                            centralRegistry.daoAddress(),
                            unallocatedRewards
                        );
                    }
                }
            }
        }

        _calcDebt(user, token);

        emit Deposit(user, token, amount);
    }

    /// @notice Registers a withdrawal of `token` deposits by `user`
    ///         from the gauge pool.
    /// @dev This does not actually include any token transfers as tokens
    ///      are permissionlessly escrowed by CToken/DToken contracts and
    ///      we simply record deposits/withdraws here.
    /// @param token Pool token address.
    /// @param user The user address.
    /// @param amount Amounts to withdraw.
    function withdraw(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert GaugeErrors.InvalidAmount();
        }

        // Make sure the token is listed inside this market, 
        // and that the token is executing the withdraw call.
        if (
            msg.sender != token ||
            !IMarketManager(marketManager).isListed(token)
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

    /// @notice Claim all pending rewards for `token` from the gauge pool.
    /// @param token Pool token address.
    function claim(address token) external nonReentrant {
        if (block.timestamp < startTime) {
            revert GaugeErrors.NotStarted();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        bool hasRewards;
        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i < rewardTokensLength; ) {
            // Query rewardToken then increment i.
            address rewardToken = rewardTokens[i++];
            uint256 rewards = userDebtInfo[token][msg.sender][rewardToken]
                .rewardPending;
            // If the caller has rewards, send them, 
            // and prevent transaction reversion.
            if (rewards > 0) {
                hasRewards = true;
                SafeTransferLib.safeTransfer(rewardToken, msg.sender, rewards);
            }

            // Update pending rewards to zero.
            userDebtInfo[token][msg.sender][rewardToken].rewardPending = 0;
        }
        if (!hasRewards) {
            revert GaugeErrors.NoReward();
        }

        _calcDebt(msg.sender, token);

        emit Claim(msg.sender, token);
    }

    /// @notice Claim rewards from gauge pool and compound any CVE rewards
    ///         into `lockIndex`.
    /// @dev Users who choose to lock emissions may potentially receive an
    ///      emission boost based on `lockBoostMultiplier` stored inside the
    ///      DAO Central Registry.
    /// @param token Pool token address.
    /// @param lockIndex The index of the lock to extend.
    /// @param continuousLock Whether the lock should be continuous or not.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function claimAndExtendLock(
        address token,
        uint256 lockIndex,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        // If gauge emissions have not started yet, 
        // theres nothing to claimAndExtendLock.
        if (block.timestamp < startTime) {
            revert GaugeErrors.NotStarted();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        // Check user pending rewards.
        uint256 rewards = userDebtInfo[token][msg.sender][cve].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        // Update pending rewards to zero.
        userDebtInfo[token][msg.sender][cve].rewardPending = 0;

        uint256 currentLockBoost = centralRegistry.lockBoostMultiplier();

        // If theres a current lock boost, recognize their bonus rewards.
        if (currentLockBoost > 0) {
            uint256 boostedRewards = (rewards * currentLockBoost) /
                DENOMINATOR;
            // We know this will never underflow due to `currentLockBoost`
            // needing to be greater than 1.
            ICVE(cve).mintLockBoost(boostedRewards - rewards);
            rewards = boostedRewards;
        }

        // Approve veCVE to take necessary cve to extend the lock.
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

    /// @notice Claim rewards from gauge pool and compound any CVE rewards
    ///         into a new veCVE lock.
    /// @dev Users who choose to lock emissions may potentially receive an
    ///      emission boost based on `lockBoostMultiplier` stored inside the
    ///      DAO Central Registry.
    /// @param token Pool token address.
    /// @param continuousLock Indicator of whether the lock should be continuous.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function claimAndLock(
        address token,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external nonReentrant {
        // If gauge emissions have not started yet, 
        // theres nothing to claimAndLock.
        if (block.timestamp < startTime) {
            revert GaugeErrors.NotStarted();
        }

        updatePool(token);
        _calcPending(msg.sender, token);

        // Check user pending rewards.
        uint256 rewards = userDebtInfo[token][msg.sender][cve].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }

        // Update pending rewards to zero.
        userDebtInfo[token][msg.sender][cve].rewardPending = 0;

        uint256 currentLockBoost = centralRegistry.lockBoostMultiplier();
        // If theres a current lock boost, recognize their bonus rewards.
        if (currentLockBoost > 0) {
            uint256 boostedRewards = (rewards * currentLockBoost) /
                DENOMINATOR;
            // We know this will never underflow due to `currentLockBoost`
            // needing to be greater than 1.
            ICVE(cve).mintLockBoost(boostedRewards - rewards);
            rewards = boostedRewards;
        }

        // Approve veCVE to take necessary cve to create the new lock.
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

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param token Pool token address.
    function updatePool(address token) public override {
        // If rewards have not started yet, there is nothing to update.
        if (block.timestamp <= startTime) {
            return;
        }

        uint256 _lastRewardTimestamp = poolLastRewardTimestamp[token];
        // If nobody has updated reward timestamp, time to set it up to startTime.
        if (_lastRewardTimestamp == 0) {
            _lastRewardTimestamp = startTime;
        }

        // Make sure time has passed since the last update.
        if (block.timestamp <= _lastRewardTimestamp) {
            return;
        }

        // Is there are no deposits, there is nothing to update.
        uint256 totalDeposited = totalSupply[token];
        if (totalDeposited == 0) {
            return;
        }

        // Cache rewardTokens length.
        uint256 rewardTokensLength = rewardTokens.length;
        for (uint256 i; i < rewardTokensLength; ) {
            uint256 lastRewardTimestamp = _lastRewardTimestamp;

            // Query rewardToken then increment i.
            address rewardToken = rewardTokens[i++];
            uint256 accRewardPerShare = poolAccRewardPerShare[token][
                rewardToken
            ];
            uint256 lastEpoch = epochOfTimestamp(lastRewardTimestamp);
            uint256 currentEpoch = currentEpoch();
            uint256 reward;

            // Step through epochs and apply rewards.
            while (lastEpoch < currentEpoch) {
                uint256 endTimestamp = epochEndTime(lastEpoch);

                // Update rewards from lastRewardTimestamp to endTimestamp.
                reward =
                    ((endTimestamp - lastRewardTimestamp) *
                        rewardAllocation(token, lastEpoch, rewardToken)) /
                    EPOCH_WINDOW;
                accRewardPerShare =
                    accRewardPerShare +
                    (reward * (WAD_SQUARED)) /
                    totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            // Update rewards from lastRewardTimestamp to current timestamp.
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    rewardAllocation(token, lastEpoch, rewardToken)) /
                EPOCH_WINDOW;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (WAD_SQUARED)) /
                totalDeposited;

            poolAccRewardPerShare[token][rewardToken] = accRewardPerShare;
        }

        // Update pool storage.
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

    /// @notice Calculate user's pending rewards.
    /// @param user User address.
    /// @param token Pool token address.
    function _calcPending(address user, address token) internal {
        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i < rewardTokensLength; ) {
            // Query rewardToken then increment i.
            address rewardToken = rewardTokens[i++];
            UserRewardInfo storage info = userDebtInfo[token][user][
                rewardToken
            ];
            info.rewardPending +=
                (balanceOf[token][user] *
                    poolAccRewardPerShare[token][rewardToken]) /
                (WAD_SQUARED) -
                info.rewardDebt;
        }
    }

    /// @notice Calculate user's debt amount for reward calculation.
    /// @param user User address.
    /// @param token Pool token address.
    function _calcDebt(address user, address token) internal {
        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i < rewardTokensLength; ) {
            // Query rewardToken then increment i.
            address rewardToken = rewardTokens[i++];
            UserRewardInfo storage info = userDebtInfo[token][user][
                rewardToken
            ];
            info.rewardDebt =
                (balanceOf[token][user] *
                    poolAccRewardPerShare[token][rewardToken]) /
                (WAD_SQUARED);
        }
    }
}
