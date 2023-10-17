// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICVE, LzCallParams } from "contracts/interfaces/ICVE.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IGelatoOneBalance } from "contracts/interfaces/IGelatoOneBalance.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { IProtocolMessagingHub, PoolData } from "contracts/interfaces/IProtocolMessagingHub.sol";
import { LzTxObj } from "contracts/interfaces/layerzero/IStargateRouter.sol";
import { EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, ChainData } from "contracts/interfaces/ICentralRegistry.sol";

contract FeeAccumulator is ReentrancyGuard {
    /// TYPES ///

    struct RewardToken {
        uint256 isRewardToken; // 2 = yes; 0 or 1 = no
        uint256 forOTC;
    }

    struct LockData {
        uint224 lockAmount;
        uint16 epoch;
        uint16 chainId;
    }

    /// CONSTANTS ///

    /// @notice Scalar for math
    uint256 public constant EXP_SCALE = 1e18;
    uint256 public constant SLIPPED_MINIMUM = 9500; // 5%
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;
    /// @notice Address of fee token
    address public immutable feeToken;
    /// @notice Fee token decimal unit
    uint256 internal immutable _feeTokenUnit;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    /// @notice Address of Gelato 1Balance
    IGelatoOneBalance public gelatoOneBalance;
    address internal _previousMessagingHub;
    uint256 internal _gasForCalldata;
    uint256 internal _gasForCrosschain;

    LockData[] public crossChainLockData;
    /// @dev We store token data semi redundantly to save gas
    ///      on daily operations and to help with gelato network structure
    ///      Used for Gelato Network bots to check what tokens to swap
    address[] public rewardTokens;

    mapping(address => RewardToken) public rewardTokenInfo;
    /// @dev 2 = yes;
    mapping(uint16 => mapping(uint256 => uint256)) public lockedTokenDataSent;

    /// ERRORS ///

    error FeeAccumulator__Unauthorized();
    error FeeAccumulator__FeeTokenIsZeroAddress();
    error FeeAccumulator__ConfigurationError();
    error FeeAccumulator__EarmarkError();

    /// MODIFIERS ///

    modifier onlyDaoPermissions() {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert FeeAccumulator__Unauthorized();
        }
        _;
    }

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address feeToken_,
        uint256 gasForCalldata_,
        uint256 gasForCrosschain_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert FeeAccumulator__ConfigurationError();
        }
        if (feeToken_ == address(0)) {
            revert FeeAccumulator__FeeTokenIsZeroAddress();
        }

        centralRegistry = centralRegistry_;
        feeToken = feeToken_;
        _feeTokenUnit = 10 ** IERC20(feeToken_).decimals();
        _gasForCalldata = gasForCalldata_;
        _gasForCrosschain = gasForCrosschain_;

        // We document this incase we ever need to update messaging hub
        // and want to revoke
        _previousMessagingHub = centralRegistry.protocolMessagingHub();

        // We set oneBalance address initially to DAO,
        // incase direct deposits to Gelato Network are not supported.
        gelatoOneBalance = IGelatoOneBalance(centralRegistry.daoAddress());

        // We infinite approve fee token so that gelato one balance
        // can drag funds to proper chain
        SafeTransferLib.safeApprove(
            feeToken,
            address(gelatoOneBalance),
            type(uint256).max
        );

        // We infinite approve fee token so that protocol messaging hub
        // can drag funds to proper chain
        SafeTransferLib.safeApprove(
            feeToken,
            _previousMessagingHub,
            type(uint256).max
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @dev Performs multiple token swaps in a single transaction, converting
    ///      the provided tokens to fee token on behalf of Curvance DAO
    /// @param data Encoded swap data containing the details of each swap
    /// @param tokens An array of token addresses corresponding to
    ///               the swap data, specifying the tokens to be swapped
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
            revert FeeAccumulator__ConfigurationError();
        }
        address currentToken;

        for (uint256 i; i < numTokens; ++i) {
            currentToken = tokens[i];
            if (swapDataArray[i].inputToken != currentToken) {
                revert FeeAccumulator__ConfigurationError();
            }
            if (swapDataArray[i].outputToken != feeToken) {
                revert FeeAccumulator__ConfigurationError();
            }
            if (!centralRegistry.isSwapper(swapDataArray[i].target)) {
                revert FeeAccumulator__ConfigurationError();
            }
            // Make sure we are not earmarking this token for DAO OTC
            if (rewardTokenInfo[currentToken].forOTC == 2) {
                continue;
            }
            if (rewardTokenInfo[currentToken].isRewardToken != 2) {
                revert FeeAccumulator__ConfigurationError();
            }

            // Swap from token to output token (fee token)
            // Note: Because this is ran directly from Gelato Network we know
            //       we will not have a malicious actor on swap routing
            //       We route liquidity to 1Inch with tight slippage
            //       requirement, meaning we do not need to separately check
            //       for slippage here.
            SwapperLib.swap(swapDataArray[i]);
        }

        // Transfer fees to Gelato Network One Balance or equivalent
        gelatoOneBalance.depositToken(
            address(this),
            IERC20(feeToken),
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
    ) external onlyDaoPermissions nonReentrant {
        // Validate that the token is earmarked for OTC
        if (rewardTokenInfo[tokenToOTC].forOTC < 2) {
            revert FeeAccumulator__EarmarkError();
        }

        // Cache router to save gas
        IPriceRouter PriceRouter = IPriceRouter(centralRegistry.priceRouter());

        (uint256 priceSwap, uint256 errorCodeSwap) = PriceRouter.getPrice(
            tokenToOTC,
            true,
            true
        );
        (uint256 priceFeeToken, uint256 errorCodeFeeToken) = PriceRouter
            .getPrice(feeToken, true, true);

        // Validate we got prices back
        if (errorCodeFeeToken == 2 || errorCodeSwap == 2) {
            revert FeeAccumulator__ConfigurationError();
        }

        address daoAddress = centralRegistry.daoAddress();
        // Price Router always returns in 1e18 format based on decimals,
        // so we only need to worry about decimal differences here
        uint256 feeTokenRequiredForOTC = (
            ((priceSwap * amountToOTC * _feeTokenUnit) / priceFeeToken)
        ) / 10 ** IERC20(tokenToOTC).decimals();

        SafeTransferLib.safeTransferFrom(
            feeToken,
            msg.sender,
            address(this),
            feeTokenRequiredForOTC
        );

        // Transfer fees to Gelato Network One Balance or equivalent
        gelatoOneBalance.depositToken(
            address(this),
            IERC20(feeToken),
            (feeTokenRequiredForOTC * vaultCompoundFee()) / vaultYieldFee()
        );

        // Give DAO the OTC'd tokens
        SafeTransferLib.safeTransfer(tokenToOTC, daoAddress, amountToOTC);
    }

    function sendLockedTokenData(
        uint16 dstChainId,
        bytes32 toAddress
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
            revert FeeAccumulator__ConfigurationError();
        }

        if (chainData.cveAddress != toAddress) {
            revert FeeAccumulator__ConfigurationError();
        }

        ICVE CVE = ICVE(centralRegistry.CVE());
        IVeCVE veCVE = IVeCVE(centralRegistry.veCVE());
        uint16 version = 1;

        bytes memory payload = abi.encode(
            veCVE.chainPoints() - veCVE.chainUnlocksByEpoch(epoch)
        );

        uint256 gas = CVE.estimateSendAndCallFee(
            uint16(dstChainId),
            chainData.cveAddress,
            0,
            payload,
            uint64(_gasForCalldata),
            false,
            abi.encodePacked(version, _gasForCrosschain)
        );

        IProtocolMessagingHub(centralRegistry.protocolMessagingHub())
            .sendLockedTokenData{ value: gas }(
            uint16(dstChainId),
            chainData.cveAddress,
            payload,
            uint64(_gasForCalldata),
            LzCallParams({
                refundAddress: payable(address(this)),
                zroPaymentAddress: address(0),
                adapterParams: abi.encodePacked(version, _gasForCrosschain)
            }),
            gas
        );
    }

    /// @notice Receives and records the epoch rewards for CVE from
    ///         the protocol messaging hub
    /// @param epochRewardsPerCVE The rewards per CVE for the previous epoch
    function receiveExecutableLockData(uint256 epochRewardsPerCVE) external {
        if (msg.sender != centralRegistry.protocolMessagingHub()) {
            revert FeeAccumulator__Unauthorized();
        }

        ICVELocker locker = ICVELocker(centralRegistry.cveLocker());
        // We validate nextEpochToDeliver in receiveCrossChainLockData on
        // the chain calculating values
        locker.recordEpochRewards(
            locker.nextEpochToDeliver(),
            epochRewardsPerCVE
        );
    }

    /// @notice Receives and processes cross-chain lock data for
    ///         the next undelivered epoch
    /// @param data Struct containing ChainID and value, with extra room for
    ///             epoch, and number of chains
    ///             This is to avoid stack too deep issues in the function
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

    function executeEpochFeeRouter(EpochRolloverData memory data) external {
        ChainData memory chainData = centralRegistry.supportedChainData(
            data.chainId
        );
        if (chainData.isSupported < 2) {
            return;
        }

        data.numChainData = crossChainLockData.length;
        data.epoch = ICVELocker(centralRegistry.cveLocker())
            .nextEpochToDeliver();

        // If we have sufficient chains reported,
        // time to execute epoch fee routing
        if ((++data.numChainData) == centralRegistry.supportedChains()) {
            // Execute Fee Routing to each chain
            uint256 epochRewardsPerCVE = _executeEpochFeeRouter(
                chainData,
                data.numChainData,
                data.epoch
            );

            ICVE CVE = ICVE(centralRegistry.CVE());
            IProtocolMessagingHub messagingHub = IProtocolMessagingHub(
                centralRegistry.protocolMessagingHub()
            );
            LockData memory lockData;
            uint16 version = 1;

            // Notify the other chains of the per epoch rewards
            for (uint256 i; i < data.numChainData; ) {
                lockData = crossChainLockData[i];
                chainData = centralRegistry.supportedChainData(
                    lockData.chainId
                );
                data.chainId = centralRegistry.GETHToMessagingChainId(
                    lockData.chainId
                );
                data.value = CVE.estimateSendAndCallFee(
                    uint16(data.chainId),
                    chainData.cveAddress,
                    0,
                    abi.encode(epochRewardsPerCVE),
                    uint64(_gasForCalldata),
                    false,
                    abi.encodePacked(version, _gasForCrosschain)
                );

                messagingHub.sendLockedTokenData{ value: data.value }(
                    uint16(data.chainId),
                    chainData.cveAddress,
                    abi.encode(epochRewardsPerCVE),
                    uint64(_gasForCalldata),
                    LzCallParams({
                        refundAddress: payable(address(this)),
                        zroPaymentAddress: address(0),
                        adapterParams: abi.encodePacked(
                            version,
                            _gasForCrosschain
                        )
                    }),
                    data.value
                );

                unchecked {
                    ++i;
                }
            }

            delete crossChainLockData;
        }
    }

    /// @notice Sends all left over fees to new fee accumulator
    /// @dev This does not need to be permissioned as it pulls data
    ///      directly from the Central Registry meaning a malicious actor
    ///      cannot abuse this
    function migrateFeeAccumulator() external {
        address newFeeAccumulator = centralRegistry.feeAccumulator();
        if (newFeeAccumulator == address(this)) {
            revert FeeAccumulator__ConfigurationError();
        }

        address[] memory currentRewardTokens = rewardTokens;
        uint256 numTokens = currentRewardTokens.length;
        uint256 tokenBalance;

        // Send remaining fee tokens to new fee accumulator, if any
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

        // Send remaining fee token to new fee accumulator, if any
        if (tokenBalance > 0) {
            SafeTransferLib.safeTransfer(
                feeToken,
                newFeeAccumulator,
                tokenBalance
            );
        }
    }

    /// @notice Set Gelato Network one balance destination address to
    ///         fund compounders
    function setOneBalanceAddress(
        address newGelatoOneBalance
    ) external onlyDaoPermissions {
        // Revoke previous approval
        SafeTransferLib.safeApprove(feeToken, address(gelatoOneBalance), 0);

        gelatoOneBalance = IGelatoOneBalance(newGelatoOneBalance);

        // We infinite approve fee token so that gelato one balance
        // can drag funds to proper chain
        SafeTransferLib.safeApprove(
            feeToken,
            newGelatoOneBalance,
            type(uint256).max
        );
    }

    /// @notice Set status on whether a token should be earmarked to OTC
    /// @param state 2 = earmarked; 0 or 1 = not earmarked
    function setEarmarked(
        address token,
        bool state
    ) external onlyDaoPermissions {
        rewardTokenInfo[token].forOTC = state ? 2 : 1;
    }

    function setGasParameters(
        uint256 gasForCalldata,
        uint256 gasForCrosschain
    ) external onlyDaoPermissions {
        _gasForCalldata = gasForCalldata;
        _gasForCrosschain = gasForCrosschain;
    }

    /// @notice Moves fee token approval to new messaging hub
    /// @dev Removes prior messaging hub approval for maximum safety
    function requeryMessagingHub() external onlyDaoPermissions {
        // Revoke previous approval
        SafeTransferLib.safeApprove(feeToken, _previousMessagingHub, 0);

        address messagingHub = centralRegistry.protocolMessagingHub();

        // We infinite approve fee token so that protocol messaging hub can
        // drag funds to proper chain
        SafeTransferLib.safeApprove(feeToken, messagingHub, type(uint256).max);

        _previousMessagingHub = messagingHub;
    }

    /// @notice Adds multiple reward tokens to the contract for Gelato Network
    ///         to read.
    /// @dev Does not fail on duplicate token, merely skips it and continues
    /// @param newTokens Array of token addresses to be added as reward tokens
    function addRewardTokens(
        address[] calldata newTokens
    ) external onlyDaoPermissions {
        uint256 numTokens = newTokens.length;
        if (numTokens == 0) {
            revert FeeAccumulator__ConfigurationError();
        }

        for (uint256 i; i < numTokens; ++i) {
            // If we already support the token just skip it
            if (rewardTokenInfo[newTokens[i]].isRewardToken == 2) {
                continue;
            }

            // Add reward token data to both rewardTokenInfo & rewardTokenData
            _addRewardToken(newTokens[i]);
        }
    }

    /// @notice Removes a reward token from the contract data that
    ///         Gelato Network reads
    /// @dev    Will revert on unsupported token address
    /// @param rewardTokenToRemove The address of the token to be removed
    function removeRewardToken(
        address rewardTokenToRemove
    ) external onlyDaoPermissions {
        RewardToken storage tokenToRemove = rewardTokenInfo[
            rewardTokenToRemove
        ];
        if (tokenToRemove.isRewardToken != 2) {
            revert FeeAccumulator__ConfigurationError();
        }

        address[] memory currentTokens = rewardTokens;
        uint256 numTokens = currentTokens.length;
        uint256 tokenIndex = numTokens;

        for (uint256 i; i < numTokens; ) {
            if (currentTokens[i] == rewardTokenToRemove) {
                // We found the token so break out of loop
                tokenIndex = i;
                break;
            }
            unchecked {
                ++i;
            }
        }

        // subtract 1 from numTokens so we properly have the end index
        if (tokenIndex == numTokens--) {
            // we were unable to find the token in the array,
            // so something is wrong and we need to revert
            revert FeeAccumulator__ConfigurationError();
        }

        // copy last item in list to location of item to be removed
        address[] storage currentList = rewardTokens;
        // copy the last token index slot to tokenIndex
        currentList[tokenIndex] = currentList[numTokens];
        // remove the last element
        currentList.pop();

        // Now delete the reward token support flag from mapping
        tokenToRemove.isRewardToken = 1;
    }

    /// @notice Retrieves the balances of all reward tokens currently held by
    ///         the Fee Accumulator
    /// @return tokenBalances An array of uint256 values,
    ///         representing the current balances of each reward token
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

    /// @notice Fetches the current price router from the central registry
    /// @return Current PriceRouter interface address
    function getPriceRouter() public view returns (IPriceRouter) {
        return IPriceRouter(centralRegistry.priceRouter());
    }

    /// @notice Vault compound fee is in basis point form
    /// @dev Returns the vaults current amount of yield used
    ///      for compounding rewards
    function vaultCompoundFee() public view returns (uint256) {
        return centralRegistry.protocolCompoundFee();
    }

    /// @notice Vault yield fee is in basis point form
    /// @dev Returns the vaults current protocol fee for compounding rewards
    function vaultYieldFee() public view returns (uint256) {
        return centralRegistry.protocolYieldFee();
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Adds `newToken` to `rewardTokens` array and
    ///         rewardTokenInfo mapping so gelato network knows a new token
    ///         has been added
    function _addRewardToken(address newToken) internal {
        rewardTokens.push() = newToken;
        // Configure for isRewardToken = true and forOTC = false,
        // if the DAO wants to accumulate reward tokens it will need to be
        // passed by protocol governance
        rewardTokenInfo[newToken] = RewardToken({
            isRewardToken: 2,
            forOTC: 1
        });
    }

    /// @notice Validates the inbound chain data and records it in the
    ///         crossChainLockData
    /// @param value The locked amount value to record
    /// @param chainId The ID of the chain where the data is coming from
    /// @param numChainData Number of data entries in the crossChainLockData
    /// @param epoch The current epoch number
    /// @dev This function also serves the purpose of validating that
    ///      the current data structure
    ///      If the data is stale or a repeat of the same chain, it resets and
    ///      starts over.
    function _validateAndRecordChainData(
        uint256 value,
        uint256 chainId,
        uint256 numChainData,
        uint256 epoch
    ) internal {
        if (numChainData > 0) {
            for (uint256 i; i < numChainData; ) {
                // If somehow the data is stale or we are repeat adding
                // the same chain, reset and start over
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

        // Add the new chain recorded data
        crossChainLockData.push() = LockData({
            lockAmount: uint224(value),
            epoch: uint16(epoch),
            chainId: uint16(chainId)
        });
    }

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
        // other chains
        for (uint256 i; i < numChains; ) {
            totalLockedTokens += crossChainLockData[i].lockAmount;

            unchecked {
                ++i;
            }
        }

        uint256 feeTokenBalance = IERC20(feeToken).balanceOf(address(this));
        uint256 feeTokenBalanceForChain;

        // Messaging Hub can pull fee token directly so we do not
        // need to queue up any safe transfers
        for (uint256 i; i < numChains; ) {
            chainData = centralRegistry.supportedChainData(
                crossChainLockData[i].chainId
            );
            feeTokenBalanceForChain =
                (feeTokenBalance * crossChainLockData[i].lockAmount) /
                totalLockedTokens;

            messagingHub.sendFees(
                chainData.messagingHub,
                PoolData({
                    dstChainId: centralRegistry.GETHToMessagingChainId(
                        crossChainLockData[i].chainId
                    ),
                    srcPoolId: chainData.asSourceAux,
                    dstPoolId: chainData.asDestinationAux,
                    amountLD: feeTokenBalanceForChain,
                    minAmountLD: (feeTokenBalanceForChain * SLIPPED_MINIMUM) /
                        SLIPPAGE_DENOMINATOR
                }),
                LzTxObj({
                    dstGasForCall: 0,
                    dstNativeAmount: 0,
                    dstNativeAddr: ""
                }),
                ""
            );

            unchecked {
                ++i;
            }
        }

        feeTokenBalanceForChain =
            (feeTokenBalance * lockedTokens) /
            totalLockedTokens;
        uint256 epochRewardsPerCVE = (feeTokenBalance * EXP_SCALE) /
            totalLockedTokens;

        address locker = centralRegistry.cveLocker();

        SafeTransferLib.safeTransfer(
            feeToken,
            locker,
            feeTokenBalanceForChain
        );
        ICVELocker(locker).recordEpochRewards(epoch, epochRewardsPerCVE);

        return epochRewardsPerCVE;
    }
}
