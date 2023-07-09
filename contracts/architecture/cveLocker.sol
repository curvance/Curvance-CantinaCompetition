// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IVeCVE.sol";
import "../interfaces/ICvxLocker.sol";
import "contracts/interfaces/ICentralRegistry.sol";

contract cveLocker {
    using SafeERC20 for IERC20;

    event TokenRecovered(address _token, address _to, uint256 _amount);
    event RewardPaid(
        address _user,
        address _recipient,
        address _rewardToken,
        uint256 _amount
    );

    struct Swap {
        address target;
        bytes call;
    }

    // TO-DO:
    // Clean up variables at top
    // Process fee per cve reporting by chain in fee routing/here (permissioned functions for feerouting)
    // validate 1inch swap logic, have zeus write tests
    // Add epoch claim offset on users first lock
    // Figure out when fees should be active either current epoch or epoch + 1
    // Add epoch rewards view for frontend?
    // Claim all rewards and reset their initial claim offset flag for when they lock again?
    // Add slippage checks
    // Add minimum epoch claim
    // Add Whitelisted swappers
    // Add support for routing asset back into Curvance i.e. cvxCRV?
    // Change lastEpochFeesDelivered to next Epoch to deliver fees for?

    uint256 public immutable genesisEpoch;

    // Address for Curvance DAO registry contract for ownership and location data.
    ICentralRegistry public immutable centralRegistry;

    bool public isShutdown;

    // Token Addresses
    address public immutable cve;

    address public immutable cvx;
    IVeCVE public immutable veCVE;

    ICVXLocker public cvxLocker;

    address public constant baseRewardToken =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant EPOCH_DURATION = 2 weeks;
    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant ethPerCVEOffset = 1 ether;

    uint256 public nextEpochToDeliver;

    // User => Reward Next Claim Index
    mapping(address => uint256) public userNextClaimIndex;

    // Move Reward Tokens to Central Registry
    mapping(address => bool) public authorizedRewardToken;

    // Move this to Central Registry
    // What other chains are supported
    uint256[] public childChains;

    // Epoch # => ChainID => Tokens Locked in Epoch
    mapping(uint256 => mapping(uint256 => uint256)) public tokensLockedByChain;

    // Epoch # => Child Chains updated
    mapping(uint256 => uint256) public childChainsUpdatedByEpoch;

    // Epoch # => Total Tokens Locked across all chains
    mapping(uint256 => uint256) public totalTokensLockedByEpoch;

    // Epoch # => Ether rewards per CVE multiplier by offset
    mapping(uint256 => uint256) public ethPerCVE;

    constructor(ICentralRegistry _centralRegistry, address _cvx) {
        centralRegistry = _centralRegistry;
        genesisEpoch = centralRegistry.genesisEpoch();
        cvx = _cvx;
        cve = centralRegistry.CVE();
        veCVE = IVeCVE(centralRegistry.veCVE());
    }

    modifier onlyDaoManager() {
        require(
            msg.sender == centralRegistry.daoAddress(),
            "cveLocker: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyVeCVE() {
        require(msg.sender == address(veCVE), "cveLocker: UNAUTHORIZED");
        _;
    }

    modifier onlyMessagingHub() {
        require(
            msg.sender == centralRegistry.protocolMessagingHub(),
            "cveLocker: UNAUTHORIZED"
        );
        _;
    }

    /// @notice Returns the current epoch for the given time
    /// @param _time The timestamp for which to calculate the epoch
    /// @return The current epoch
    function currentEpoch(uint256 _time) public view returns (uint256) {
        if (_time < genesisEpoch) return 0;
        return ((_time - genesisEpoch) / EPOCH_DURATION);
    }

    /**
     * @notice Retrieves the last epoch for which rewards were distributed.
     * @return The last epoch for which CVE locker rewards were distributed.
     */
    function lastEpochRewardsDistributed() public view returns (uint256) {
        return nextEpochToDeliver - 1; // Cannot do unchecked here incase no epochs have rewards as we'd have 0 - 1 and underflow
    }

    /**
     * @notice Checks if a user has any CVE locker rewards to claim.
     * @dev Even if a users lock is expiring the next lock resulting in 0 points,
     *      we want their data updated so data is properly adjusted on unlock
     * @param _user The address of the user to check for reward claims.
     * @return A boolean value indicating if the user has any rewards to claim.
     */
    function hasRewardsToClaim(
        address _user
    ) public view returns (bool, uint256) {
        if (nextEpochToDeliver == 0) return (false, 0);
        if (
            nextEpochToDeliver > userNextClaimIndex[_user] &&
            veCVE.userTokenPoints(_user) > 0
        ) {
            unchecked {
                return (
                    true,
                    nextEpochToDeliver - userNextClaimIndex[_user] - 1
                );
            }
        }
        return (false, 0);
    }

    ///////////////////////////////////////////
    ////////// Fee Router Functions ///////////
    ///////////////////////////////////////////

    /// @notice Update user claim index
    /// @dev Updates the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param _user The address of the user.
    /// @param _index The new claim index.
    function updateUserClaimIndex(
        address _user,
        uint256 _index
    ) public onlyVeCVE {
        userNextClaimIndex[_user] = _index;
    }

    /// @notice Reset user claim index
    /// @dev Deletes the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param _user The address of the user.
    function resetUserClaimIndex(address _user) public onlyVeCVE {
        delete userNextClaimIndex[_user];
    }

    ///////////////////////////////////////////
    ///////////// Reward Functions ////////////
    ///////////////////////////////////////////

    /// @notice Claim rewards for multiple epochs
    /// @param _recipient The address who should receive the rewards of _user
    /// @param epoches The number of epochs for which to claim rewards.
    /// @param desiredRewardToken The address of the token to receive as a reward.
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param lock A boolean to indicate if the desiredRewardToken need to be locked if its CVE.
    /// @param isFreshLock A boolean to indicate if it's a new lock.
    /// @param _continuousLock A boolean to indicate if the lock should be continuous.
    /// @param _aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function claimRewards(
        address _recipient,
        uint256 epoches,
        address desiredRewardToken,
        bytes memory params,
        bool lock,
        bool isFreshLock,
        bool _continuousLock,
        uint256 _aux
    ) public {
        _claimRewards(
            msg.sender,
            _recipient,
            epoches,
            desiredRewardToken,
            params,
            lock,
            isFreshLock,
            _continuousLock,
            _aux
        );
    }

    /// @notice Claim rewards for multiple epochs
    /// @param _user The user who rewards should be claimed on behalf of
    /// @param _recipient The address who should receive the rewards of _user
    /// @param epoches The number of epochs for which to claim rewards.
    /// @param desiredRewardToken The address of the token to receive as a reward.
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param lock A boolean to indicate if the desiredRewardToken need to be locked if its CVE.
    /// @param isFreshLock A boolean to indicate if it's a new lock.
    /// @param _continuousLock A boolean to indicate if the lock should be continuous.
    /// @param _aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function claimRewardsFor(
        address _user,
        address _recipient,
        uint256 epoches,
        address desiredRewardToken,
        bytes memory params,
        bool lock,
        bool isFreshLock,
        bool _continuousLock,
        uint256 _aux
    ) public onlyVeCVE {
        _claimRewards(
            _user,
            _recipient,
            epoches,
            desiredRewardToken,
            params,
            lock,
            isFreshLock,
            _continuousLock,
            _aux
        );
    }

    // See claimRewardFor above
    function _claimRewards(
        address _user,
        address _recipient,
        uint256 epoches,
        address desiredRewardToken,
        bytes memory params,
        bool lock,
        bool isFreshLock,
        bool _continuousLock,
        uint256 _aux
    ) public {
        uint256 nextUserRewardEpoch = userNextClaimIndex[_user];
        require(
            nextUserRewardEpoch + epoches < nextEpochToDeliver,
            "cveLocker: epoch fees not yet delivered"
        );

        uint256 userRewards;

        for (uint256 i; i < epoches; ) {
            unchecked {
                userRewards += calculateRewardsForEpoch(
                    nextUserRewardEpoch + i++
                );
            }
        }

        unchecked {
            userNextClaimIndex[_user] += epoches;
            userRewards = userRewards / ethPerCVEOffset; //Removes the 1e18 offset for proper reward value
        }

        uint256 rewardAmount = _processRewards(
            _recipient,
            userRewards,
            desiredRewardToken,
            params,
            lock,
            isFreshLock,
            _continuousLock,
            _aux
        );

        if (rewardAmount > 0)
            // Only emit an event if they actually had rewards, do not wanna revert to maintain composability
            emit RewardPaid(
                _user,
                _recipient,
                desiredRewardToken,
                rewardAmount
            );
    }

    /// @notice Calculate the rewards for a given epoch
    /// @param _epoch The epoch for which to calculate the rewards.
    /// @return The calculated reward amount.
    ///         This is calculated based on the user's token points for the given epoch.
    function calculateRewardsForEpoch(
        uint256 _epoch
    ) internal returns (uint256) {
        if (veCVE.userTokenUnlocksByEpoch(msg.sender, _epoch) > 0) {
            // If they have tokens unlocking this epoch we need to decriment their tokenPoints
            veCVE.updateUserPoints(msg.sender, _epoch);
        }

        return (veCVE.userTokenPoints(msg.sender) * ethPerCVE[_epoch]);
    }

    /// @dev Swap input token
    /// @param _inputToken The input asset address
    /// @param _swapData The swap aggregation data
    function _swap(address _inputToken, Swap memory _swapData) private {
        _approveTokenIfNeeded(_inputToken, address(_swapData.target));

        (bool success, bytes memory retData) = _swapData.target.call(
            _swapData.call
        );

        propagateError(success, retData, "swap");

        require(success == true, "cveLocker: calling swap returned an error");
    }

    /// @dev Approve token if needed
    /// @param _token The token address
    /// @param _spender The spender address
    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint256).max);
        }
    }

    /// @dev Propagate error message
    /// @param success If transaction is successful
    /// @param data The transaction result data
    /// @param errorMessage The custom error message
    function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) public pure {
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    /// @notice Process user rewards
    /// @dev Process the rewards for the user, if any.
    ///      If the user wishes to receive rewards in a token other than
    ///      the base reward token, a swap is performed.
    ///      If the desired reward token is CVE and the user opts for lock,
    ///      the rewards are locked as VeCVE.
    /// @param userRewards The amount of rewards to process for the user.
    /// @param desiredRewardToken The address of the token the user wishes to receive as rewards.
    /// @param params Additional parameters required for reward processing,
    ///               which may include swap data.
    /// @param lock A boolean to indicate if the rewards need to be locked,
    ///             only needed if desiredRewardToken is CVE.
    /// @param isFreshLock A boolean to indicate if it's a new veCVE lock.
    /// @param _continuousLock A boolean to indicate if the lock should be continuous.
    /// @param _aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function _processRewards(
        address recipient,
        uint256 userRewards,
        address desiredRewardToken,
        bytes memory params,
        bool lock,
        bool isFreshLock,
        bool _continuousLock,
        uint256 _aux
    ) internal returns (uint256) {
        if (userRewards == 0) return 0;

        if (desiredRewardToken != baseRewardToken) {
            require(
                authorizedRewardToken[desiredRewardToken],
                "cveLocker: unsupported reward token"
            );

            Swap memory swapData = abi.decode(params, (Swap));

            if (swapData.call.length > 0) {
                _swap(desiredRewardToken, swapData);
            } else {
                revert("cveLocker: swapData misconfigured");
            }

            if (desiredRewardToken == cvx && lock) {
                return _lockFeesAsVlCVX(recipient, desiredRewardToken, _aux);
            }

            if (desiredRewardToken == cve && lock) {
                return
                    _lockFeesAsVeCVE(
                        desiredRewardToken,
                        isFreshLock,
                        _continuousLock,
                        _aux
                    ); //dont allow users to lock for others to avoid spam attacks
            }

            uint256 reward = IERC20(desiredRewardToken).balanceOf(
                address(this)
            );
            IERC20(baseRewardToken).safeTransfer(recipient, reward);
            return reward;
        }

        return _distributeRewardsAsETH(recipient, userRewards);
    }

    /// @notice Lock fees as VeCVE
    /// @param desiredRewardToken The address of the token to be locked, this should be CVE.
    /// @param isFreshLock A boolean to indicate if it's a new lock.
    /// @param _lockIndex The index of the lock in the user's lock array.
    ///                   This parameter is only required if it is not a fresh lock.
    /// @param _continuousLock A boolean to indicate if the lock should be continuous.
    function _lockFeesAsVeCVE(
        address desiredRewardToken,
        bool isFreshLock,
        bool _continuousLock,
        uint256 _lockIndex
    ) internal returns (uint256) {
        uint256 reward = IERC20(desiredRewardToken).balanceOf(address(this));

        if (isFreshLock) {
            veCVE.lockFor(msg.sender, reward, _continuousLock);
            return reward;
        }

        veCVE.increaseAmountAndExtendLockFor(
            msg.sender,
            reward,
            _lockIndex,
            _continuousLock
        );
        return reward;
    }

    function _lockFeesAsVlCVX(
        address _recipient,
        address desiredRewardToken,
        uint256 _spendRatio
    ) internal returns (uint256) {
        uint256 reward = IERC20(desiredRewardToken).balanceOf(address(this));
        cvxLocker.lock(_recipient, reward, _spendRatio);
        return reward;
    }

    function _distributeRewardsAsETH(
        address recipient,
        uint256 reward
    ) internal returns (uint256) {
        (bool success, ) = payable(recipient).call{ value: reward }("");
        require(success, "cveLocker: error sending ETH rewards");
        return reward;
    }

    /// @notice Recover tokens sent accidentally to the contract or
    ///         leftover rewards (excluding veCVE tokens)
    /// @param _token The address of the token to recover
    /// @param _to The address to receive the recovered tokens
    /// @param _amount The amount of tokens to recover
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyDaoManager {
        require(
            _token != baseRewardToken,
            "cveLocker: cannot withdraw reward token"
        );
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }
        IERC20(_token).safeTransfer(_to, _amount);

        emit TokenRecovered(_token, _to, _amount);
    }

    function addAuthorizedRewardToken(address _token) external onlyDaoManager {
        require(_token != address(0), "Invalid Token Address");
        require(!authorizedRewardToken[_token], "Invalid Operation");
        authorizedRewardToken[_token] = true;
    }

    function removeAuthorizedRewardToken(
        address _token
    ) external onlyDaoManager {
        require(_token != address(0), "Invalid Token Address");
        require(authorizedRewardToken[_token], "Invalid Operation");
        delete authorizedRewardToken[_token];
    }

    /// @param _chainId The remote chainId sending the tokens
    /// @param _srcAddress The remote Bridge address
    /// @param _nonce The message ordering nonce
    /// @param _token The token contract on the local chain
    /// @param amountLD The qty of local _token contract tokens
    /// @param _payload The bytes containing the _tokenOut, _deadline, _amountOutMin, _toAddr
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes memory _payload
    ) external payable {}

    receive() external payable {}
}
