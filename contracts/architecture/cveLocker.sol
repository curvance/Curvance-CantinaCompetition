//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { rewardsData } from "contracts/interfaces/ICveLocker.sol";
import { ICVXLocker } from "contracts/interfaces/ICvxLocker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract cveLocker {
    event TokenRecovered(address _token, address _to, uint256 _amount);
    event RewardPaid(
        address _user,
        address _recipient,
        address _rewardToken,
        uint256 _amount
    );

    // TO-DO:
    // Process fee per cve reporting by chain in fee routing/here (permissioned functions for feerouting)
    // Figure out when fees should be active either current epoch or epoch + 1
    // Add epoch rewards view for frontend?

    // Add slippage checks
    // Add Whitelisted swappers

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
    uint256 public constant SLIPPAGE = 500; // 5%

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

    constructor(ICentralRegistry centralRegistry_, address _cvx) {

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "cveLocker: invalid central registry"
        );

        centralRegistry = centralRegistry_;
        genesisEpoch = centralRegistry.genesisEpoch();
        cvx = _cvx;
        cve = centralRegistry.CVE();
        veCVE = IVeCVE(centralRegistry.veCVE());
    }

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "cveLocker: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
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

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting in 0 points,
    ///      we want their data updated so data is properly adjusted on unlock
    /// @param _user The address of the user to check for reward claims.
    /// @return A boolean value indicating if the user has any rewards to claim.
    function hasRewardsToClaim(address _user) public view returns (bool) {
        if (
            nextEpochToDeliver > userNextClaimIndex[_user] &&
            veCVE.userTokenPoints(_user) > 0
        ) return true;
        return false;
    }

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting in 0 points,
    ///      we want their data updated so data is properly adjusted on unlock
    /// @param _user The address of the user to check for reward claims.
    /// @return A boolean value indicating if the user has any rewards to claim.
    function epochsToClaim(address _user) public view returns (uint256) {
        if (
            nextEpochToDeliver > userNextClaimIndex[_user] &&
            veCVE.userTokenPoints(_user) > 0
        ) {
            unchecked {
                return nextEpochToDeliver - userNextClaimIndex[_user] - 1;
            }
        }
        return 0;
    }

    ///////////////////////////////////////////
    ////////// Fee Router Functions ///////////
    ///////////////////////////////////////////

    /// @notice Update user claim index
    /// @dev Updates the claim index of a user. Can only be called by the VeCVE contract.
    /// @param _user The address of the user.
    /// @param _index The new claim index.
    function updateUserClaimIndex(
        address _user,
        uint256 _index
    ) public onlyVeCVE {
        userNextClaimIndex[_user] = _index;
    }

    /// @notice Reset user claim index
    /// @dev Deletes the claim index of a user. Can only be called by the VeCVE contract.
    /// @param _user The address of the user.
    function resetUserClaimIndex(address _user) public onlyVeCVE {
        delete userNextClaimIndex[_user];
    }

    ///////////////////////////////////////////
    ///////////// Reward Functions ////////////
    ///////////////////////////////////////////

    /// @notice Claim rewards for multiple epochs
    /// @param _recipient The address who should receive the rewards of _user
    /// @param _rewardsData Rewards data for CVE rewards locker
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param _aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function claimRewards(
        address _recipient,
        rewardsData memory _rewardsData,
        bytes memory params,
        uint256 _aux
    ) public {
        uint256 epochs = epochsToClaim(msg.sender);
        require(epochs > 0, "cveLocker: no epochs to claim");
        _claimRewards(
            msg.sender,
            _recipient,
            epochs,
            _rewardsData,
            params,
            _aux
        );
    }

    /// @notice Claim rewards for multiple epochs
    /// @param _recipient The address who should receive the rewards of _user
    /// @param epochs The number of epochs for which to claim rewards.
    /// @param _rewardsData Rewards data for CVE rewards locker
    /// @param params Swap data for token swapping rewards to desiredRewardToken.
    /// @param _aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function claimRewardsFor(
        address _user,
        address _recipient,
        uint256 epochs,
        rewardsData memory _rewardsData,
        bytes memory params,
        uint256 _aux
    ) public onlyVeCVE {
        /// We check whether there are epochs to claim in veCVE so we do not need to check here like in claimRewards
        _claimRewards(_user, _recipient, epochs, _rewardsData, params, _aux);
    }

    // See claimRewardFor above
    function _claimRewards(
        address _user,
        address _recipient,
        uint256 epochs,
        rewardsData memory _rewardsData,
        bytes memory params,
        uint256 _aux
    ) public {
        uint256 nextUserRewardEpoch = userNextClaimIndex[_user];
        uint256 userRewards;

        for (uint256 i; i < epochs; ) {
            unchecked {
                userRewards += calculateRewardsForEpoch(
                    nextUserRewardEpoch + i++
                );
            }
        }

        unchecked {
            userNextClaimIndex[_user] += epochs;
            userRewards = userRewards / ethPerCVEOffset; //Removes the 1e18 offset for proper reward value
        }

        uint256 rewardAmount = _processRewards(
            _recipient,
            userRewards,
            _rewardsData,
            params,
            _aux
        );

        if (rewardAmount > 0)
            // Only emit an event if they actually had rewards, do not wanna revert to maintain composability
            emit RewardPaid(
                _user,
                _recipient,
                _rewardsData.desiredRewardToken,
                rewardAmount
            );
    }

    /// @notice Calculate the rewards for a given epoch
    /// @param _epoch The epoch for which to calculate the rewards.
    /// @return The calculated reward amount. This is calculated based on the user's token points for the given epoch.
    function calculateRewardsForEpoch(
        uint256 _epoch
    ) internal returns (uint256) {
        if (veCVE.userTokenUnlocksByEpoch(msg.sender, _epoch) > 0) {
            // If they have tokens unlocking this epoch we need to decriment their tokenPoints
            veCVE.updateUserPoints(msg.sender, _epoch);
        }

        return (veCVE.userTokenPoints(msg.sender) * ethPerCVE[_epoch]);
    }

    /// @notice Process user rewards
    /// @dev Process the rewards for the user, if any. If the user wishes to receive rewards in a token other than the base reward token, a swap is performed.
    /// If the desired reward token is CVE and the user opts for lock, the rewards are locked as VeCVE.
    /// @param userRewards The amount of rewards to process for the user.
    /// @param _rewardsData Rewards data for CVE rewards locker
    /// @param params Additional parameters required for reward processing, which may include swap data.
    /// @param _aux Auxiliary data for wrapped assets such as vlCVX and veCVE.
    function _processRewards(
        address recipient,
        uint256 userRewards,
        rewardsData memory _rewardsData,
        bytes memory params,
        uint256 _aux
    ) internal returns (uint256) {
        if (userRewards == 0) return 0;

        if (_rewardsData.desiredRewardToken != baseRewardToken) {
            require(
                authorizedRewardToken[_rewardsData.desiredRewardToken],
                "cveLocker: unsupported reward token"
            );

            SwapperLib.Swap memory swapData = abi.decode(
                params,
                (SwapperLib.Swap)
            );

            if (swapData.call.length > 0) {
                SwapperLib.swap(
                    swapData,
                    ICentralRegistry(centralRegistry).priceRouter(),
                    SLIPPAGE
                );
            } else {
                revert("cveLocker: swapData misconfigured");
            }

            if (
                _rewardsData.desiredRewardToken == cvx &&
                _rewardsData.shouldLock
            ) {
                return
                    _lockFeesAsVlCVX(
                        recipient,
                        _rewardsData.desiredRewardToken,
                        _aux
                    );
            }

            if (
                _rewardsData.desiredRewardToken == cve &&
                _rewardsData.shouldLock
            ) {
                return
                    _lockFeesAsVeCVE(
                        _rewardsData.desiredRewardToken,
                        _rewardsData.isFreshLock,
                        _rewardsData.isFreshLockContinuous,
                        _aux
                    ); // dont allow users to lock for others to avoid spam attacks
            }

            uint256 reward = IERC20(_rewardsData.desiredRewardToken).balanceOf(
                address(this)
            );
            SafeTransferLib.safeTransfer(baseRewardToken, recipient, reward);
            return reward;
        }

        return _distributeRewardsAsETH(recipient, userRewards);
    }

    /// @notice Lock fees as veCVE
    /// @param desiredRewardToken The address of the token to be locked, this should be CVE.
    /// @param isFreshLock A boolean to indicate if it's a new lock.
    /// @param continuousLock A boolean to indicate if the lock should be continuous.
    /// @param lockIndex The index of the lock in the user's lock array. This parameter is only required if it is not a fresh lock.
    function _lockFeesAsVeCVE(
        address desiredRewardToken,
        bool isFreshLock,
        bool continuousLock,
        uint256 lockIndex
    ) internal returns (uint256) {
        uint256 reward = IERC20(desiredRewardToken).balanceOf(address(this));

        /// Because this call is nested within call to claim all rewards there will never be any rewards to process,
        /// and thus no potential secondary lock so we can just pass empty reward data to the veCVE calls
        if (isFreshLock) {
            veCVE.lockFor(
                msg.sender,
                reward,
                continuousLock,
                msg.sender,
                rewardsData({
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

        /// Because this call is nested within call to claim all rewards there will never be any rewards to process,
        /// and thus no potential secondary lock so we can just pass empty reward data to the veCVE calls
        veCVE.increaseAmountAndExtendLockFor(
            msg.sender,
            reward,
            lockIndex,
            continuousLock,
            msg.sender,
            rewardsData({
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
    /// @param _recipient The address to receive the locked vlCVX tokens.
    /// @param desiredRewardToken The address of the token to be locked, this should be CVX.
    /// @param _spendRatio X% of your deposit to gain Y% boost on the deposit, currently disabled.
    /// @return reward The total amount of CVX that was locked as vlCVX.
    function _lockFeesAsVlCVX(
        address _recipient,
        address desiredRewardToken,
        uint256 _spendRatio
    ) internal returns (uint256) {
        uint256 reward = IERC20(desiredRewardToken).balanceOf(address(this));
        cvxLocker.lock(_recipient, reward, _spendRatio);
        return reward;
    }

    /// @dev Distributes the specified reward amount as ETH to the recipient address.
    /// @param recipient The address to receive the ETH rewards.
    /// @param reward The amount of ETH to send.
    /// @return reward The total amount of ETH that was sent.
    function _distributeRewardsAsETH(
        address recipient,
        uint256 reward
    ) internal returns (uint256) {
        (bool success, ) = payable(recipient).call{ value: reward }("");
        require(success, "cveLocker: error sending ETH rewards");
        return reward;
    }

    /// @notice Recover tokens sent accidentally to the contract or leftover rewards (excluding veCVE tokens)
    /// @param _token The address of the token to recover
    /// @param _to The address to receive the recovered tokens
    /// @param _amount The amount of tokens to recover
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyDaoPermissions {
        require(
            _token != baseRewardToken,
            "cveLocker: cannot withdraw reward token"
        );
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }
        SafeTransferLib.safeTransfer(_token, _to, _amount);

        emit TokenRecovered(_token, _to, _amount);
    }

    /// @dev Authorizes a new reward token. Can only be called by the DAO manager.
    /// @param _token The address of the token to authorize.
    function addAuthorizedRewardToken(
        address _token
    ) external onlyElevatedPermissions {
        require(_token != address(0), "Invalid Token Address");
        require(!authorizedRewardToken[_token], "Invalid Operation");
        authorizedRewardToken[_token] = true;
    }

    /// @dev Removes an authorized reward token. Can only be called by the DAO manager.
    /// @param _token The address of the token to deauthorize.
    function removeAuthorizedRewardToken(
        address _token
    ) external onlyDaoPermissions {
        require(_token != address(0), "Invalid Token Address");
        require(authorizedRewardToken[_token], "Invalid Operation");
        delete authorizedRewardToken[_token];
    }

    function notifyLockerShutdown() external {
        require(
            msg.sender == address(veCVE) ||
                centralRegistry.hasElevatedPermissions(msg.sender),
            "cveLocker: UNAUTHORIZED"
        );
        isShutdown = true;
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
