// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { IProtocolMessagingHub } from "contracts/interfaces/IProtocolMessagingHub.sol";
import { EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, ChainData } from "contracts/interfaces/ICentralRegistry.sol";

contract FeeAccumulator is ReentrancyGuard {
    /// TYPES ///

    /// @param isRewardToken Whether an address is the reward token or not.
    ///                      2 = yes; 0 or 1 = no.
    /// @param forOTC Whether a token should be held back for DAO OTC or not.
    ///               2 = yes; 0 or 1 = no.
    struct RewardToken {
        uint256 isRewardToken;
        uint256 forOTC;
    }

    struct LockData {
        uint224 lockAmount;
        uint16 epoch;
        uint16 chainId;
    }

    /// CONSTANTS ///

    /// @notice Address of fee token.
    address public immutable feeToken;
    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;
    /// @notice Address of OneBalanceFeeManager contract.
    address public immutable oneBalanceFeeManager;

    /// @notice Fee token decimal unit.
    uint256 internal immutable _feeTokenUnit;

    /// STORAGE ///

    /// @notice Cached Protocol Messaging Hub address.
    address internal _messagingHubStored;

    LockData[] public crossChainLockData;
    /// @notice We store token data semi redundantly to save gas
    ///         on daily operations and to help with gelato network structure
    ///         Used for Gelato Network bots to check what tokens to swap.
    address[] public rewardTokens;

    /// @notice Token Address => RewardToken data.
    mapping(address => RewardToken) public rewardTokenInfo;

    /// @notice ChainID => Epoch => 2 = yes; 0 = no.
    mapping(uint256 => mapping(uint256 => uint256)) public lockedTokenDataSent;

    /// ERRORS ///

    error FeeAccumulator__Unauthorized();
    error FeeAccumulator__OneBalanceFeeManagerIsZeroAddress();
    error FeeAccumulator__InvalidCentralRegistry();
    error FeeAccumulator__SwapDataAndTokenLengthMismatch(
        uint256 numSwapData,
        uint256 numTokens
    );
    error FeeAccumulator__SwapDataInputTokenIsNotCurrentToken(
        uint256 index,
        address inputToken,
        address currentToken
    );
    error FeeAccumulator__SwapDataOutputTokenIsNotFeeToken(
        uint256 index,
        address inputToken,
        address currentToken
    );
    error FeeAccumulator__SwapDataInvalidSwapper(
        uint256 index,
        address invalidSwapper
    );
    error FeeAccumulator__SwapDataCurrentTokenIsNotRewardToken(
        uint256 index,
        address currentToken
    );
    error FeeAccumulator__TokenIsNotEarmarked();
    error FeeAccumulator__ChainIsNotSupported();
    error FeeAccumulator__ToAddressIsNotMessagingHub(
        address cveAddress,
        address toAddress
    );
    error FeeAccumulator__ConfigurationError();
    error FeeAccumulator__CurrentEpochError(
        uint256 currentEpoch,
        uint256 nextEpochToDeliver
    );
    error FeeAccumulator__NewFeeAccumulatorIsNotChanged();
    error FeeAccumulator__TokenLengthIsZero();
    error FeeAccumulator__RemovalTokenIsNotRewardToken();
    error FeeAccumulator__RemovalTokenDoesNotExist();
    error FeeAccumulator__MessagingHubHasNotChanged();

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address oneBalanceFeeManager_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert FeeAccumulator__InvalidCentralRegistry();
        }
        if (oneBalanceFeeManager_ == address(0)) {
            revert FeeAccumulator__OneBalanceFeeManagerIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        feeToken = centralRegistry.feeToken();
        oneBalanceFeeManager = oneBalanceFeeManager_;
        _feeTokenUnit = 10 ** IERC20(feeToken).decimals();
        // We document this incase we ever need to update messaging hub
        // and want to revoke.
        _messagingHubStored = centralRegistry.protocolMessagingHub();

        // We infinite approve fee token so that protocol messaging hub
        // can drag funds to proper chain.
        SafeTransferLib.safeApprove(
            feeToken,
            _messagingHubStored,
            type(uint256).max
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Performs multiple token swaps in a single transaction, converting
    ///      the provided tokens to fee token on behalf of Curvance DAO.
    /// @param data Encoded swap data containing the details of each swap.
    /// @param tokens An array of token addresses corresponding to
    ///               the swap data, specifying the tokens to be swapped.
    function multiSwap(
        bytes calldata data,
        address[] calldata tokens
    ) external nonReentrant {
        if (!centralRegistry.isHarvester(msg.sender)) {
            revert FeeAccumulator__Unauthorized();
        }

        SwapperLib.Swap[] memory swapDataArray = abi.decode(
            data,
            (SwapperLib.Swap[])
        );

        uint256 numTokens = swapDataArray.length;
        if (numTokens != tokens.length) {
            revert FeeAccumulator__SwapDataAndTokenLengthMismatch(
                numTokens,
                tokens.length
            );
        }
        address currentToken;

        for (uint256 i; i < numTokens; ++i) {
            currentToken = tokens[i];
            // Make sure we are not earmarking this token for DAO OTC.
            if (rewardTokenInfo[currentToken].forOTC == 2) {
                continue;
            }
            if (rewardTokenInfo[currentToken].isRewardToken != 2) {
                revert FeeAccumulator__SwapDataCurrentTokenIsNotRewardToken(
                    i,
                    currentToken
                );
            }
            if (swapDataArray[i].inputToken != currentToken) {
                revert FeeAccumulator__SwapDataInputTokenIsNotCurrentToken(
                    i,
                    swapDataArray[i].inputToken,
                    currentToken
                );
            }
            if (swapDataArray[i].outputToken != feeToken) {
                revert FeeAccumulator__SwapDataOutputTokenIsNotFeeToken(
                    i,
                    swapDataArray[i].outputToken,
                    feeToken
                );
            }
            if (!centralRegistry.isSwapper(swapDataArray[i].target)) {
                revert FeeAccumulator__SwapDataInvalidSwapper(
                    i,
                    swapDataArray[i].target
                );
            }

            // Swap from token to output token (fee token).
            // Note: Because this is ran directly from Gelato Network we know
            //       we will not have a malicious actor on swap routing.
            //       We route liquidity to 1Inch with tight slippage
            //       requirement, meaning we do not need to separately check
            //       for slippage here.
            SwapperLib.swap(centralRegistry, swapDataArray[i]);
        }

        SafeTransferLib.safeTransfer(
            feeToken,
            oneBalanceFeeManager,
            (IERC20(feeToken).balanceOf(address(this)) * vaultCompoundFee()) /
                vaultYieldFee()
        );
    }

    /// @notice Performs an (OTC) operation for a specific token,
    ///         transferring the token to the DAO in exchange for fee token.
    /// @dev The function validates that the token is earmarked for OTC and
    ///      calculates the amount of fee token required based on the
    ///      current prices.
    /// @param tokenToOTC Address of the token to be OTC purchased by the DAO.
    /// @param amountToOTC Amount of the token to be OTC purchased by the DAO.
    function executeOTC(
        address tokenToOTC,
        uint256 amountToOTC
    ) external nonReentrant {
        _checkDaoPermissions();

        // Validate that the token is earmarked for OTC
        if (rewardTokenInfo[tokenToOTC].forOTC < 2) {
            revert FeeAccumulator__TokenIsNotEarmarked();
        }

        // Cache router to save gas
        IOracleRouter oracleRouter = IOracleRouter(
            centralRegistry.oracleRouter()
        );

        (uint256 priceSwap, uint256 errorCodeSwap) = oracleRouter.getPrice(
            tokenToOTC,
            true,
            true
        );
        (uint256 priceFeeToken, uint256 errorCodeFeeToken) = oracleRouter
            .getPrice(feeToken, true, true);

        // Validate we got prices back
        if (errorCodeFeeToken == 2 || errorCodeSwap == 2) {
            revert FeeAccumulator__ConfigurationError();
        }

        address daoAddress = centralRegistry.daoAddress();
        // Price Router always returns in 1e18 format based on decimals,
        // so we only need to worry about decimal differences here.
        uint256 feeTokenRequiredForOTC = (
            ((priceSwap * amountToOTC * _feeTokenUnit) / priceFeeToken)
        ) / 10 ** IERC20(tokenToOTC).decimals();

        SafeTransferLib.safeTransferFrom(
            feeToken,
            msg.sender,
            address(this),
            feeTokenRequiredForOTC
        );

        SafeTransferLib.safeTransfer(
            feeToken,
            oneBalanceFeeManager,
            (feeTokenRequiredForOTC * vaultCompoundFee()) / vaultYieldFee()
        );

        // Give DAO the OTC'd tokens
        SafeTransferLib.safeTransfer(tokenToOTC, daoAddress, amountToOTC);
    }

    /// @notice Sends veCVE locked token data to destination chain.
    /// @param dstChainId Destination chain ID where the message data
    ///                   should be sent.
    /// @param toAddress The destination address specified by `dstChainId`.
    function sendWormholeMessages(
        uint256 dstChainId,
        address toAddress
    ) external {
        if (!centralRegistry.isHarvester(msg.sender)) {
            revert FeeAccumulator__Unauthorized();
        }

        ICVELocker locker = ICVELocker(centralRegistry.cveLocker());
        uint256 epoch = locker.nextEpochToDeliver();

        if (lockedTokenDataSent[dstChainId][epoch] == 2) {
            return;
        }

        lockedTokenDataSent[dstChainId][epoch] = 2;

        ChainData memory chainData = centralRegistry.supportedChainData(
            dstChainId
        );

        if (chainData.isSupported < 2) {
            revert FeeAccumulator__ChainIsNotSupported();
        }

        if (chainData.messagingHub != toAddress) {
            revert FeeAccumulator__ToAddressIsNotMessagingHub(
                chainData.messagingHub,
                toAddress
            );
        }

        IVeCVE veCVE = IVeCVE(centralRegistry.veCVE());

        bytes memory payload = abi.encode(
            veCVE.chainPoints() - veCVE.chainUnlocksByEpoch(epoch)
        );

        IProtocolMessagingHub messagingHub = IProtocolMessagingHub(
            centralRegistry.protocolMessagingHub()
        );

        uint256 gas = messagingHub.quoteWormholeFee(dstChainId, false);

        messagingHub.sendWormholeMessages{ value: gas }(
            dstChainId,
            toAddress,
            payload
        );
    }

    /// @notice Receives and records the epoch rewards for CVE from
    ///         the protocol messaging hub.
    /// @param amount The rewards per CVE for the previous epoch.
    function receiveExecutableLockData(uint256 amount) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            revert FeeAccumulator__Unauthorized();
        }

        // We validate nextEpochToDeliver in receiveCrossChainLockData on
        // the chain calculating values.
        ICVELocker(centralRegistry.cveLocker()).recordEpochRewards(amount);
    }

    /// @notice Receives and processes cross-chain lock data for
    ///         the next undelivered epoch.
    /// @param data Struct containing ChainID and value, with extra room for
    ///             epoch, and number of chains.
    ///             This is to avoid stack too deep issues in the function.
    /// @dev This function handles cross-chain communication and
    ///      the coordination of fee routing, as well as recording and
    ///      reporting epoch rewards on those fees.
    ///      Uses both Layerzero and Stargate to execute all necessary actions.
    ///      If sufficient chains have reported, it calculates rewards,
    ///      notifies other chains, and executes crosschain fee routing.
    function receiveCrossChainLockData(
        EpochRolloverData memory data
    ) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            revert FeeAccumulator__Unauthorized();
        }

        ChainData memory chainData = centralRegistry.supportedChainData(
            data.chainId
        );
        if (chainData.isSupported < 2) {
            return;
        }

        uint256 epoch = ICVELocker(centralRegistry.cveLocker())
            .nextEpochToDeliver();

        _validateAndRecordChainData(
            data.value,
            data.chainId,
            crossChainLockData.length,
            epoch
        );
    }

    /// @notice Records a Curvance reward epoch, if all chains have been
    ///         recorded executes system wide reporting and distribution
    ///         to all chains within the Curvance Protocol system.
    function executeEpochFeeRouter(uint256 chainId) external {
        ICVELocker locker = ICVELocker(centralRegistry.cveLocker());
        uint256 epoch = locker.nextEpochToDeliver();

        if (locker.currentEpoch(block.timestamp) <= epoch) {
            revert FeeAccumulator__CurrentEpochError(
                locker.currentEpoch(block.timestamp),
                epoch
            );
        }

        ChainData memory chainData = centralRegistry.supportedChainData(
            chainId
        );
        if (chainData.isSupported < 2) {
            return;
        }

        uint256 numChainData = crossChainLockData.length;

        // If we have sufficient chains reported,
        // time to execute epoch fee routing.
        if (numChainData == centralRegistry.supportedChains()) {
            // Execute Fee Routing to each chain.
            uint256 epochRewardsPerCVE = _executeEpochFeeRouter(
                chainData,
                numChainData,
                epoch
            );

            IProtocolMessagingHub messagingHub = IProtocolMessagingHub(
                centralRegistry.protocolMessagingHub()
            );
            LockData memory lockData;
            uint256 gas;
            uint16 messagingChainId;

            // Notify the other chains of the per epoch rewards.
            for (uint256 i; i < numChainData; ) {
                lockData = crossChainLockData[i];
                chainData = centralRegistry.supportedChainData(
                    lockData.chainId
                );
                messagingChainId = centralRegistry.GETHToMessagingChainId(
                    uint256(lockData.chainId)
                );

                gas = messagingHub.quoteWormholeFee(
                    uint256(lockData.chainId),
                    false
                );

                messagingHub.sendWormholeMessages{ value: gas }(
                    uint256(lockData.chainId),
                    chainData.messagingHub,
                    abi.encode(epochRewardsPerCVE)
                );

                unchecked {
                    ++i;
                }
            }

            delete crossChainLockData;
        }
    }

    /// @notice Sends all left over fees to new fee accumulator.
    /// @dev This does not need to be permissioned as it pulls data
    ///      directly from the Central Registry meaning a malicious actor
    ///      cannot abuse this.
    function migrateFeeAccumulator() external {
        address newFeeAccumulator = centralRegistry.feeAccumulator();
        if (newFeeAccumulator == address(this)) {
            revert FeeAccumulator__NewFeeAccumulatorIsNotChanged();
        }

        address[] memory currentRewardTokens = rewardTokens;
        uint256 numTokens = currentRewardTokens.length;
        uint256 tokenBalance;

        // Send remaining fee tokens to new fee accumulator, if any.
        for (uint256 i; i < numTokens; ) {
            tokenBalance = IERC20(currentRewardTokens[i]).balanceOf(
                address(this)
            );

            if (tokenBalance > 0) {
                SafeTransferLib.safeTransfer(
                    currentRewardTokens[i],
                    newFeeAccumulator,
                    tokenBalance
                );
            }

            unchecked {
                ++i;
            }
        }

        tokenBalance = IERC20(feeToken).balanceOf(address(this));

        // Send remaining fee token to new fee accumulator, if any.
        if (tokenBalance > 0) {
            SafeTransferLib.safeTransfer(
                feeToken,
                newFeeAccumulator,
                tokenBalance
            );
        }
    }

    /// @notice Set status on whether a token should be earmarked to OTC.
    /// @param state 2 = earmarked; 0 or 1 = not earmarked.
    function setEarmarked(address token, bool state) external {
        _checkDaoPermissions();

        rewardTokenInfo[token].forOTC = state ? 2 : 1;
    }

    /// @notice Moves fee token approval to new messaging hub.
    /// @dev Removes prior messaging hub approval for maximum safety.
    function notifyUpdatedMessagingHub() external {
        if (msg.sender != address(centralRegistry)) {
            revert FeeAccumulator__Unauthorized();
        }

        address messagingHub = centralRegistry.protocolMessagingHub();

        if (messagingHub == _messagingHubStored) {
            revert FeeAccumulator__MessagingHubHasNotChanged();
        }

        // Revoke previous approval.
        SafeTransferLib.safeApprove(feeToken, _messagingHubStored, 0);

        // We infinite approve fee token so that protocol messaging hub can
        // drag funds to proper chain.
        SafeTransferLib.safeApprove(feeToken, messagingHub, type(uint256).max);

        _messagingHubStored = messagingHub;
    }

    /// @notice Adds multiple reward tokens to the contract for Gelato Network
    ///         to read.
    /// @dev Does not fail on duplicate token, merely skips it and continues.
    /// @param newTokens Array of token addresses to be added as reward
    ///                  tokens.
    function addRewardTokens(address[] calldata newTokens) external {
        _checkDaoPermissions();

        uint256 numTokens = newTokens.length;
        if (numTokens == 0) {
            revert FeeAccumulator__TokenLengthIsZero();
        }

        for (uint256 i; i < numTokens; ++i) {
            // If we already support the token just skip it.
            if (rewardTokenInfo[newTokens[i]].isRewardToken == 2) {
                continue;
            }

            // Add reward token data to both rewardTokenInfo
            // and rewardTokenData.
            _addRewardToken(newTokens[i]);
        }
    }

    /// @notice Removes a reward token from the contract data that
    ///         Gelato Network reads.
    /// @dev Will revert on unsupported token address.
    /// @param rewardTokenToRemove The address of the token to be removed.
    function removeRewardToken(address rewardTokenToRemove) external {
        _checkDaoPermissions();

        RewardToken storage tokenToRemove = rewardTokenInfo[
            rewardTokenToRemove
        ];
        if (tokenToRemove.isRewardToken != 2) {
            revert FeeAccumulator__RemovalTokenIsNotRewardToken();
        }

        address[] memory currentTokens = rewardTokens;
        uint256 numTokens = currentTokens.length;
        uint256 tokenIndex = numTokens;

        for (uint256 i; i < numTokens; ) {
            if (currentTokens[i] == rewardTokenToRemove) {
                // We found the token so break out of the loop.
                tokenIndex = i;
                break;
            }
            unchecked {
                ++i;
            }
        }

        // Subtract 1 from numTokens so we properly have the end index.
        if (tokenIndex == numTokens--) {
            // We were unable to find the token in the array,
            // so something is wrong and we need to revert.
            revert FeeAccumulator__RemovalTokenDoesNotExist();
        }

        // Copy last item in list to location of item to be removed.
        address[] storage currentList = rewardTokens;
        // Copy the last token index slot to tokenIndex.
        currentList[tokenIndex] = currentList[numTokens];
        // Remove the last element.
        currentList.pop();

        // Now delete the reward token support flag from mapping.
        tokenToRemove.isRewardToken = 1;
    }

    /// @notice Retrieves the balances of all reward tokens currently held by
    ///         the Fee Accumulator.
    /// @return tokenBalances An array of uint256 values,
    ///         representing the current balances of each reward token.
    function getRewardTokenBalances()
        external
        view
        returns (uint256[] memory)
    {
        address[] memory currentTokens = rewardTokens;
        uint256 numTokens = currentTokens.length;
        uint256[] memory tokenBalances = new uint256[](numTokens);

        for (uint256 i; i < numTokens; ) {
            tokenBalances[i] = IERC20(currentTokens[i]).balanceOf(
                address(this)
            );

            unchecked {
                ++i;
            }
        }

        return tokenBalances;
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Fetches the current price router from the central registry.
    /// @return Current OracleRouter interface address.
    function getOracleRouter() public view returns (IOracleRouter) {
        return IOracleRouter(centralRegistry.oracleRouter());
    }

    /// @notice Vault compound fee is in basis point form.
    /// @dev Returns the vaults current amount of yield used
    ///      for compounding rewards.
    function vaultCompoundFee() public view returns (uint256) {
        return centralRegistry.protocolCompoundFee();
    }

    /// @notice Vault yield fee is in basis point form.
    /// @dev Returns the vaults current protocol fee for compounding rewards.
    function vaultYieldFee() public view returns (uint256) {
        return centralRegistry.protocolYieldFee();
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Adds `newToken` to `rewardTokens` array and
    ///         rewardTokenInfo mapping so gelato network knows a new token
    ///         has been added.
    function _addRewardToken(address newToken) internal {
        rewardTokens.push() = newToken;
        // Configure for isRewardToken = true and forOTC = false,
        // if the DAO wants to accumulate reward tokens it will need to be
        // passed by protocol governance.
        rewardTokenInfo[newToken] = RewardToken({
            isRewardToken: 2,
            forOTC: 1
        });
    }

    /// @notice Validates the inbound chain data and records it in the
    ///         crossChainLockData.
    /// @param value The locked amount value to record.
    /// @param chainId The ID of the chain where the data is coming from.
    /// @param numChainData Number of data entries in the crossChainLockData.
    /// @param epoch The current epoch number.
    /// @dev This function also serves the purpose of validating that
    ///      the current data structure. If the data is stale or a repeat
    ///      of the same chain, it resets and starts over.
    function _validateAndRecordChainData(
        uint256 value,
        uint256 chainId,
        uint256 numChainData,
        uint256 epoch
    ) internal {
        if (numChainData > 0) {
            for (uint256 i; i < numChainData; ) {
                // If somehow the data is stale or we are repeat adding
                // the same chain, reset and start over.
                if (
                    crossChainLockData[i].epoch < epoch ||
                    crossChainLockData[i].chainId == chainId
                ) {
                    delete crossChainLockData;
                    break;
                }

                unchecked {
                    ++i;
                }
            }
        }

        // Add the new chain recorded data.
        crossChainLockData.push() = LockData({
            lockAmount: uint224(value),
            epoch: uint16(epoch),
            chainId: uint16(chainId)
        });
    }

    /// @notice Executes a Curvance reward epoch, by recording rewards on this
    ///         chain and then distributing information and rewards to all
    ///         other chains within the system.
    /// @param chainData Struct containing chain data to cache execution
    ///                  instructions.
    /// @param numChains The number of chains to distribute rewards to.
    /// @param epoch The epoch to distribute rewards for.
    /// @return The rewards this epoch for having 1 CVE locked as veCVE,
    ///         in reward tokens in `WAD` form.
    function _executeEpochFeeRouter(
        ChainData memory chainData,
        uint256 numChains,
        uint256 epoch
    ) internal returns (uint256) {
        IProtocolMessagingHub messagingHub = IProtocolMessagingHub(
            centralRegistry.protocolMessagingHub()
        );

        IVeCVE veCVE = IVeCVE(centralRegistry.veCVE());
        uint256 lockedTokens = (veCVE.chainPoints() -
            veCVE.chainUnlocksByEpoch(epoch));

        uint256 totalLockedTokens = lockedTokens;

        // Record this chains reward data and prep remaining data for
        // other chains.
        for (uint256 i; i < numChains; ) {
            totalLockedTokens += crossChainLockData[i].lockAmount;

            unchecked {
                ++i;
            }
        }

        uint256 feeTokenBalance = IERC20(feeToken).balanceOf(address(this));

        // In terms of funds inside fee accumulator, 1/16 or 6.25% of fee token
        // should be sent and deposited to Gelato 1Balance on polygon.
        SafeTransferLib.safeTransfer(
            feeToken,
            oneBalanceFeeManager,
            (feeTokenBalance * vaultCompoundFee()) /
                centralRegistry.protocolHarvestFee()
        );

        feeTokenBalance = IERC20(feeToken).balanceOf(address(this));

        uint256 chainId;
        uint256 feeTokenBalanceForChain;

        // Messaging Hub can pull fee token directly so we do not
        // need to queue up any safe transfers.
        for (uint256 i; i < numChains; ) {
            chainId = crossChainLockData[i].chainId;
            chainData = centralRegistry.supportedChainData(chainId);
            feeTokenBalanceForChain =
                (feeTokenBalance * crossChainLockData[i].lockAmount) /
                totalLockedTokens;

            messagingHub.sendFees(
                chainId,
                chainData.messagingHub,
                feeTokenBalanceForChain
            );

            unchecked {
                ++i;
            }
        }

        feeTokenBalanceForChain =
            (feeTokenBalance * lockedTokens) /
            totalLockedTokens;
        uint256 epochRewardsPerCVE = (feeTokenBalance * WAD) /
            totalLockedTokens;

        ICVELocker locker = ICVELocker(centralRegistry.cveLocker());

        // If the locker is shutdown, transfer fees to DAO
        // instead of recording epoch rewards.
        if (locker.isShutdown() == 2) {
            SafeTransferLib.safeTransfer(
                feeToken,
                centralRegistry.daoAddress(),
                feeTokenBalanceForChain
            );
            return epochRewardsPerCVE;
        }

        // Transfer fees to locker and record newest epoch rewards.
        SafeTransferLib.safeTransfer(
            feeToken,
            address(locker),
            feeTokenBalanceForChain
        );
        ICVELocker(locker).recordEpochRewards(epochRewardsPerCVE);

        return epochRewardsPerCVE;
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert FeeAccumulator__Unauthorized();
        }
    }
}
