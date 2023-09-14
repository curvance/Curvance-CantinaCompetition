//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { ICVXLocker } from "contracts/interfaces/ICVXLocker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CVELocker is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Protocol epoch length
    uint256 public constant EPOCH_DURATION = 2 weeks;
    /// @notice Scalar for math
    uint256 public constant EXP_SCALE = 1e18;
    // `bytes4(keccak256(bytes("CVELocker__Unauthorized()")))`
    uint256 internal constant _CVELOCKER_UNAUTHORIZED_SELECTOR = 0x82274acf;
    // `bytes4(keccak256(bytes("CVELocker__FailedETHTransfer()")))`
    uint256 internal constant _FAILED_ETH_TRANSFER_SELECTOR = 0xe2e395e8;
    // `bytes4(keccak256(bytes("CVELocker__NoEpochRewards()")))`
    uint256 internal constant _NO_EPOCH_REWARDS_SELECTOR = 0x95721ba7;
    /// @notice CVE contract address
    address public immutable cve;
    /// @notice CVX contract address
    address public immutable cvx;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;
    /// @notice Reward token
    address public immutable baseRewardToken;

    /// STORAGE ///

    /// @notice veCVE contract address
    IVeCVE public veCVE;
    /// @notice Genesis Epoch timestamp
    uint256 public genesisEpoch;
    // 2 = yes; 1 = no
    uint256 public lockerStarted = 1;
    // 2 = yes; 1 = no
    uint256 public isShutdown = 1;

    /// @notice CVX Locker contract address
    ICVXLocker public cvxLocker;

    /// @notice The next undelivered epoch index
    uint256 public nextEpochToDeliver;

    // Important user invariant for rewards
    // User => Reward Next Claim Index
    mapping(address => uint256) public userNextClaimIndex;
    // RewardToken => 2 = yes; 0 or 1 = no
    mapping(address => uint256) public authorizedRewardToken;

    // Epoch # => Total Tokens Locked across all chains
    mapping(uint256 => uint256) public tokensLockedByEpoch;

    // Epoch # => Rewards per CVE multiplied by `EXP_SCALE`
    mapping(uint256 => uint256) public epochRewardsPerCVE;

    /// EVENTS ///

    event TokenRecovered(address token, address to, uint256 amount);
    event RewardPaid(
        address user,
        address recipient,
        address rewardToken,
        uint256 amount
    );

    /// ERRORS ///

    error CVELocker__CVXIsZeroAddress();
    error CVELocker__BaseRewardTokenIsZeroAddress();
    error CVELocker__Unauthorized();
    error CVELocker__FailedETHTransfer();
    error CVELocker__NoEpochRewards();
    error CVELocker__WrongEpochRewardSubmission();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "CVELocker: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "CVELocker: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyVeCVE() {
        address _veCVE = address(veCVE);
        assembly {
            if iszero(eq(caller(), _veCVE)) {
                mstore(0x00, _CVELOCKER_UNAUTHORIZED_SELECTOR)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    modifier onlyFeeAccumulator() {
        require(
            msg.sender == centralRegistry.feeAccumulator(),
            "CVELocker: UNAUTHORIZED"
        );
        _;
    }

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address cvx_,
        address baseRewardToken_
    ) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "CVELocker: invalid central registry"
        );
        if (cvx_ == address(0)) {
            revert CVELocker__CVXIsZeroAddress();
        }
        if (baseRewardToken_ == address(0)) {
            revert CVELocker__BaseRewardTokenIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        genesisEpoch = centralRegistry.genesisEpoch();
        cvx = cvx_;
        baseRewardToken = baseRewardToken_;
        cve = centralRegistry.CVE();
    }

    /// EXTERNAL FUNCTIONS ///

    function recordEpochRewards(
        uint256 epoch,
        uint256 rewardsPerCVE
    ) external onlyFeeAccumulator {
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

    function startLocker() external onlyDaoPermissions {
        require(lockerStarted == 1, "CVELocker: locker already started");

        veCVE = IVeCVE(centralRegistry.veCVE());
        genesisEpoch = centralRegistry.genesisEpoch();
        lockerStarted = 2;
    }

    /// @notice Recover tokens sent accidentally to the contract
    ///         or leftover rewards (excluding veCVE tokens)
    /// @param token The address of the token to recover
    /// @param to The address to receive the recovered tokens
    /// @param amount The amount of tokens to recover
    function recoverToken(
        address token,
        address to,
        uint256 amount
    ) external onlyDaoPermissions {
        require(
            token != baseRewardToken,
            "CVELocker: cannot withdraw reward token"
        );

        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }

        SafeTransferLib.safeTransfer(token, to, amount);

        emit TokenRecovered(token, to, amount);
    }

    /// @notice Authorizes a new reward token.
    /// @dev Can only be called by the DAO manager.
    /// @param token The address of the token to authorize.
    function addAuthorizedRewardToken(
        address token
    ) external onlyElevatedPermissions {
        require(token != address(0), "CVELocker: Invalid Token Address");
        require(
            authorizedRewardToken[token] < 2,
            "CVELocker: Invalid Operation"
        );
        authorizedRewardToken[token] = 2;
    }

    /// @notice Removes an authorized reward token.
    /// @dev Can only be called by the DAO manager.
    /// @param token The address of the token to deauthorize.
    function removeAuthorizedRewardToken(
        address token
    ) external onlyDaoPermissions {
        require(token != address(0), "CVELocker: Invalid Token Address");
        require(
            authorizedRewardToken[token] == 2,
            "CVELocker: Invalid Operation"
        );
        authorizedRewardToken[token] = 1;
    }

    function notifyLockerShutdown() external {
        require(
            msg.sender == address(veCVE) ||
                centralRegistry.hasElevatedPermissions(msg.sender),
            "CVELocker: UNAUTHORIZED"
        );
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
            veCVE.userTokenPoints(user) > 0
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
    ) external onlyVeCVE {
        userNextClaimIndex[user] = index;
    }

    /// @notice Reset user claim index
    /// @dev Deletes the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param user The address of the user.
    function resetUserClaimIndex(address user) external onlyVeCVE {
        delete userNextClaimIndex[user];
    }

    // Reward Functions

    /// @notice Claim rewards for multiple epochs
    /// @param recipient The address who should receive the rewards of user
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function claimRewards(
        address recipient,
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

        _claimRewards(msg.sender, recipient, epochs, rewardsData, params, aux);
    }

    /// @notice Claim rewards for multiple epochs
    /// @param user The address of the user.
    /// @param recipient The address who should receive the rewards of user
    /// @param epochs The number of epochs for which to claim rewards.
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function claimRewardsFor(
        address user,
        address recipient,
        uint256 epochs,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) external onlyVeCVE nonReentrant {
        // We check whether there are epochs to claim in veCVE
        // so we do not need to check here like in claimRewards
        _claimRewards(user, recipient, epochs, rewardsData, params, aux);
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
            veCVE.userTokenPoints(user) > 0
        ) {
            unchecked {
                return nextEpochToDeliver - (userNextClaimIndex[user] - 1);
            }
        }

        return 0;
    }

    /// INTERNAL FUNCTIONS ///

    // See claimRewardFor above
    function _claimRewards(
        address user,
        address recipient,
        uint256 epochs,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) internal {
        uint256 nextUserRewardEpoch = userNextClaimIndex[user];
        uint256 userRewards;

        for (uint256 i; i < epochs; ) {
            unchecked {
                userRewards += _calculateRewardsForEpoch(
                    user,
                    nextUserRewardEpoch + i++
                );
            }
        }

        unchecked {
            userNextClaimIndex[user] += epochs;
            // Removes the 1e18 offset for proper reward value
            userRewards = userRewards / EXP_SCALE;
        }

        uint256 rewardAmount = _processRewards(
            recipient,
            userRewards,
            rewardsData,
            params,
            aux
        );

        if (rewardAmount > 0) {
            // Only emit an event if they actually had rewards,
            // do not wanna revert to maintain composability
            emit RewardPaid(
                user,
                recipient,
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
        if (veCVE.userTokenUnlocksByEpoch(user, epoch) > 0) {
            // If they have tokens unlocking this epoch we need to decrease
            // their tokenPoints
            veCVE.updateUserPoints(user, epoch);
        }

        return (veCVE.userTokenPoints(user) * epochRewardsPerCVE[epoch]);
    }

    /// @notice Process user rewards
    /// @dev Process the rewards for the user, if any.
    ///      If the user wishes to receive rewards in a token other than
    ///      the base reward token, a swap is performed.
    ///      If the desired reward token is CVE and the user opts for lock,
    ///      the rewards are locked as VeCVE.
    /// @param userRewards The amount of rewards to process for the user.
    /// @param rewardsData Rewards data for CVE rewards locker
    /// @param params Additional parameters required for reward processing,
    ///               which may include swap data.
    /// @param aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function _processRewards(
        address recipient,
        uint256 userRewards,
        RewardsData calldata rewardsData,
        bytes calldata params,
        uint256 aux
    ) internal returns (uint256) {
        if (userRewards == 0) {
            return 0;
        }

        if (rewardsData.desiredRewardToken != baseRewardToken) {
            require(
                authorizedRewardToken[rewardsData.desiredRewardToken] == 2,
                "CVELocker: unsupported reward token"
            );

            if (
                rewardsData.desiredRewardToken == cvx && rewardsData.shouldLock
            ) {
                return
                    _lockFeesAsVlCVX(
                        recipient,
                        rewardsData.desiredRewardToken,
                        aux
                    );
            }

            if (
                rewardsData.desiredRewardToken == cve && rewardsData.shouldLock
            ) {
                // dont allow users to lock for others to avoid spam attacks
                return
                    _lockFeesAsVeCVE(
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
                swapData.inputToken != baseRewardToken ||
                swapData.outputToken != rewardsData.desiredRewardToken ||
                swapData.inputAmount > userRewards
            ) {
                revert("CVELocker: swapData misconfigured");
            }

            uint256 reward = SwapperLib.swap(swapData);

            if (swapData.outputToken == address(0)) {
                SafeTransferLib.safeTransferETH(recipient, reward);
            } else {
                SafeTransferLib.safeTransfer(
                    rewardsData.desiredRewardToken,
                    recipient,
                    reward
                );
            }

            return reward;
        }

        SafeTransferLib.safeTransfer(baseRewardToken, recipient, userRewards);

        return userRewards;
    }

    /// @notice Lock fees as veCVE
    /// @param desiredRewardToken The address of the token to be locked,
    ///                           this should be CVE.
    /// @param isFreshLock A boolean to indicate if it's a new lock.
    /// @param continuousLock A boolean to indicate if the lock should be continuous.
    /// @param lockIndex The index of the lock in the user's lock array.
    ///                  This parameter is only required if it is not a fresh lock.
    function _lockFeesAsVeCVE(
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
            veCVE.lockFor(
                msg.sender,
                reward,
                continuousLock,
                msg.sender,
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
            msg.sender,
            reward,
            lockIndex,
            continuousLock,
            msg.sender,
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

    /// @dev Lock fees as vlCVX
    /// @param recipient The address to receive the locked vlCVX tokens.
    /// @param desiredRewardToken The address of the token to be locked,
    ///                           this should be CVX.
    /// @param spendRatio X% of your deposit to gain Y% boost on the deposit,
    ///                   currently disabled.
    /// @return reward The total amount of CVX that was locked as vlCVX.
    function _lockFeesAsVlCVX(
        address recipient,
        address desiredRewardToken,
        uint256 spendRatio
    ) internal returns (uint256) {
        uint256 reward = IERC20(desiredRewardToken).balanceOf(address(this));
        cvxLocker.lock(recipient, reward, spendRatio);

        return reward;
    }
}
