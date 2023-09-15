// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SwapperLib, IERC20 } from "contracts/libraries/SwapperLib.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IWETH } from "contracts/interfaces/IWETH.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICVE, LzCallParams } from "contracts/interfaces/ICVE.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";
import { IProtocolMessagingHub, PoolData } from "contracts/interfaces/IProtocolMessagingHub.sol";
import { swapRouter, lzTxObj } from "contracts/interfaces/layerzero/IStargateRouter.sol";
import { EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { ICentralRegistry, ChainData } from "contracts/interfaces/ICentralRegistry.sol";

contract FeeAccumulator is ReentrancyGuard {
    /// TYPES ///

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

    address public constant ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // pseudo ETH address
    IWETH public immutable WETH; // Address of WETH
    uint256 public constant expScale = 1e18; // Scalar for math
    uint256 public constant SLIPPED_MINIMUM = 9500; // 5%
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///

    address internal _previousMessagingHub;
    address public router; // Address of Stargate Router
    address payable public oneBalanceAddress;
    uint256 internal _gasForCalldata;
    uint256 internal _gasForCrosschain;

    LockData[] public crossChainLockData;
    // We store token data semi redundantly to save gas
    // on daily operations and to help with gelato network structure
    address[] public rewardTokens; // Used for Gelato Network bots to check what tokens to swap
    mapping(address => RewardToken) public rewardTokenInfo; // 2 = yes; 0 or 1 = no

    /// ERRORS ///

    error FeeAccumulator_TransferFailed();
    error FeeAccumulator_ConfigurationError();
    error FeeAccumulator_InsufficientETH();
    error FeeAccumulator_EarmarkError();

    /// MODIFIERS ///

    modifier onlyHarvestor() {
        require(
            centralRegistry.isHarvester(msg.sender),
            "FeeAccumulator: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "FeeAccumulator: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyMessagingHub() {
        require(
            msg.sender == centralRegistry.protocolMessagingHub(),
            "FeeAccumulator: UNAUTHORIZED"
        );
        _;
    }

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address WETH_,
        address router_,
        uint256 gasForCalldata_,
        uint256 gasForCrosschain_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert FeeAccumulator_ConfigurationError();
        }

        centralRegistry = centralRegistry_;
        WETH = IWETH(WETH_);
        router = router_;
        _gasForCalldata = gasForCalldata_;
        _gasForCrosschain = gasForCrosschain_;

        // We document this incase we ever need to update messaging hub and want to revoke
        _previousMessagingHub = centralRegistry.protocolMessagingHub();

        // We infinite approve WETH so that protocol messaging hub can drag funds to proper chain
        SafeTransferLib.safeApprove(
            WETH_,
            _previousMessagingHub,
            type(uint256).max
        );

        // We set oneBalance address initially to DAO,
        // incase direct deposits to Gelato Network are not supported.
        oneBalanceAddress = payable(centralRegistry.daoAddress());
    }

    /// EXTERNAL FUNCTIONS ///

    /// @dev Performs multiple token swaps in a single transaction,
    ///      converting the provided tokens to ETH on behalf of Curvance DAO
    /// @param data Encoded swap data containing the details of each swap
    /// @param tokens An array of token addresses corresponding to the swap data, specifying the tokens to be swapped
    function multiSwap(
        bytes calldata data,
        address[] calldata tokens
    ) external onlyHarvestor nonReentrant {
        SwapperLib.Swap[] memory swapDataArray = abi.decode(
            data,
            (SwapperLib.Swap[])
        );

        uint256 numTokens = swapDataArray.length;
        if (numTokens != tokens.length) {
            revert FeeAccumulator_ConfigurationError();
        }
        address currentToken;

        for (uint256 i; i < numTokens; ++i) {
            currentToken = tokens[i];
            // Make sure we are not earmarking this token for DAO OTC
            if (rewardTokenInfo[currentToken].forOTC == 2) {
                continue;
            }

            // Swap from token to output token (ETH)
            // Note: Because this is ran directly from Gelato Network we know we will not have a malicious actor on swap routing
            //       We route liquidity to 1Inch with tight slippage requirement, meaning we do not need to separately check
            //       for slippage here.
            SwapperLib.swap(swapDataArray[i]);
        }

        uint256 fees = address(this).balance;
        // We do not need expScale since ether and fees are already in 1e18 form
        // Transfer fees to Gelato Network One Balance or equivalent
        fees =
            fees -
            _distributeETH(
                oneBalanceAddress,
                (fees * vaultCompoundFee()) / vaultYieldFee()
            );
        // Deposit remainder into WETH so protocol messaging hub can pull WETH to execute fee distribution
        WETH.deposit{ value: fees }();
    }

    /// @notice Performs an (OTC) operation for a specific token, transferring the token to the DAO in exchange for ETH.
    /// @dev The function validates that the token is earmarked for OTC and calculates the amount of ETH required based on the current prices
    /// @param tokenToOTC The address of the token to be OTC purchased by the DAO
    /// @param amountToOTC The amount of the token to be OTC purchased by the DAO
    function executeOTC(
        address tokenToOTC,
        uint256 amountToOTC
    ) external payable onlyDaoPermissions nonReentrant {
        // Validate that the token is earmarked for OTC
        if (rewardTokenInfo[tokenToOTC].forOTC < 2) {
            revert FeeAccumulator_EarmarkError();
        }

        // Cache router to save gas
        IPriceRouter PriceRouter = getPriceRouter();

        (uint256 priceSwap, uint256 errorCodeSwap) = PriceRouter.getPrice(
            tokenToOTC,
            true,
            true
        );
        (uint256 priceETH, uint256 errorCodeETH) = PriceRouter.getPrice(
            ETHER,
            true,
            true
        );

        // Validate we got prices back
        if (errorCodeETH == 2 || errorCodeSwap == 2) {
            revert FeeAccumulator_ConfigurationError();
        }

        address daoAddress = centralRegistry.daoAddress();
        // Price Router always returns in 1e18 format based on decimals,
        // so we do not need to worry about decimal differences here
        uint256 ethRequiredForOTC = (priceSwap * amountToOTC) / priceETH;

        // Validate enough ether has been provided
        if (msg.value < ethRequiredForOTC) {
            revert FeeAccumulator_InsufficientETH();
        }

        // We do not need expScale since ether and fees are already in 1e18 form
        // Transfer fees to Gelato Network One Balance or equivalent
        _distributeETH(
            oneBalanceAddress,
            (ethRequiredForOTC * vaultCompoundFee()) / vaultYieldFee()
        );
        // Deposit remainder into WETH so protocol messaging hub can pull WETH to execute fee distribution
        WETH.deposit{ value: ethRequiredForOTC }();

        // Give DAO the OTC'd tokens
        SafeTransferLib.safeTransfer(tokenToOTC, daoAddress, amountToOTC);

        // If there was excess make sure we reimburse the DAO
        if (msg.value > ethRequiredForOTC) {
            _distributeETH(payable(daoAddress), msg.value - ethRequiredForOTC);
        }
    }

    function sendLockedTokenData(
        uint16 dstChainId,
        bytes32 toAddress
    ) external onlyHarvestor {
        ChainData memory chainData = centralRegistry.supportedChainData(
            dstChainId
        );

        if (chainData.isSupported < 2) {
            revert FeeAccumulator_ConfigurationError();
        }

        if (chainData.cveAddress != toAddress) {
            revert FeeAccumulator_ConfigurationError();
        }
        ICVE CVE = ICVE(centralRegistry.CVE());
        address veCVE = centralRegistry.veCVE();
        uint16 version = 1;

        bytes memory payload = abi.encode(
            IVeCVE(veCVE).chainTokenPoints() -
                IVeCVE(veCVE).chainUnlocksByEpoch(
                    ICVELocker(centralRegistry.cveLocker())
                        .nextEpochToDeliver()
                )
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

    /// @notice Receives and records the epoch rewards for CVE from the protocol messaging hub
    /// @param epochRewardsPerCVE The rewards per CVE for the previous epoch
    function receiveExecutableLockData(
        uint256 epochRewardsPerCVE
    ) external onlyMessagingHub {
        ICVELocker locker = ICVELocker(centralRegistry.cveLocker());
        // We validate nextEpochToDeliver in receiveCrossChainLockData on the chain calculating values
        locker.recordEpochRewards(
            locker.nextEpochToDeliver(),
            epochRewardsPerCVE
        );
    }

    /// @notice Receives and processes cross-chain lock data for the next undelivered epoch
    /// @param data Struct containing ChainID and value, with extra room for epoch, and number of chains
    ///             this is to avoid stack too deep issues in the function
    /// @dev This function handles cross-chain communication and the coordination of fee routing,
    ///      as well as recording and reporting epoch rewards on those fees.
    ///      Uses both Layerzero and Stargate to execute all necessary actions. If sufficient chains have reported,
    ///      it calculates rewards, notifies other chains, and executes crosschain fee routing.
    function receiveCrossChainLockData(
        EpochRolloverData memory data
    ) external onlyMessagingHub {
        ChainData memory chainData = centralRegistry.supportedChainData(
            data.chainId
        );
        if (chainData.isSupported < 2) {
            return;
        }

        data.numChainData = crossChainLockData.length;
        data.epoch = ICVELocker(centralRegistry.cveLocker())
            .nextEpochToDeliver();

        _validateAndRecordChainData(
            data.value,
            data.chainId,
            data.numChainData,
            data.epoch
        );

        // If we have sufficient chains reported, time to execute epoch fee routing
        if ((++data.numChainData) == centralRegistry.supportedChains()) {
            // Execute Fee Routing to each chain and unwrap enough WETH to pay for LayerZero fees below
            uint256 epochRewardsPerCVE = _executeEpochFeeRouter(
                chainData,
                data.numChainData,
                data.epoch,
                data.chainId
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
                abi.encode(epochRewardsPerCVE);
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
    /// @dev    This does not need to be permissioned as it pulls data directly
    ///         from the Central Registry meaning a malicious actor cannot abuse this
    function migrateFeeAccumulator() external {
        address newFeeAccumulator = centralRegistry.feeAccumulator();
        if (newFeeAccumulator == address(this)) {
            revert FeeAccumulator_ConfigurationError();
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
        }

        tokenBalance = IERC20(address(WETH)).balanceOf(address(this));
        // Send remaining WETH to new fee accumulator, if any
        if (tokenBalance > 0) {
            SafeTransferLib.safeTransfer(
                address(WETH),
                newFeeAccumulator,
                tokenBalance
            );
        }

        // Send remaining ETH to new fee accumulator, if any
        if (address(this).balance > 0) {
            _distributeETH(payable(newFeeAccumulator), address(this).balance);
        }
    }

    /// @notice Admin function to set Stargate router destination address to route fees
    function setStargateAddress(
        address payable newOneBalanceAddress
    ) external onlyDaoPermissions {
        oneBalanceAddress = newOneBalanceAddress;
    }

    /// @notice Admin function to set Gelato Network one balance destination address to fund compounders
    function setOneBalanceAddress(
        address payable newOneBalanceAddress
    ) external onlyDaoPermissions {
        oneBalanceAddress = newOneBalanceAddress;
    }

    /// @notice Admin function to set status on whether a token should be earmarked to OTC
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
        _gasForCrosschain = gasForCalldata;
        _gasForCrosschain = gasForCrosschain;
    }

    /// @notice Moves WETH approval to new messaging hub
    /// @dev    Removes prior messaging hub approval for maximum safety
    function reQueryMessagingHub() external onlyDaoPermissions {
        // Revoke previous approval
        SafeTransferLib.safeApprove(address(WETH), _previousMessagingHub, 0);

        // We infinite approve WETH so that protocol messaging hub can drag funds to proper chain
        SafeTransferLib.safeApprove(
            address(WETH),
            centralRegistry.protocolMessagingHub(),
            type(uint256).max
        );
    }

    /// @notice Adds multiple reward tokens to the contract for Gelato Network to read.
    /// @dev    Does not fail on duplicate token, merely skips it and continues
    /// @param newTokens An array of token addresses to be added as reward tokens
    function addRewardTokens(
        address[] calldata newTokens
    ) external onlyDaoPermissions {
        uint256 numTokens = newTokens.length;
        if (numTokens == 0) {
            revert FeeAccumulator_ConfigurationError();
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

    /// @notice Removes a reward token from the contract data that Gelato Network reads
    /// @dev    Will revert on unsupported token address
    /// @param rewardTokenToRemove The address of the token to be removed
    function removeRewardToken(
        address rewardTokenToRemove
    ) external onlyDaoPermissions {
        RewardToken storage tokenToRemove = rewardTokenInfo[
            rewardTokenToRemove
        ];
        if (tokenToRemove.isRewardToken != 2) {
            revert FeeAccumulator_ConfigurationError();
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
            revert FeeAccumulator_ConfigurationError();
        }

        // copy last item in list to location of item to be removed
        address[] storage currentList = rewardTokens;
        // copy the last token index slot to tokenIndex
        currentList[tokenIndex] = currentList[numTokens];
        // remove the last element
        currentList.pop();

        // Now delete the reward token support flag from mapping
        delete tokenToRemove.isRewardToken;
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

    /// @notice Adds `newToken` to `rewardTokens` array and rewardTokenInfo mapping
    ///         so gelato network knows a new token has been added
    function _addRewardToken(address newToken) internal {
        rewardTokens.push() = newToken;
        // Configure for isRewardToken = true and forOTC = false,
        // if the DAO wants to accumulate reward tokens it will need to be passed
        // by protocol governance
        rewardTokenInfo[newToken] = RewardToken({
            isRewardToken: 2,
            forOTC: 1
        });
    }

    /// @notice Retrieves the balances of all reward tokens currently held by the Fee Accumulator
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

    /// @notice Validates the inbound chain data and records it in the crossChainLockData
    /// @param value The locked amount value to record
    /// @param chainId The ID of the chain where the data is coming from
    /// @param numChainData The number of data entries in the crossChainLockData
    /// @param epoch The current epoch number
    /// @dev This function also serves the purpose of validating that the current data structure,
    ///      if the data is stale or a repeat of the same chain, it resets and starts over.
    function _validateAndRecordChainData(
        uint256 value,
        uint256 chainId,
        uint256 numChainData,
        uint256 epoch
    ) internal {
        if (numChainData > 0) {
            for (uint256 i; i < numChainData; ) {
                // If somehow the data is stale or we are repeat adding the same chain,
                // reset and start over
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
        uint256 epoch,
        uint256 chainId
    ) internal returns (uint256 epochRewardsPerCVE) {
        uint256 feeBalance = IERC20(address(WETH)).balanceOf(address(this));
        IProtocolMessagingHub messagingHub = IProtocolMessagingHub(
            centralRegistry.protocolMessagingHub()
        );
        uint256 lockedTokens;

        {
            // Use scoping to avoid stack too deep
            bytes memory bytesAddress = new bytes(32);
            address feeEstimateAddress = chainData.messagingHub;
            assembly {
                mstore(add(bytesAddress, 32), feeEstimateAddress)
            }

            (uint256 stargateFees, ) = messagingHub.overEstimateStargateFee(
                swapRouter(router),
                1,
                bytesAddress,
                numChains
            );

            uint256 layerZeroFees = _overEstimateLZFees(
                chainData,
                chainId,
                numChains,
                ICVE(centralRegistry.CVE())
            );
            // Withdraw sufficient eth from WETH to cover layerzero fees
            WETH.withdraw(layerZeroFees);
            feeBalance = feeBalance - (stargateFees + layerZeroFees);

            IVeCVE veCVE = IVeCVE(centralRegistry.veCVE());
            lockedTokens = (veCVE.chainTokenPoints() -
                veCVE.chainUnlocksByEpoch(epoch));
        }

        uint256 totalLockedTokens = lockedTokens;

        // Record this chains reward data and prep remaining data for other chains
        for (uint256 i; i < numChains; ) {
            totalLockedTokens += crossChainLockData[i].lockAmount;

            unchecked {
                ++i;
            }
        }

        uint256 feeBalanceForChain;

        // Messaging Hub can pull WETH directly so we do not need to queue up any safe transfers
        for (uint256 i; i < numChains; ) {
            chainData = centralRegistry.supportedChainData(
                crossChainLockData[i].chainId
            );
            feeBalanceForChain =
                (feeBalance * crossChainLockData[i].lockAmount) /
                totalLockedTokens;

            messagingHub.sendFees(
                router,
                PoolData({
                    dstChainId: centralRegistry.GETHToMessagingChainId(
                        crossChainLockData[i].chainId
                    ),
                    srcPoolId: chainData.asSourceAux,
                    dstPoolId: chainData.asDestinationAux,
                    amountLD: feeBalanceForChain,
                    minAmountLD: (feeBalanceForChain * SLIPPED_MINIMUM) /
                        SLIPPAGE_DENOMINATOR
                }),
                lzTxObj({
                    dstGasForCall: 0,
                    dstNativeAmount: 0,
                    dstNativeAddr: ""
                }),
                ""
            );
        }

        feeBalanceForChain = (feeBalance * lockedTokens) / totalLockedTokens;
        epochRewardsPerCVE =
            (feeBalanceForChain * expScale) /
            totalLockedTokens;

        WETH.withdraw(feeBalanceForChain);

        address locker = centralRegistry.cveLocker();

        _distributeETH(payable(locker), feeBalanceForChain);
        ICVELocker(locker).recordEpochRewards(epoch, epochRewardsPerCVE);

        return epochRewardsPerCVE;
    }

    /// @notice Quotes gas cost for executing crosschain stargate swap
    /// @dev Intentionally greatly overestimates so we are sure that a multicall will not fail
    function _overEstimateLZFees(
        ChainData memory chainData,
        uint256 chainId,
        uint256 numChains,
        ICVE CVE
    ) internal view returns (uint256) {
        uint16 version = 1;
        if (block.chainid == 1) {
            return
                CVE.estimateSendAndCallFee(
                    uint16(centralRegistry.GETHToMessagingChainId(chainId)),
                    chainData.cveAddress,
                    0,
                    abi.encode(type(uint256).max),
                    uint64(_gasForCalldata),
                    false,
                    abi.encodePacked(version, _gasForCrosschain)
                ) *
                numChains *
                3;
        }

        // Calculate fees based on all chains being eth since thats infinitely more expensive
        return
            CVE.estimateSendAndCallFee(
                uint16(centralRegistry.GETHToMessagingChainId(1)),
                chainData.cveAddress,
                0,
                abi.encode(type(uint256).max),
                uint64(_gasForCalldata),
                false,
                abi.encodePacked(version, _gasForCrosschain)
            ) * numChains;
    }

    /// @notice Distributes the specified amount of ETH to
    ///         the recipient address
    /// @dev Has reEntry protection via multiSwap/daoOTC
    /// @param recipient The address to receive the ETH
    /// @param amount The amount of ETH to send
    /// @return amount The total amount of ETH that was sent
    function _distributeETH(
        address payable recipient,
        uint256 amount
    ) internal returns (uint256) {
        assembly {
            // Revert if we failed to transfer eth
            if iszero(call(gas(), recipient, amount, 0x00, 0x00, 0x00, 0x00)) {
                // bytes4(keccak256(bytes("FeeAccumulator_TransferFailed()")))
                mstore(0x00, 0x3595adc2)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }

        return amount;
    }
}
