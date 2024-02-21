//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Delegable } from "contracts/libraries/Delegable.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CVELocker is Delegable, ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Protocol epoch length.
    uint256 public constant EPOCH_DURATION = 2 weeks;

    /// @notice The address of the CVE contract.
    address public immutable cve;
    /// @notice CVE Locker Reward token.
    address public immutable rewardToken;
    /// @notice Genesis Epoch timestamp.
    uint256 public immutable genesisEpoch;

    /// @dev `bytes4(keccak256(bytes("CVELocker__Unauthorized()")))`.
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x82274acf;
    /// @dev `bytes4(keccak256(bytes("CVELocker__NoEpochRewards()")))`.
    uint256 internal constant _NO_EPOCH_REWARDS_SELECTOR = 0x95721ba7;

    /// STORAGE ///

    /// @notice The address of the veCVE contract.
    IVeCVE public veCVE;
    /// @notice Whether the CVE Locker has been started or not.
    /// @dev 2 = yes; 1 = no.
    uint256 public lockerStarted = 1;
    /// @notice Whether the CVE Locker is shut down or not.
    /// @dev 2 = yes; 1 = no.
    uint256 public isShutdown = 1;

    /// @notice The next undelivered epoch index.
    /// @dev This should be as close to currentEpoch() + 1 as possible,
    ///      but can lag behind if crosschain systems are strained.
    uint256 public nextEpochToDeliver;

    /// @notice Important user invariant for rewards.
    /// @dev User => Reward Next Claim Index.
    mapping(address => uint256) public userNextClaimIndex;

    /// @notice The rewards alloted to 1 vote escrowed CVE for an epoch,
    ///         in `WAD`.
    /// @dev Epoch # => Rewards per veCVE.
    mapping(uint256 => uint256) public epochRewardsPerCVE;

    /// EVENTS ///

    event RewardPaid(address user, address rewardToken, uint256 amount);

    /// ERRORS ///

    error CVELocker__InvalidCentralRegistry();
    error CVELocker__RewardTokenIsZeroAddress();
    error CVELocker__SwapDataIsInvalid();
    error CVELocker__Unauthorized();
    error CVELocker__NoEpochRewards();
    error CVELocker__LockerIsAlreadyStarted();

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address rewardToken_
    ) Delegable(centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CVELocker__InvalidCentralRegistry();
        }

        if (rewardToken_ == address(0)) {
            revert CVELocker__RewardTokenIsZeroAddress();
        }

        genesisEpoch = centralRegistry.genesisEpoch();
        rewardToken = rewardToken_;
        cve = centralRegistry.cve();
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Called by the fee accumulator to record rewards allocated to
    ///         an epoch.
    /// @dev Only callable on by the Fee Accumulator.
    /// @param rewardsPerCVE The rewards alloted to 1 vote escrowed CVE for
    ///                      the next reward epoch delivered.
    function recordEpochRewards(uint256 rewardsPerCVE) external {
        // Validate the caller reporting epoch data is the fee accumulator.
        if (msg.sender != centralRegistry.feeAccumulator()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Record rewards per CVE for the epoch,
        // then update nextEpochToDeliver invariant.
        epochRewardsPerCVE[nextEpochToDeliver++] = rewardsPerCVE;
    }

    /// @notice Starts the CVE locker, called by the DAO after setting up
    ///         both CVELocker and veCVE contracts.
    /// @dev Only callable on by an entity with DAO permissions or higher.
    function startLocker() external {
        _checkDaoPermissions();

        if (lockerStarted == 2) {
            revert CVELocker__LockerIsAlreadyStarted();
        }

        veCVE = IVeCVE(centralRegistry.veCVE());
        lockerStarted = 2;
    }

    /// @notice Rescue any token sent by mistake.
    /// @param token token to rescue.
    /// @param amount amount of `token` to rescue, 0 indicates to rescue all.
    function rescueToken(address token, uint256 amount) external {
        _checkDaoPermissions();
        address daoOperator = centralRegistry.daoAddress();

        if (token == address(0)) {
            if (amount == 0) {
                amount = address(this).balance;
            }

            SafeTransferLib.forceSafeTransferETH(daoOperator, amount);
        } else {
            if (token == rewardToken) {
                _revert(_UNAUTHORIZED_SELECTOR);
            }

            if (amount == 0) {
                amount = IERC20(token).balanceOf(address(this));
            }

            SafeTransferLib.safeTransfer(token, daoOperator, amount);
        }
    }

    /// @notice Shuts down the CVELocker and prevents future reward
    /// distributions.
    /// @dev Should only be used to facilitate migration to a new system.
    function notifyLockerShutdown() external {
        if (
            msg.sender != address(veCVE) &&
            !centralRegistry.hasElevatedPermissions(msg.sender)
        ) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        isShutdown = 2;
    }

    /// @notice Returns the current epoch for the given time.
    /// @param time The timestamp for which to calculate the epoch.
    /// @return The current epoch.
    function currentEpoch(uint256 time) external view returns (uint256) {
        if (time < genesisEpoch) {
            return 0;
        }

        return ((time - genesisEpoch) / EPOCH_DURATION);
    }

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting
    ///      in 0 points, we want their data updated so data is properly
    ///      adjusted on unlock.
    /// @param user The address of the user to check for reward claims.
    /// @return A boolean value indicating if the user has any rewards
    ///         to claim.
    function hasRewardsToClaim(address user) external view returns (bool) {
        if (
            nextEpochToDeliver > userNextClaimIndex[user] &&
            veCVE.userPoints(user) > 0
        ) {
            return true;
        }

        return false;
    }

    /// CLAIM INDEX FUNCTIONS ///

    /// @notice Updates `user`'s claim index.
    /// @dev Updates the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param user The address of the user.
    /// @param index The new claim index.
    function updateUserClaimIndex(address user, uint256 index) external {
        _checkIsVeCVE();
        userNextClaimIndex[user] = index;
    }

    /// @notice Resets `user`'s claim index.
    /// @dev Deletes the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param user The address of the user.
    function resetUserClaimIndex(address user) external {
        _checkIsVeCVE();
        delete userNextClaimIndex[user];
    }

    /// REWARD FUNCTIONS ///

    /// @notice Claims rewards for multiple epochs.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param aux Auxiliary data for wrapped assets such as veCVE.
    function claimRewards(
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        uint256 epochs = epochsToClaim(msg.sender);

        // If there are no epoch rewards to claim, revert.
        assembly {
            if iszero(epochs) {
                mstore(0x00, _NO_EPOCH_REWARDS_SELECTOR)
                // Return bytes 29-32 for the selector.
                revert(0x1c, 0x04)
            }
        }

        _claimRewards(
            msg.sender,
            msg.sender,
            epochs,
            rewardsData,
            params,
            aux
        );
    }

    /// @notice Claims rewards for multiple epochs.
    /// @param user The address of the user claiming rewards.
    /// @param epochs The number of epochs for which to claim rewards.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Swap data for token swapping rewards to cve,
    ///               if necessary.
    /// @param aux Auxiliary data for veCVE.
    function claimRewardsFor(
        address user,
        uint256 epochs,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        _checkIsVeCVE();

        // We check whether there are epochs to claim in veCVE
        // so we do not need to check here like in claimRewards.
        _claimRewards(user, user, epochs, rewardsData, params, aux);
    }

    /// @notice Manages rewards for `user`, used at the beginning
    ///         of some external strategy for `user`.
    /// @dev Be extremely careful giving this authority to anyone, the
    ///      intention is to allow delegate claim functionality to hot wallets
    ///      or strategies that make sure of rewards directly without
    ///      distributing rewards to a user directly.
    ///      Emits a {ClaimApproval} event.
    /// @param user The address of the user having rewards managed.
    /// @param epochs The number of epochs for which to manage rewards.
    /// @return How much rewards were claimed for `user` from the locker.
    function manageRewardsFor(
        address user,
        uint256 epochs
    ) external nonReentrant returns (uint256) {
        if (!_checkIsDelegate(user, msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // We check whether there are epochs to claim in reward manager
        // modules so we do not need to check here like in claimRewards.
        return _claimRewardsDirect(user, epochs);
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting
    ///      in 0 points, we want their data updated so data is properly
    ///      adjusted on unlock.
    /// @param user The address of the user to check for reward claims.
    /// @return A value indicating if the user has any rewards to claim.
    function epochsToClaim(address user) public view returns (uint256) {
        if (
            nextEpochToDeliver > userNextClaimIndex[user] &&
            veCVE.userPoints(user) > 0
        ) {
            unchecked {
                return nextEpochToDeliver - (userNextClaimIndex[user]);
            }
        }

        return 0;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Claims rewards for multiple epochs.
    /// @dev May emit a {RewardPaid} event.
    /// @param user The address of the user claiming rewards.
    /// @param recipient The address receiving rewards.
    /// @param epochs The number of epochs for which to claim rewards.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Swap data for token swapping rewards to cve,
    ///               if necessary.
    /// @param aux Auxiliary data for veCVE.
    function _claimRewards(
        address user,
        address recipient,
        uint256 epochs,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) internal {
        uint256 rewards = _calculateRewards(user, epochs);

        // Process rewards and bubble up the amount of rewards received in
        // `rewardsData.desiredRewardToken`.
        uint256 rewardAmount = _processRewards(
            recipient,
            rewards,
            rewardsData,
            params,
            aux
        );

        // Only emit an event if they actually had rewards,
        // do not wanna revert to maintain composability.
        if (rewardAmount > 0) {
            emit RewardPaid(
                user,
                rewardsData.asCVE ? cve : rewardToken,
                rewardAmount
            );
        }
    }

    /// @notice Claims rewards for `epochs` directly without rewards
    ///         adjustment checks for `user`.
    /// @dev May emit a {RewardPaid} event.
    /// @param user The address of the user claiming rewards.
    /// @param epochs The number of epochs for which to claim rewards.
    /// @return rewards How much rewards were claimed for `user` from the locker.
    function _claimRewardsDirect(
        address user,
        uint256 epochs
    ) internal returns (uint256 rewards) {
        rewards = _calculateRewards(user, epochs);

        // Only emit an event if they actually had rewards,
        // do not wanna revert to maintain composability.
        if (rewards > 0) {
            // Transfer rewards directly to reward manager for strategy
            // execution.
            SafeTransferLib.safeTransfer(rewardToken, msg.sender, rewards);

            emit RewardPaid(user, rewardToken, rewards);
        }
    }

    /// @notice Calculates the rewards over `epochs`.
    /// @dev Updates userNextClaimIndex, documenting rewards claimed
    ///      by `user`. This is done prior to distribution to maintain
    ///      check effects.
    /// @param user The address of the user to calculate rewards for.
    /// @param epochs The epochs for which to calculate the rewards.
    /// @return The calculated reward amount.
    ///         This is calculated based on the user's token points
    ///         for the given epoch.
    function _calculateRewards(
        address user,
        uint256 epochs
    ) internal returns (uint256) {
        uint256 startEpoch = userNextClaimIndex[user];
        uint256 rewards;

        for (uint256 i; i < epochs; ) {
            unchecked {
                rewards += _calculateRewardsForEpoch(user, startEpoch + i++);
            }
        }

        // We do not need to worry about over/underflows here because
        // `userNextClaimIndex` only goes up by 1 every 2 weeks.
        unchecked {
            userNextClaimIndex[user] += epochs;
        }

        // Removes the `WAD` precision offset for proper reward value.
        return rewards / WAD;
    }

    /// @notice Calculate the rewards for a given epoch.
    /// @param user The address of the user to calculate rewards for.
    /// @param epoch The epoch for which to calculate the rewards.
    /// @return The calculated reward amount.
    ///         This is calculated based on the user's token points
    ///         for the given epoch.
    function _calculateRewardsForEpoch(
        address user,
        uint256 epoch
    ) internal returns (uint256) {
        if (veCVE.userUnlocksByEpoch(user, epoch) > 0) {
            // If they have tokens unlocking this epoch we need to decrease
            // their tokenPoints.
            veCVE.updateUserPoints(user, epoch);
        }

        return (veCVE.userPoints(user) * epochRewardsPerCVE[epoch]);
    }

    /// @notice Processes the rewards and distributes to `recipient`, if any.
    ///         If the recipient wishes to receive rewards in a token other than
    ///         the base reward token, a swap is performed.
    ///         If the desired reward token is CVE and the user opts for lock,
    ///         the rewards are locked as VeCVE.
    /// @param recipient The address receiving processed rewards.
    /// @param rewards The amount of rewards to process for `recipient`.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Swap data for token swapping rewards to cve,
    ///               if necessary.
    /// @param aux Auxiliary data for veCVE.
    /// @return The amount of reward token received by `recipient`,
    ///         in either `rewardToken` or CVE.
    function _processRewards(
        address recipient,
        uint256 rewards,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) internal returns (uint256) {
        // If there are no rewards we can return immediately.
        if (rewards == 0) {
            return 0;
        }

        // Check if `recipient` wants to route their rewards into another token.
        if (rewardsData.asCVE) {
            SwapperLib.Swap memory swapData = abi.decode(
                params,
                (SwapperLib.Swap)
            );

            // Swap into their desired reward token.
            if (
                swapData.call.length == 0 ||
                swapData.inputToken != rewardToken ||
                swapData.outputToken != cve ||
                swapData.inputAmount != rewards ||
                !centralRegistry.isSwapper(swapData.target)
            ) {
                revert CVELocker__SwapDataIsInvalid();
            }

            // Swap to CVE and update reward amount based on CVE received.
            uint256 adjustedRewards = SwapperLib.swap(
                centralRegistry,
                swapData
            );

            // Check if the claimer wants to lock as veCVE.
            if (rewardsData.shouldLock) {
                return
                    _lockRewardsAsVeCVE(
                        recipient,
                        rewardsData.isFreshLock,
                        rewardsData.isFreshLockContinuous,
                        aux
                    );
            }

            // Transfer them CVE then return.
            SafeTransferLib.safeTransfer(cve, recipient, adjustedRewards);
            return adjustedRewards;
        }

        // Transfer rewards then return.
        SafeTransferLib.safeTransfer(rewardToken, recipient, rewards);
        return rewards;
    }

    /// @notice Locks claimed fees as veCVE, in an old or fresh lock.
    /// @param user The address of the user locking fees as veCVE.
    /// @param isFreshLock A boolean to indicate if it's a new lock.
    /// @param continuousLock A boolean to indicate if the lock should be
    ///                       continuous.
    /// @param lockIndex The index of the lock in the user's lock array.
    ///                  This parameter is only required if it is not a fresh
    ///                  lock.
    /// @return The amount of CVE locked for `user`.
    function _lockRewardsAsVeCVE(
        address user,
        bool isFreshLock,
        bool continuousLock,
        uint256 lockIndex
    ) internal returns (uint256) {
        uint256 lockAmount = IERC20(cve).balanceOf(address(this));

        IERC20(cve).approve(address(veCVE), lockAmount);

        // Because this call is nested within call to claim all rewards
        // there will never be any rewards to process,
        // and thus no potential secondary lock so we can just pass
        // empty reward data to the veCVE calls.
        if (isFreshLock) {
            veCVE.createLockFor(
                user,
                lockAmount,
                continuousLock,
                RewardsData({
                    asCVE: false,
                    shouldLock: false,
                    isFreshLock: false,
                    isFreshLockContinuous: false
                }),
                "",
                0
            );

            return lockAmount;
        }

        // Because this call is nested within call to claim all rewards
        // there will never be any rewards to process,
        // and thus no potential secondary lock so we can just pass
        // empty reward data to the veCVE calls.
        veCVE.increaseAmountAndExtendLockFor(
            user,
            lockAmount,
            lockIndex,
            continuousLock,
            RewardsData({
                asCVE: false,
                shouldLock: false,
                isFreshLock: false,
                isFreshLockContinuous: false
            }),
            "",
            0
        );

        return lockAmount;
    }

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }

    /// @dev Checks whether the caller is the veCVE contract.
    function _checkIsVeCVE() internal view {
        address _veCVE = address(veCVE);
        assembly {
            if iszero(eq(caller(), _veCVE)) {
                mstore(0x00, _UNAUTHORIZED_SELECTOR)
                // Return bytes 29-32 for the selector.
                revert(0x1c, 0x04)
            }
        }
    }
}
