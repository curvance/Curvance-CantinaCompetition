// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { CommonLib } from "contracts/libraries/CommonLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";
import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";

contract SimpleRewardZapper is ReentrancyGuard {
    /// CONSTANTS ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Curvance CVE locker.
    ICVELocker public immutable cveLocker;
    /// @notice The address of the CVE locker reward token on this chain.
    address public immutable rewardToken;
    /// @notice The address of WETH on this chain.
    address public immutable WETH;

    /// @dev `bytes4(keccak256(bytes("SimpleRewardZapper__Unauthorized()")))`.
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xf52eef9e;

    /// STORAGE ///

    /// @notice Whether a market manager is approved for Zapping.
    /// @dev Output token => 2 = yes; 0 or 1 = no.
    mapping(address => uint256) public authorizedMarketManager;

    /// @notice Whether a token is approved for swapping.
    /// @dev Output token => 2 = yes; 0 or 1 = no.
    mapping(address => uint256) public authorizedOutputToken;

    /// ERRORS ///

    error SimpleRewardZapper__UnknownOutputToken();
    error SimpleRewardZapper__IsAlreadyAuthorized();
    error SimpleRewardZapper__IsNotAuthorized();
    error SimpleRewardZapper__InvalidInputAmount();
    error SimpleRewardZapper__InsufficientToRepay();
    error SimpleRewardZapper__NoRewardsToClaim();
    error SimpleRewardZapper__ExecutionError();
    error SimpleRewardZapper__Unauthorized();
    error SimpleRewardZapper__InvalidMarketManager();
    error SimpleRewardZapper__InvalidCentralRegistry();
    error SimpleRewardZapper__InvalidCVELocker();
    error SimpleRewardZapper__InvalidZapper(address invalidZapper);

    /// CONSTRUCTOR ///

    receive() external payable {}

    constructor(
        ICentralRegistry centralRegistry_,
        address WETH_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert SimpleRewardZapper__InvalidCentralRegistry();
        }

        address locker = centralRegistry_.cveLocker();

        // Validate that CVE locker is properly configured inside
        // the Central Registry.
        if (locker == address(0)) {
            revert SimpleRewardZapper__InvalidCVELocker();
        }

        centralRegistry = centralRegistry_;
        cveLocker = ICVELocker(locker);
        rewardToken = ICVELocker(locker).rewardToken();
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Claims CVE locker rewards, then swaps and transfers
    ///         `swapperData.outputToken` to `recipient`.
    /// @param swapperData Swap instruction data.
    /// @param recipient Address that should receive swapped output.
    /// @return outAmount The output amount received from swapping.
    function claimAndSwap(
        SwapperLib.Swap memory swapperData,
        address recipient
    ) external nonReentrant returns (uint256 outAmount) {
        // Normally in swappers we check whether the input is a networks gas
        // token, but we use cve lockers are built with non gas token
        // stablecoins as reward tokens. This means we do not need to check
        // CommonLib.isETH here.

        // Swap input token must match the reward token from the CVE locker,
        // rather than hardcoding input here this also acts as check that
        // solver API call instructions have been configured properly.
        if (swapperData.inputToken != rewardToken) {
            revert SimpleRewardZapper__ExecutionError();
        }

        // Validate that the desired output token is approved.
        if (authorizedOutputToken[swapperData.outputToken] != 2) {
            revert SimpleRewardZapper__UnknownOutputToken();
        }

        // Validate target contract is an approved swapper.
        if (!centralRegistry.isSwapper(swapperData.target)) {
            revert SimpleRewardZapper__InvalidZapper(swapperData.target);
        }

        // Claim caller rewards and cache reward amount.
        uint256 rewards = _processRewards(msg.sender);

        // Validate swap input amount equals rewards received.
        if (swapperData.inputAmount != rewards) {
            revert SimpleRewardZapper__InvalidInputAmount();
        }

        // Check how much in rewards were received from the swap.
        outAmount = SwapperLib.swap(centralRegistry, swapperData);

        // Make sure we did not somehow end up with an empty swap through
        // all prior checks, slippage checks are native handled by the solver
        // so we do not need to measure slippage % here.
        if (outAmount == 0) {
            revert SimpleRewardZapper__ExecutionError();
        }

        // Transfer output tokens to `recipient`.
        _transferToRecipient(swapperData.outputToken, recipient, outAmount);
    }

    /// @notice Claims CVE locker rewards, then Zaps, then deposits
    ///         `zapperCall.inputToken`, a cToken underlying, and enters
    ///         into Curvance collateral position.
    /// @param zapperCall Zap instruction data to execute the Zap.
    /// @param marketManager The Curvance market manager address which has
    ///                      listed `cToken`.
    /// @param cToken The Curvance cToken address.
    /// @param recipient Address that should receive Zapped deposit.
    /// @return The output amount of cTokens received from Zapping.
    function claimZapAndDeposit(
        SwapperLib.ZapperCall memory zapperCall,
        address marketManager,
        address cToken,
        address recipient
    ) external nonReentrant returns (uint256) {
        // Normally in swappers we check whether the input is a networks gas
        // token, but we use cve lockers are built with non gas token
        // stablecoins as reward tokens. This means we do not need to check
        // CommonLib.isETH here.

        // Swap input token must match the reward token from the CVE locker,
        // rather than hardcoding input here this also acts as check that
        // solver API call instructions have been configured properly.
        if (zapperCall.inputToken != rewardToken) {
            revert SimpleRewardZapper__ExecutionError();
        }

        // Validate that the desired Market Manager is approved.
        if (authorizedMarketManager[marketManager] != 2) {
            revert SimpleRewardZapper__UnknownOutputToken();
        }

        // Validate that `cToken` is listed inside the associated
        // Market Manager.
        if (!IMarketManager(marketManager).isListed(cToken)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // We do not need to check for an output token approval here since all
        // cTokens are natively authorized.

        // Validate target contract is an approved Zapper.
        if (!centralRegistry.isZapper(zapperCall.target)) {
            revert SimpleRewardZapper__InvalidZapper(zapperCall.target);
        }

        // Claim caller rewards and cache reward amount.
        uint256 rewards = _processRewards(msg.sender);

        // Validate Zap input amount equals rewards received.
        if (zapperCall.inputAmount != rewards) {
            revert SimpleRewardZapper__InvalidInputAmount();
        }

        // Execute Zap into cToken underlying.
        SwapperLib.zap(zapperCall);

        // Enter Curvance cToken position.
        return _enterCurvance(cToken, recipient);
    }

    /// @notice Claims CVE locker rewards, then may swap, then repays
    ///         dToken debt inside Curvance.
    /// @dev Sends any excess dToken underlying to `recipient`.
    ///      Only needs to swap if `rewardToken` != dToken underlying.
    /// @param swapperData Optional swap instruction data to execute the repayment.
    /// @param marketManager The Curvance market manager address which has
    ///                      listed `dToken`.
    /// @param dToken The Curvance dToken address.
    /// @param repayAmount The amount of dToken underlying to be repaid.
    /// @param recipient Address that should have its outstanding debt repaid.
    /// @return The excess amount of dToken underlying that was returned
    ///         to `recipient`.
    function claimSwapAndRepay(
        SwapperLib.Swap memory swapperData,
        address marketManager,
        address dToken,
        uint256 repayAmount,
        address recipient
    ) external nonReentrant returns (uint256) {
        // Normally in swappers we check whether the input is a networks gas
        // token, but we use cve lockers are built with non gas token
        // stablecoins as reward tokens. This means we do not need to check
        // CommonLib.isETH here.

        // Swap input token must match the reward token from the CVE locker,
        // rather than hardcoding input here this also acts as check that
        // solver API call instructions have been configured properly.
        if (swapperData.inputToken != rewardToken) {
            revert SimpleRewardZapper__ExecutionError();
        }

        // Validate that the desired Market Manager is approved.
        if (authorizedMarketManager[marketManager] != 2) {
            revert SimpleRewardZapper__UnknownOutputToken();
        }

        // Validate that `dToken` is listed inside the associated
        // Market Manager.
        if (!IMarketManager(marketManager).isListed(dToken)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Claim caller rewards and cache reward amount.
        uint256 rewards = _processRewards(msg.sender);

        // Validate swap input amount equals rewards received.
        if (swapperData.inputAmount != rewards) {
            revert SimpleRewardZapper__InvalidInputAmount();
        }

        // Cache underlying to minimize external calls.
        address dTokenUnderlying = DToken(dToken).underlying();

        if (swapperData.outputToken != dTokenUnderlying) {
            // Validate target contract is an approved swapper.
            if (!centralRegistry.isSwapper(swapperData.target)) {
                revert SimpleRewardZapper__InvalidZapper(swapperData.target);
            }

            // Swap from reward token into `dTokenUnderlying`.
            SwapperLib.swap(centralRegistry, swapperData);
        }

        // Repay Curvance dToken debt.
        return _repayDebt(dToken, dTokenUnderlying, repayAmount, recipient);
    }

    /// PERMISSIONED EXTERNAL FUNCTIONS ///

    /// @notice Authorizes a market manager for Zapping.
    /// @dev Only callable on by an entity with elevated DAO permissions.
    ///      Such as the timelock controller.
    /// @param newMarketManager The address of the market manager to authorize.
    function addAuthorizedMarketManager(address newMarketManager) external {
        _checkElevatedPermissions();

        // Validate `newMarketManager` is 
        if (authorizedMarketManager[newMarketManager] == 2) {
            revert SimpleRewardZapper__IsAlreadyAuthorized();
        }

        // Validate that `newMarketManager` is configured as a market manager
        // inside the Central Registry.
        if (!centralRegistry.isMarketManager(newMarketManager)) {
            revert SimpleRewardZapper__InvalidMarketManager();
        }

        // Authorize new Market Manager.
        authorizedMarketManager[newMarketManager] = 2;
    }

    /// @notice Removes authorization of market manager for Zapping.
    /// @dev Only callable on by an entity with DAO permissions or higher.
    /// @param currentMarketManager The address of the market manager to deauthorize.
    function removeAuthorizedMarketManager(address currentMarketManager) external {
        _checkDaoPermissions();

        if (authorizedMarketManager[currentMarketManager] != 2) {
            revert SimpleRewardZapper__IsNotAuthorized();
        }

        // Deauthorize current Market Manager.
        authorizedMarketManager[currentMarketManager] = 1;
    }

    /// @notice Authorizes a new reward token.
    /// @dev Only callable on by an entity with elevated DAO permissions.
    ///      Such as the timelock controller.
    /// @param outputToken The address of the token to authorize.
    function addAuthorizedOutputToken(address outputToken) external {
        _checkElevatedPermissions();

        if (outputToken == address(0)) {
            revert SimpleRewardZapper__UnknownOutputToken();
        }

        if (authorizedOutputToken[outputToken] == 2) {
            revert SimpleRewardZapper__IsAlreadyAuthorized();
        }

        authorizedOutputToken[outputToken] = 2;
    }

    /// @notice Removes an authorized reward token.
    /// @dev Only callable on by an entity with DAO permissions or higher.
    /// @param outputToken The address of the token to deauthorize.
    function removeAuthorizedOutputToken(address outputToken) external {
        _checkDaoPermissions();

        if (outputToken == address(0)) {
            revert SimpleRewardZapper__UnknownOutputToken();
        }

        if (authorizedOutputToken[outputToken] != 2) {
            revert SimpleRewardZapper__IsNotAuthorized();
        }

        authorizedOutputToken[outputToken] = 1;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Deposits cToken underlying into Curvance cToken contract.
    /// @param cToken The Curvance cToken address.
    /// @param recipient Address that should receive Curvance cTokens.
    /// @return The output amount of cTokens received.
    function _enterCurvance(
        address cToken,
        address recipient
    ) internal returns (uint256) {
        address cTokenUnderlying = CTokenPrimitive(cToken).underlying();
        uint256 balance = IERC20(cTokenUnderlying).balanceOf(address(this));

        // Approve cToken to take `inputToken`.
        SwapperLib._approveTokenIfNeeded(cTokenUnderlying, cToken, balance);

        uint256 priorBalance = IERC20(cToken).balanceOf(recipient);

        // Enter Curvance cToken position and make sure `recipient` got
        // cTokens.
        if (CTokenPrimitive(cToken).deposit(balance, recipient) == 0) {
            revert SimpleRewardZapper__ExecutionError();
        }

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(cTokenUnderlying, cToken);

        // Bubble up how many cTokens `recipient` received.
        return IERC20(cToken).balanceOf(recipient) - priorBalance;
    }

    /// @notice Repays Curvance lenders dToken underlying owed on behalf
    ///         of `recipient`.
    /// @param dToken The Curvance dToken address.
    /// @param dTokenUnderlying The underlying token for `dToken`.
    /// @param repayAmount The amount of dToken underlying to be repaid.
    /// @param recipient Address that should have outstanding debt repaid.
    /// @return outAmount The excess amount of dToken underlying that was
    ///                   returned to `recipient`.
    function _repayDebt(
        address dToken,
        address dTokenUnderlying,
        uint256 repayAmount,
        address recipient
    ) internal returns (uint256 outAmount) {
        // Manually query balance here since its possible we did not swap if
        // rewardToken == outputToken.
        // We also never need to worry about this capturing other peoples
        // balances since the Zapper should never be holding any reward token,
        // or dToken underlying itself.
        outAmount = IERC20(dTokenUnderlying).balanceOf(address(this));
        
        // Revert if the swap experienced too much slippage.
        if (outAmount < repayAmount) {
            revert SimpleRewardZapper__InsufficientToRepay();
        }

        // Approve `dTokenUnderlying` to dToken contract, if necessary.
        SwapperLib._approveTokenIfNeeded(
            dTokenUnderlying,
            dToken,
            repayAmount
        );

        // Execute repayment of dToken debt.
        DToken(dToken).repayFor(recipient, repayAmount);

        // Remove any excess approval.
        SwapperLib._removeApprovalIfNeeded(dTokenUnderlying, dToken);

        outAmount -= repayAmount;

        // Transfer any remaining `dTokenUnderlying` to `recipient`.
        if (outAmount > 0) {
            _transferToRecipient(
                dTokenUnderlying, 
                recipient, 
                outAmount
            );
        }
    }

    /// @notice Checks whether `user` has rewards, if they do, claim them
    ///         to this contract and bubble up the reward amount.
    /// @param user The address of the user to process rewards for.
    /// @return The amount of rewards received from processing.
    function _processRewards(address user) internal returns (uint256) {
        uint256 epochs = cveLocker.epochsToClaim(user);

        // Validate that the caller actually has rewards to claim.
        if (epochs == 0) {
            revert SimpleRewardZapper__NoRewardsToClaim();
        }

        return cveLocker.manageRewardsFor(user, epochs);
    }

    /// @notice Helper function for efficiently transferring tokens
    ///         to desired user.
    /// @param token The token to transfer to `recipient`, 
    ///              this can be the network gas token.
    /// @param recipient The user receiving `token`.
    /// @param amount The amount of `token` to be transferred to `recipient`.
    function _transferToRecipient(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (CommonLib.isETH(token)) {
            return SafeTransferLib.forceSafeTransferETH(recipient, amount);
        }
            
        SafeTransferLib.safeTransfer(token, recipient, amount);
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
}
