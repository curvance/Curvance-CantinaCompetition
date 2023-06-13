//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./utils/SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IVeCVE.sol";
import "./interfaces/ICentralRegistry.sol";

contract cveLocker {
    using SafeERC20 for IERC20;

    event TokenRecovered(address _token, address _to, uint256 _amount);

    struct Swap {
        address target;
        bytes call;
    }

    //TO-DO: 
    //Clean up variables at top
    //Process fee per cve reporting by chain in fee routing/here (permissioned functions for feerouting)
    //Add case for cveETH?
    //validate 1inch swap logic, have zeus write tests
    //Add epoch claim offset on users first lock
    //Figure out when fees should be active either current epoch or epoch + 1
    //Add epoch rewards view for frontend?
    //Add token points offset for continuous lock

    uint256 public immutable genesisEpoch;
    ICentralRegistry public immutable centralRegistry;

    bool public isShutdown;
    address public baseRewardToken;
    uint256 public constant EPOCH_DURATION = 2 weeks;
    uint256 public constant DENOMINATOR = 10000;

    bool public genesisEpochFeesDelivered;
    uint256 public lastEpochFeesDelivered;

    mapping(address => uint256) public userLastEpochClaimed;
    mapping(address => bool) public userGenesisEpochClaimed;
    
    //MoveHelpers to Central Registry
    mapping(address => bool) public authorizedHelperContract;

    //User => Token Points 
    mapping(address => uint256) public userTokenPoints;
    //User => Epoch # => Tokens unlocked
    mapping(address => mapping(uint256 => uint256)) public userTokenUnlocksByEpoch;

    //What other chains are supported
    uint256[] public childChains;
    //Epoch # => ChainID => Tokens Locked in Epoch
    mapping(uint256 => mapping(uint256 => uint256)) public tokensLockedByChain;
    //Epoch # => Child Chains updated 
    mapping(uint256 => uint256) public childChainsUpdatedByEpoch;


    //Epoch # => Total Tokens Locked across all chains
    mapping(uint256 => uint256) public totalTokensLockedByEpoch;
    //Epoch # => Token unlocks on this chain
    mapping(uint256 => uint256) public totalUnlocksByEpoch;

    //Epoch # => Ether rewards per CVE multiplier by offset
    mapping(uint256 => uint256) public ethPerCVE;

    uint256 public constant ethPerCVEOffset = 1 ether;

    constructor(ICentralRegistry _centralRegistry) {
       
        centralRegistry = _centralRegistry;
        genesisEpoch = centralRegistry.genesisEpoch();
    }

    modifier onlyDaoManager () {
        require(msg.sender == centralRegistry.daoAddress(), "UNAUTHORIZED");
        _;
    }

    /**
     * @notice Returns the current epoch for the given time
     * @param _time The timestamp for which to calculate the epoch
     * @return The current epoch
     */
    function currentEpoch(uint256 _time) public view returns (uint256){
        if (_time < genesisEpoch) return 0;
        return ((_time - genesisEpoch)/EPOCH_DURATION); 
    }

    /**
    * @notice Claim rewards for the genesis epoch
    * @dev Allows a user to claim their rewards for the genesis epoch (epoch 0). Edge case handling is required for the genesis epoch.
    */
    function claimRewardsGenesisEpoch() public {
        //Need edge case for genesis epoch since epoch =  0
    }

    /**
    * @notice Claim rewards for multiple epochs
    * @param epoches The number of epochs for which to claim rewards.
    * @param desiredRewardToken The address of the token to receive as a reward.
    * @param params Swap data for token swapping rewards to desiredRewardToken.
    * @param lock A boolean to indicate if the desiredRewardToken need to be locked if its CVE.
    * @param isFreshLock A boolean to indicate if it's a new lock.
    * @param _lockIndex The index of the lock in the user's lock array.
    * @param _continuousLock A boolean to indicate if the lock should be continuous.
    */
    function claimRewardsMulti(uint256 epoches, address desiredRewardToken, bytes memory params, bool lock, bool isFreshLock, uint256 _lockIndex, bool _continuousLock) public {
        uint256 currentUserEpoch = userLastEpochClaimed[msg.sender];
        require(currentUserEpoch + epoches <= lastEpochFeesDelivered, "cveLocker: epoch fees not yet delivered");

        uint256 userRewards;

        for (uint256 i; i < epoches;){

            unchecked {
                userRewards += calculateRewardsForEpoch(currentUserEpoch + i++);
            }
            
        }

        userLastEpochClaimed[msg.sender] += epoches;
        processRewards(userRewards, desiredRewardToken, params, lock, isFreshLock, _lockIndex, _continuousLock);

    }

    /**
    * @notice Calculate the rewards for a given epoch
    * @param _epoch The epoch for which to calculate the rewards.
    * @return The calculated reward amount. This is calculated based on the user's token points for the given epoch.
    */
    function calculateRewardsForEpoch(uint256 _epoch) internal returns (uint256) {

        if (userTokenUnlocksByEpoch[msg.sender][_epoch] != 0) {// If they have tokens unlocking this epoch we need to decriment their tokenPoints
            userTokenPoints[msg.sender] -= userTokenUnlocksByEpoch[msg.sender][_epoch];
        }
        
        return (userTokenPoints[msg.sender] * ethPerCVE[_epoch])/ethPerCVEOffset;
    }

    /**
     * @dev Swap input token
     * @param _inputToken The input asset address
     * @param _swapData The swap aggregation data
     */
    function _swap(address _inputToken, Swap memory _swapData) private {
        _approveTokenIfNeeded(_inputToken, address(_swapData.target));

        (bool success, bytes memory retData) = _swapData.target.call(_swapData.call);

        propagateError(success, retData, "swap");

        require(success == true, "calling swap got an error");
    }

    /**
     * @dev Approve token if needed
     * @param _token The token address
     * @param _spender The spender address
     */
    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint256).max);
        }
    }

    /**
     * @dev Propagate error message
     * @param success If transaction is successful
     * @param data The transaction result data
     * @param errorMessage The custom error message
     */
    function propagateError(bool success, bytes memory data, string memory errorMessage) public pure {
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    /**
    * @notice Set the base reward token address
    * @dev Allows the DAO manager to set the address of the base reward token. 
    * @param _address The new address for the base reward token. 
    */
    function setBaseRewardToken (address _address) external onlyDaoManager {
        baseRewardToken = _address;
    }

    /**
    * @notice Process user rewards
    * @dev Process the rewards for the user, if any. If the user wishes to receive rewards in a token other than the base reward token, a swap is performed. 
    * If the desired reward token is CVE and the user opts for lock, the rewards are locked as VeCVE.
    * @param userRewards The amount of rewards to process for the user.
    * @param desiredRewardToken The address of the token the user wishes to receive as rewards.
    * @param params Additional parameters required for reward processing, which may include swap data.
    * @param lock A boolean to indicate if the rewards need to be locked, only needed if desiredRewardToken is CVE.
    * @param isFreshLock A boolean to indicate if it's a new veCVE lock.
    * @param _lockIndex The index of the lock in the user's veCVE lock array.
    * @param _continuousLock A boolean to indicate if the lock should be continuous.
    */
    function processRewards(uint256 userRewards, address desiredRewardToken, bytes memory params, bool lock, bool isFreshLock, uint256 _lockIndex, bool _continuousLock) internal {

        if (userRewards > 0) {

            if (desiredRewardToken != baseRewardToken){
                 (Swap memory swapData) = abi.decode(params, (Swap));

                 if (swapData.call.length > 0) {
                    _swap(desiredRewardToken, swapData);
                 }

                 if (desiredRewardToken == centralRegistry.CVE() && lock) {
                     lockFeesAsVeCVE(desiredRewardToken, isFreshLock, _lockIndex, _continuousLock);
                 }

            } else {

                if (baseRewardToken != address(0)){
                    IERC20(baseRewardToken).safeTransfer(msg.sender, userRewards);
                } else {
                    (bool success, ) = payable(msg.sender).call{ value: userRewards}("");
                    require(success, "cve: error sending ETH rewards");
                }

            }

        }

    }

    /**
    * @notice Lock fees as VeCVE
    * @param desiredRewardToken The address of the token to be locked, this should be CVE.
    * @param isFreshLock A boolean to indicate if it's a new lock.
    * @param _lockIndex The index of the lock in the user's lock array. This parameter is only required if it is not a fresh lock.
    * @param _continuousLock A boolean to indicate if the lock should be continuous.
    */
    function lockFeesAsVeCVE(address desiredRewardToken, bool isFreshLock, uint256 _lockIndex, bool _continuousLock) internal {

        if (isFreshLock){
            IVeCVE(centralRegistry.veCVE()).lockFor(msg.sender, IERC20(desiredRewardToken).balanceOf(address(this)), _continuousLock);

        } else {
            IVeCVE(centralRegistry.veCVE()).increaseAmountAndExtendLockFor(msg.sender, IERC20(desiredRewardToken).balanceOf(address(this)), _lockIndex, _continuousLock);
        }

    }

    /**
    * @notice Recover tokens sent accidentally to the contract or leftover rewards (excluding veCVE tokens)
    * @param _token The address of the token to recover
    * @param _to The address to receive the recovered tokens
    * @param _amount The amount of tokens to recover
    */
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyDaoManager {
        require(_token != address(this), "cannot withdraw veCVE token");
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }
        IERC20(_token).safeTransfer(_to, _amount);

        emit TokenRecovered(_token, _to, _amount);
    }

    /**
    * @notice Adds an address as an authorized helper contract
    * @param _helper The address of the locker contract to be set
    */
    function addAuthorizedHelper(address _helper) external onlyDaoManager {
        require(_helper != address(0), "Invalid Helper Address");
        require(!authorizedHelperContract[_helper], "Invalid Operation");
        authorizedHelperContract[_helper] = true;
    }

    /**
    * @notice Removes an address as an authorized helper contract
    * @param _helper The address of the locker contract to be set
    */
    function removeAuthorizedHelper(address _helper) external onlyDaoManager {
        require(_helper != address(0), "Invalid Helper Address");
        require(authorizedHelperContract[_helper], "Invalid Operation");
        delete authorizedHelperContract[_helper];
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
        uint _nonce, 
        address _token, 
        uint amountLD, 
        bytes memory _payload
    ) external payable {}

    receive() external payable{}


}