//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract CVELocker is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Protocol epoch length
    uint256 public constant EPOCH_DURATION = 2 weeks;
    /// @notice CVE contract address
    address public immutable cve;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;
    /// @notice Reward token
    address public immutable rewardToken;
    /// @notice Genesis Epoch timestamp
    uint256 public immutable genesisEpoch;
    /// `bytes4(keccak256(bytes("CVELocker__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0x82274acf;
    /// `bytes4(keccak256(bytes("CVELocker__NoEpochRewards()")))`
    uint256 internal constant _NO_EPOCH_REWARDS_SELECTOR = 0x95721ba7;

    /// STORAGE ///

    /// @notice veCVE contract address
    IVeCVE public veCVE;
    // 2 = yes; 1 = no
    uint256 public lockerStarted = 1;
    // 2 = yes; 1 = no
    uint256 public isShutdown = 1;

    /// @notice The next undelivered epoch index
    uint256 public nextEpochToDeliver;

    // Important user invariant for rewards
    // User => Reward Next Claim Index
    mapping(address => uint256) public userNextClaimIndex;
    // RewardToken => 2 = yes; 0 or 1 = no
    mapping(address => uint256) public authorizedRewardToken;

    // Epoch # => Total Tokens Locked across all chains
    mapping(uint256 => uint256) public tokensLockedByEpoch;

    // Epoch # => Rewards per CVE multiplied by `WAD`
    mapping(uint256 => uint256) public epochRewardsPerCVE;

    /// EVENTS ///

    event RewardPaid(address user, address rewardToken, uint256 amount);

    /// ERRORS ///

    error CVELocker__InvalidCentralRegistry();
    error CVELocker__RewardTokenIsZeroAddress();
    error CVELocker__RewardTokenIsAlreadyAuthorized();
    error CVELocker__RewardTokenIsNotAuthorized();
    error CVELocker__SwapDataIsInvalid();
    error CVELocker__Unauthorized();
    error CVELocker__NoEpochRewards();
    error CVELocker__WrongEpochRewardSubmission();
    error CVELocker__TransferError();
    error CVELocker__LockerIsAlreadyStarted();

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_, address rewardToken_) {
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

        centralRegistry = centralRegistry_;
        genesisEpoch = centralRegistry.genesisEpoch();
        rewardToken = rewardToken_;
        cve = centralRegistry.CVE();
    }

    /// EXTERNAL FUNCTIONS ///

    function recordEpochRewards(
        uint256 epoch,
        uint256 rewardsPerCVE
    ) external {
        // Make sure the caller reporting epoch data is the fee accumulator itself
        if (msg.sender != centralRegistry.feeAccumulator()) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        if (epoch != nextEpochToDeliver) {
            revert CVELocker__WrongEpochRewardSubmission();
        }

        // Record rewards per CVE for the epoch
        epochRewardsPerCVE[epoch] = rewardsPerCVE;

        // Update nextEpochToDeliver invariant
        unchecked {
            ++nextEpochToDeliver;
        }
    }

    function startLocker() external {
        _checkDaoPermissions();

        if (lockerStarted == 2) {
            revert CVELocker__LockerIsAlreadyStarted();
        }

        veCVE = IVeCVE(centralRegistry.veCVE());
        lockerStarted = 2;
    }

    /// @notice Rescue any token sent by mistake
    /// @param token token to rescue
    /// @param amount amount of `token` to rescue, 0 indicates to rescue all
    function rescueToken(
        address token,
        uint256 amount
    ) external {
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

    /// @notice Authorizes a new reward token.
    /// @dev Can only be called by the DAO manager.
    /// @param token The address of the token to authorize.
    function addAuthorizedRewardToken(
        address token
    ) external {
        _checkElevatedPermissions();

        if (token == address(0)) {
            revert CVELocker__RewardTokenIsZeroAddress();
        }

        if (authorizedRewardToken[token] == 2) {
            revert CVELocker__RewardTokenIsAlreadyAuthorized();
        }

        authorizedRewardToken[token] = 2;
    }

    /// @notice Removes an authorized reward token.
    /// @dev Can only be called by the DAO manager.
    /// @param token The address of the token to deauthorize.
    function removeAuthorizedRewardToken(
        address token
    ) external {
        _checkDaoPermissions();

        if (token == address(0)) {
            revert CVELocker__RewardTokenIsZeroAddress();
        }

        if (authorizedRewardToken[token] < 2) {
            revert CVELocker__RewardTokenIsNotAuthorized();
        }

        authorizedRewardToken[token] = 1;
    }

    function notifyLockerShutdown() external {
        if (
            msg.sender != address(veCVE) &&
            !centralRegistry.hasElevatedPermissions(msg.sender)
        ) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        isShutdown = 2;
    }

    /// @notice Returns the current epoch for the given time
    /// @param time The timestamp for which to calculate the epoch
    /// @return The current epoch
    function currentEpoch(uint256 time) external view returns (uint256) {
        if (time < genesisEpoch) {
            return 0;
        }

        return ((time - genesisEpoch) / EPOCH_DURATION);
    }

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting
    ///      in 0 points, we want their data updated so data is properly
    ///      adjusted on unlock
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

    // Fee Router Functions

    /// @notice Update user claim index
    /// @dev Updates the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param user The address of the user.
    /// @param index The new claim index.
    function updateUserClaimIndex(
        address user,
        uint256 index
    ) external {
        _checkIsVeCVE();
        userNextClaimIndex[user] = index;
    }

    /// @notice Reset user claim index
    /// @dev Deletes the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param user The address of the user.
    function resetUserClaimIndex(address user) external {
        _checkIsVeCVE();
        delete userNextClaimIndex[user];
    }

    // Reward Functions

    /// @notice Claim rewards for multiple epochs
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param aux Auxiliary data for wrapped assets such as veCVE.
    function claimRewards(
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        uint256 epochs = epochsToClaim(msg.sender);

        // If there are no epoch rewards to claim, revert
        assembly {
            if iszero(epochs) {
                mstore(0x00, _NO_EPOCH_REWARDS_SELECTOR)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }

        _claimRewards(msg.sender, epochs, rewardsData, params, aux);
    }

    /// @notice Claim rewards for multiple epochs
    /// @param user The address of the user.
    /// @param epochs The number of epochs for which to claim rewards.
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param aux Auxiliary data for wrapped assets such as veCVE.
    function claimRewardsFor(
        address user,
        uint256 epochs,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external nonReentrant {
        _checkIsVeCVE();
        // We check whether there are epochs to claim in veCVE
        // so we do not need to check here like in claimRewards
        _claimRewards(user, epochs, rewardsData, params, aux);
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting
    ///      in 0 points, we want their data updated so data is properly
    ///      adjusted on unlock
    /// @param user The address of the user to check for reward claims.
    /// @return A boolean value indicating if the user has any rewards to claim.
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

    // See claimRewardFor above
    function _claimRewards(
        address user,
        uint256 epochs,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) internal {
        uint256 startEpoch = userNextClaimIndex[user];
        uint256 rewards;

        for (uint256 i; i < epochs; ) {
            unchecked {
                rewards += _calculateRewardsForEpoch(user, startEpoch + i++);
            }
        }

        unchecked {
            userNextClaimIndex[user] += epochs;
            // Removes the 1e18 offset for proper reward value
            rewards = rewards / WAD;
        }

        uint256 rewardAmount = _processRewards(
            user,
            rewards,
            rewardsData,
            params,
            aux
        );

        if (rewardAmount > 0) {
            // Only emit an event if they actually had rewards,
            // do not wanna revert to maintain composability
            emit RewardPaid(
                user,
                rewardsData.desiredRewardToken,
                rewardAmount
            );
        }
    }

    /// @notice Calculate the rewards for a given epoch
    /// @param user The address of the user.
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
            // their tokenPoints
            veCVE.updateUserPoints(user, epoch);
        }

        return (veCVE.userPoints(user) * epochRewardsPerCVE[epoch]);
    }

    /// @notice Process user rewards
    /// @dev Process the rewards for the user, if any.
    ///      If the user wishes to receive rewards in a token other than
    ///      the base reward token, a swap is performed.
    ///      If the desired reward token is CVE and the user opts for lock,
    ///      the rewards are locked as VeCVE.
    /// @param user The address of the user.
    /// @param rewards The amount of rewards to process for the user.
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Additional parameters required for reward processing,
    ///               which may include swap data.
    /// @param aux Auxiliary data for wrapped assets such as veCVE.
    function _processRewards(
        address user,
        uint256 rewards,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) internal returns (uint256) {
        if (rewards == 0) {
            return 0;
        }

        if (rewardsData.desiredRewardToken != rewardToken) {
            if (authorizedRewardToken[rewardsData.desiredRewardToken] < 2) {
                revert CVELocker__RewardTokenIsNotAuthorized();
            }

            if (
                rewardsData.desiredRewardToken == cve && rewardsData.shouldLock
            ) {
                // dont allow users to lock for others to avoid spam attacks
                return
                    _lockFeesAsVeCVE(
                        user,
                        rewardsData.desiredRewardToken,
                        rewardsData.isFreshLock,
                        rewardsData.isFreshLockContinuous,
                        aux
                    );
            }

            SwapperLib.Swap memory swapData = abi.decode(
                params,
                (SwapperLib.Swap)
            );

            if (
                swapData.call.length == 0 ||
                swapData.inputToken != rewardToken ||
                swapData.outputToken != rewardsData.desiredRewardToken ||
                swapData.inputAmount > rewards ||
                !centralRegistry.isSwapper(swapData.target)
            ) {
                revert CVELocker__SwapDataIsInvalid();
            }

            uint256 reward = SwapperLib.swap(swapData);

            if (swapData.outputToken == address(0)) {
                SafeTransferLib.safeTransferETH(user, reward);
            } else {
                SafeTransferLib.safeTransfer(
                    rewardsData.desiredRewardToken,
                    user,
                    reward
                );
            }

            return reward;
        }

        SafeTransferLib.safeTransfer(rewardToken, user, rewards);

        return rewards;
    }

    /// @notice Lock fees as veCVE
    /// @param user The address of the user.
    /// @param desiredRewardToken The address of the token to be locked,
    ///                           this should be CVE.
    /// @param isFreshLock A boolean to indicate if it's a new lock.
    /// @param continuousLock A boolean to indicate if the lock should be continuous.
    /// @param lockIndex The index of the lock in the user's lock array.
    ///                  This parameter is only required if it is not a fresh lock.
    function _lockFeesAsVeCVE(
        address user,
        address desiredRewardToken,
        bool isFreshLock,
        bool continuousLock,
        uint256 lockIndex
    ) internal returns (uint256) {
        uint256 reward = IERC20(desiredRewardToken).balanceOf(address(this));

        // Because this call is nested within call to claim all rewards
        // there will never be any rewards to process,
        // and thus no potential secondary lock so we can just pass
        // empty reward data to the veCVE calls
        if (isFreshLock) {
            veCVE.createLockFor(
                user,
                reward,
                continuousLock,
                RewardsData({
                    desiredRewardToken: desiredRewardToken,
                    shouldLock: false,
                    isFreshLock: false,
                    isFreshLockContinuous: false
                }),
                "",
                0
            );

            return reward;
        }

        // Because this call is nested within call to claim all rewards
        // there will never be any rewards to process,
        // and thus no potential secondary lock so we can just pass
        // empty reward data to the veCVE calls
        veCVE.increaseAmountAndExtendLockFor(
            user,
            reward,
            lockIndex,
            continuousLock,
            RewardsData({
                desiredRewardToken: desiredRewardToken,
                shouldLock: false,
                isFreshLock: false,
                isFreshLockContinuous: false
            }),
            "",
            0
        );

        return reward;
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
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }
    }
}
