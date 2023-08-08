// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { SwapperLib, IERC20 } from "contracts/libraries/SwapperLib.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";

import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";

contract FeeAccumulator is ReentrancyGuard {

    /// TYPES ///

    struct RewardToken {
        uint256 isRewardToken;
        uint256 forOTC;
    }

    /// CONSTANTS ///

    address public constant ETHER =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // pseudo ETH address
    IWETH public immutable WETH; // Address of WETH
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///

    address internal previousMessagingHub;
    address payable public oneBalanceAddress; 
    
    // We store token data semi redundantly to save gas
    // on daily operations and to help with gelato network structure
    address[] public rewardTokens; // Used for Gelato Network bots to check what tokens to swap
    mapping (address => RewardToken) public rewardTokenInfo; // 2 = yes; 0 or 1 = no

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
        address WETH_
    ) {
        if (!ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )){
                revert FeeAccumulator_ConfigurationError();
            }

        centralRegistry = centralRegistry_;
        WETH = IWETH(WETH_);
        // We document this incase we ever need to update messaging hub and want to revoke
        previousMessagingHub = centralRegistry.protocolMessagingHub();

        // We infinite approve WETH so that protocol messaging hub can drag funds to proper chain
        SafeTransferLib.safeApprove(
            WETH_,
            previousMessagingHub,
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
    function multiSwap(bytes calldata data, address[] calldata tokens) external onlyHarvestor nonReentrant {

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
        fees = fees - _distributeETH(oneBalanceAddress, (fees * vaultCompoundFee()) / vaultYieldFee());
        // Deposit remainder into WETH so protocol messaging hub can pull WETH to execute fee distribution
        WETH.deposit{ value: fees }(fees);
    }

    /// @notice Performs an (OTC) operation for a specific token, transferring the token to the DAO in exchange for ETH.
    /// @dev The function validates that the token is earmarked for OTC and calculates the amount of ETH required based on the current prices
    /// @param tokenToOTC The address of the token to be OTC purchased by the DAO
    /// @param amountToOTC The amount of the token to be OTC purchased by the DAO
    function executeOTC(address tokenToOTC, uint256 amountToOTC) external payable onlyDaoPermissions nonReentrant {

        // Validate that the token is earmarked for OTC
        if (rewardTokenInfo[tokenToOTC].forOTC < 2) {
            revert FeeAccumulator_EarmarkError();
        }

        // Cache router to save gas
        IPriceRouter router = getPriceRouter();
        
        (uint256 priceSwap, uint256 errorCodeSwap) = router.getPrice(tokenToOTC, true, true);
        (uint256 priceETH, uint256 errorCodeETH) = router.getPrice(ETHER, true, true);

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
        ethRequiredForOTC = ethRequiredForOTC - _distributeETH(oneBalanceAddress, (ethRequiredForOTC * vaultCompoundFee()) / vaultYieldFee());
        // Deposit remainder into WETH so protocol messaging hub can pull WETH to execute fee distribution
        WETH.deposit{ value: ethRequiredForOTC }(ethRequiredForOTC);

        // Give DAO the OTC'd tokens
        SafeTransferLib.safeTransfer(
            tokenToOTC,
            daoAddress,
            amountToOTC
        );

        // If there was excess make sure we reimburse the DAO
        if (msg.value > ethRequiredForOTC) {
            _distributeETH(payable(daoAddress), msg.value - ethRequiredForOTC);
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
            tokenBalance = IERC20(currentRewardTokens[i]).balanceOf(address(this));

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

    /// @notice Admin function to set Gelato Network one balance destination address to fund compounders
    function setOneBalanceAddress(address payable newOneBalanceAddress) external onlyDaoPermissions {
        oneBalanceAddress = newOneBalanceAddress;
    }

    /// @notice Admin function to set status on whether a token should be earmarked to OTC
    /// @param state 2 = earmarked; 0 or 1 = not earmarked
    function setEarmarked(address token, bool state) external onlyDaoPermissions {
        rewardTokenInfo[token].forOTC = state ? 2: 1;
    }

    /// @notice Moves WETH approval to new messaging hub
    /// @dev    Removes prior messaging hub approval for maximum safety
    function reQueryMessagingHub() external onlyDaoPermissions {
        // Revoke previous approval
        SafeTransferLib.safeApprove(
            address(WETH),
            previousMessagingHub,
            0
        );

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
    function addRewardTokens(address[] calldata newTokens) external onlyDaoPermissions {
        uint256 numTokens = newTokens.length;
        if (numTokens == 0) {
            revert FeeAccumulator_ConfigurationError();
        }

        for (uint256 i; i < numTokens; ++i){

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
    function removeRewardToken(address rewardTokenToRemove) external onlyDaoPermissions {
        RewardToken storage tokenToRemove = rewardTokenInfo[rewardTokenToRemove];
        if (tokenToRemove.isRewardToken != 2) {
            revert FeeAccumulator_ConfigurationError();
        }

        address[] memory currentTokens = rewardTokens;
        uint256 numTokens = currentTokens.length;
        uint256 tokenIndex = numTokens;

        for (uint256 i; i < numTokens; ){
            if (currentTokens[i] == rewardTokenToRemove){
                // We found the token so break out of loop
                tokenIndex = i;
                break;
            }
            unchecked {
                ++i;
            }
        }

        // subtract 1 from numTokens so we properly have the end index
        if (tokenIndex == numTokens--){
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
        rewardTokenInfo[newToken] = RewardToken({isRewardToken: 2, forOTC: 1});
    }

    /// @notice Retrieves the balances of all reward tokens currently held by the Fee Accumulator
    /// @return tokenBalances An array of uint256 values,
    ///         representing the current balances of each reward token
    function getRewardTokenBalances() external view returns (uint256[] memory) {
        address[] memory currentTokens = rewardTokens;
        uint256 numTokens = currentTokens.length;
        uint256[] memory tokenBalances = new uint256[](numTokens);

        for (uint256 i; i < numTokens; ) {
            tokenBalances[i] = IERC20(currentTokens[i]).balanceOf(address(this));

            unchecked {
                ++i;
            }
        }

        return tokenBalances;
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
               revert (0x1c,0x04)
            }
        }

        return amount;
    }

}
