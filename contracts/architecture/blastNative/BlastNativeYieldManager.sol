// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

import { IBlastCentralRegistry } from "contracts/interfaces/blast/IBlastCentralRegistry.sol";
import { IBlast } from "contracts/interfaces/external/blast/IBlast.sol";
import { IERC20Rebasing } from "contracts/interfaces/external/blast/IERC20Rebasing.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { IMarketManager, IMToken } from "contracts/interfaces/market/IMarketManager.sol";

/// @dev The Curvance Blast Native Yield Manager manages all delegated yield
///      inside the Curvance protocol. By design Curvance does not support
///      native ETH, but rather chooses to support WETH. This means that
///      BlastNativeYieldManager is built to engage with WETH, LPs, and Gas
///      refunds natively. USDB positions are also supported identically to
///      WETH to LPs may require special secondary logic dependant on the
///      dex/perp implementation of native yield. Curvance is currently built
///      with the expectation that yield inside LPs will naturally increase
///      through the `automatic` setting but secondary logic can be built into
///      Curvance is a dexes strategy differs.
contract BlastNativeYieldManager is ReentrancyGuard {
    /// CONSTANTS ///

    /// BLAST YIELD CONTRACTS ///

    /// @notice The address managing ETH/Gas yield.
    IBlast public constant CHAIN_YIELD_MANAGER = IBlast(0x4300000000000000000000000000000000000002);
    /// @notice The address managing WETH yield, also the token itself.
    /// @dev Will change when deploying to mainnet.
    IERC20Rebasing public constant WETH_YIELD_MANAGER = IERC20Rebasing(0x4200000000000000000000000000000000000023);
    /// @notice The address managing USDB yield, also the token itself.
    /// @dev Will change when deploying to mainnet.
    IERC20Rebasing public constant USDB_YIELD_MANAGER = IERC20Rebasing(0x4200000000000000000000000000000000000022);
    /// @notice Protocol epoch length.
    uint256 public constant EPOCH_WINDOW = 2 weeks;

    /// @notice Curvance DAO hub.
    IBlastCentralRegistry public immutable centralRegistry;

    /// @dev `bytes4(keccak256(bytes("BlastNativeYieldManager__Unauthorized()")))`
    uint256 internal constant _UNAUTHORIZED_SELECTOR = 0xf249dc1f;

    /// STORAGE ///

    /// @notice Whether a provided address is a Market Manager or not.
    /// @dev Address => is Market Manager.
    mapping(address => bool) public isMarketManager;

    /// @notice Whether there is a debt token that a cToken should donate
    ///         its native yield to.
    /// @dev cToken Address => dToken Address receiving additional rewards.
    mapping(address => address) public cTokenToDTokenYieldRouted;

    /// @notice The amount of pending WETH yield held for an address.
    /// @dev Address => Pending WETH yield.
    mapping(address => uint256) public pendingWETHYield;

    /// @notice The amount of pending USDB yield held for an address.
    /// @dev Address => Pending USDB yield.
    mapping(address => uint256) public pendingUSDBYield;

    /// @notice Address => Epoch => Was this epoch reported already.
    mapping(address => mapping(uint256 => bool)) public epochReported;

    /// ERRORS ///

    error BlastNativeYieldManager__Unauthorized();
    error BlastNativeYieldManager__NoYieldToClaim();
    error BlastNativeYieldManager__InvariantError();
    error BlastNativeYieldManager__InvalidTokenTypes();
    error BlastNativeYieldManager__MarketManagerMismatch();
    error BlastNativeYieldManager__InvalidCentralRegistry();
    error BlastNativeYieldManager__InvalidMarketManager();

    receive() external payable {}

    /// CONSTRUCTOR ///

    constructor(IBlastCentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(IBlastCentralRegistry).interfaceId
            )
        ) {
            revert BlastNativeYieldManager__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        address[] memory marketManagers = centralRegistry_.marketManagers();
        uint256 numMarkets = marketManagers.length;

        // Register any previously configured markets here, if any.
        for (uint256 i; i < numMarkets; ) {
            isMarketManager[marketManagers[i++]] = true;
        }

        // Set gas fees yield to claimable and then pass Governor
        // permissioning to Curvance DAO.
        CHAIN_YIELD_MANAGER.configureClaimableYield();
        CHAIN_YIELD_MANAGER.configureGovernor(centralRegistry_.daoAddress());

    }

    /// @notice Claims delegated yield on behalf of the caller. Will natively
    ///         revert if not delegated, works out of the box for any
    ///         protocol meaning anyone can benefit from the composable nature
    ///         of the smart contract.
    /// @dev Only callable by governee themself. Natively claims gas rebate.
    /// @param marketManager The Market Manager associated with the mToken
    ///                      managing it native yield.
    /// @param claimWETHYield Whether WETH native yield should be claimed.
    /// @param claimUSDBYield Whether USDB native yield should be claimed.
    /// @return WETHYield The amount of WETH yield claimed.
    /// @return USDBYield The amount of USDB yield claimed.
    function claimYieldForGauge(
        address marketManager,
        bool claimWETHYield,
        bool claimUSDBYield
    ) external nonReentrant returns (
        uint256 WETHYield,
        uint256 USDBYield
    ) {
        // Validate that `marketManager_` is configured as a market manager
        // inside the Yield Manager.
        if (!isMarketManager[marketManager]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Validate that the caller is a token listed inside the associated
        // Market Manager.
        if (!IMarketManager(marketManager).isListed(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 gasYield = CHAIN_YIELD_MANAGER.claimMaxGas(
            msg.sender,
            address(this)
        );
        uint256 WETHPrior = WETH_YIELD_MANAGER.balanceOf(address(this));
        uint256 USDBPrior = USDB_YIELD_MANAGER.balanceOf(address(this));
        uint256 WETHPerSecond;
        uint256 USDBPerSecond;

        address yieldDestination = cTokenToDTokenYieldRouted[msg.sender];

        // If the listed token is not currently routing its yield to another token,
        // route yield to itself.
        if (yieldDestination == address(0)) {
            yieldDestination = msg.sender;
        }

        if (gasYield > 0) {
            IWETH(address(WETH_YIELD_MANAGER)).deposit{ value: gasYield }();
            WETHYield += gasYield;
        }

        if (claimWETHYield) {
            uint256 pendingWETH = pendingWETHYield[msg.sender];

            // Recognize USDB yield, if necessary.
            if (pendingWETH > 0) {
                WETHYield += pendingWETH;
                WETHPerSecond = WETHYield / EPOCH_WINDOW;
            }
        }

        if (claimUSDBYield) {
            uint256 pendingUSDB = pendingUSDBYield[msg.sender];

            // Recognize USDB yield, if necessary.
            if (pendingUSDB > 0) {
                USDBYield += pendingUSDB;
                USDBPerSecond = USDBYield / EPOCH_WINDOW;
            }
        }

        // Validate yield was actually claimed.
        if (USDBYield == 0 && WETHYield == 0) {
            revert BlastNativeYieldManager__NoYieldToClaim();
        }

        // Cache Gauge Pool.
        IGaugePool gaugePool = IMarketManager(marketManager).gaugePool();
        uint256 nextEpoch = gaugePool.currentEpoch() + 1;

        // Validate that the Gauge Pool has not already set gauge rewards
        // for the next epoch.
        if (epochReported[msg.sender][nextEpoch]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Its theoretically possible that the rewards per second round down
        // if YIELD < EPOCH_WINDOW, this would mean that even if we did
        // stream it, the yield would be infinitesimal so we will just send
        // the dust back to DAO with the logic after check is performed.


        if (WETHPerSecond > 0){
            // Approve WETH to the Gauge Pool, if necessary.
            SwapperLib._approveTokenIfNeeded(
                address(WETH_YIELD_MANAGER),
                address(gaugePool),
                WETHYield
            );

            gaugePool.setRewardPerSec(
                yieldDestination,
                nextEpoch,
                address(WETH_YIELD_MANAGER),
                WETHPerSecond
            );

            // Remove any excess approval.
            SwapperLib._removeApprovalIfNeeded(
                address(WETH_YIELD_MANAGER),
                address(gaugePool)
            );
        }

        // Cache new WETH balance, its possible we received rewards back by
        // calling gauge system, or if no rewards were set because yield was
        // too low.
        uint256 WETHAfter = WETH_YIELD_MANAGER.balanceOf(address(this));

        // We offset the prior to what we expect to have been removed from
        // prior balance after streaming native yield via gauge system.
        WETHPrior -= WETHYield;

        if (WETHAfter != WETHPrior) {
            // If somehow the contract pulled more yield than allotted,
            // panic and kill the action.
            if (WETHAfter < WETHPrior) {
                revert BlastNativeYieldManager__InvariantError();
            }

            // If we didnt revert prior we now know that we have more
            // WETH than expected.

            SafeTransferLib.safeTransfer(
                address(WETH_YIELD_MANAGER),
                centralRegistry.daoAddress(),
                WETHAfter - WETHPrior
            );
        }

        if (USDBPerSecond > 0){
            // Approve USDB to the Gauge Pool, if necessary.
            SwapperLib._approveTokenIfNeeded(
                address(USDB_YIELD_MANAGER),
                address(gaugePool),
                USDBYield
            );

            gaugePool.setRewardPerSec(
                yieldDestination,
                nextEpoch,
                address(USDB_YIELD_MANAGER),
                USDBPerSecond
            );

            // Remove any excess approval.
            SwapperLib._removeApprovalIfNeeded(
                address(USDB_YIELD_MANAGER),
                address(gaugePool)
            );
        }

        // Cache new WETH balance, its possible we received rewards back by
        // calling gauge system, or if no rewards were set because yield
        // was too low.
        uint256 USDBAfter = USDB_YIELD_MANAGER.balanceOf(address(this));

        // We offset the prior to what we expect to have been remove
        // from prior balance after streaming native yield via gauge system.
        USDBPrior -= USDBYield;

        if (USDBAfter != USDBPrior) {
            // If somehow the contract pulled more yield than allotted,
            // panic and kill the action.
            if (USDBAfter < USDBPrior) {
                revert BlastNativeYieldManager__InvariantError();
            }

            // If we didnt revert prior we now know that we have more
            // USDB than expected.
            SafeTransferLib.safeTransfer(
                address(USDB_YIELD_MANAGER),
                centralRegistry.daoAddress(),
                USDBAfter - USDBPrior
            );
        }
    }

    /// @notice Claims delegated yield on behalf of the caller. Will natively
    ///         revert if not delegated, works out of the box for any
    ///         protocol meaning anyone can benefit from the composable nature
    ///         of the smart contract.
    /// @dev Only callable by governee themself. Natively claims gas rebate.
    /// @param marketManager The Market Manager associated with the mToken
    ///                      managing it native yield.
    /// @param claimWETHYield Whether WETH native yield should be claimed.
    /// @param claimUSDBYield Whether USDB native yield should be claimed.
    /// @return WETHYield The amount of WETH yield claimed.
    /// @return USDBYield The amount of USDB yield claimed.
    function claimYieldForAutoCompounding(
        address marketManager,
        bool claimWETHYield,
        bool claimUSDBYield
    ) external nonReentrant returns (
        uint256 WETHYield,
        uint256 USDBYield
    ) {
        // Validate that `marketManager_` is configured as a market manager
        // inside the Yield Manager.
        if (!isMarketManager[marketManager]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Validate that the caller is a token listed inside the associated
        // Market Manager.
        if (!IMarketManager(marketManager).isListed(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        uint256 gasYield = CHAIN_YIELD_MANAGER.claimMaxGas(
            msg.sender,
            address(this)
        );

        if (gasYield > 0) {
            IWETH(address(WETH_YIELD_MANAGER)).deposit{ value: gasYield }();
            WETHYield += gasYield;
        }

        if (claimWETHYield) {
            uint256 pendingWETH = pendingWETHYield[msg.sender];

            // Recognize USDB yield, if necessary.
            if (pendingWETH > 0) {
                WETHYield += pendingWETH;
            }
        }

        if (claimUSDBYield) {
            uint256 pendingUSDB = pendingUSDBYield[msg.sender];

            // Recognize USDB yield, if necessary.
            if (pendingUSDB > 0) {
                USDBYield += pendingUSDB;
            }
        }

        // Validate yield was actually claimed.
        if (USDBYield == 0 && WETHYield == 0) {
            revert BlastNativeYieldManager__NoYieldToClaim();
        }

        if (USDBYield != 0) {
            SafeTransferLib.safeTransfer(
                address(USDB_YIELD_MANAGER),
                msg.sender,
                USDBYield
            );
        }

        if (WETHYield != 0) {
            SafeTransferLib.safeTransfer(
                address(WETH_YIELD_MANAGER),
                msg.sender,
                WETHYield
            );
        }
    }

    /// @notice Sets routing of cToken rewards to dToken lenders.
    /// @dev This is a 1:1 mapping so in cases of cross margin markets
    ///      these mappings will need to be monitored.
    /// @param cToken The collateral token to route native yield from.
    /// @param cToken The debt token to route native yield to.
    function setCTokenToDTokenYieldDonation(
        address cToken,
        address dToken
    ) external {
        _checkElevatedPermissions();

        if (
            IMToken(cToken).marketManager() != 
            IMToken(dToken).marketManager()
            ) {
                revert BlastNativeYieldManager__MarketManagerMismatch();
            }
        
        if (
            !IMToken(cToken).isCToken() ||
            IMToken(dToken).isCToken()
            ) {
                revert BlastNativeYieldManager__InvalidTokenTypes();
            }
        
        cTokenToDTokenYieldRouted[cToken] = dToken;
    }

    /// @notice Withdraws all native yield fees from non-MToken addresses.
    /// @dev Only callable by Central Registry.
    /// @param nonMTokens Array of non-MTokens addresses to withdraw native from.
    function claimPendingNativeYield(address[] calldata nonMTokens) external {
        _checkIsCentralRegistry();

        uint256 nonMTokensLength = nonMTokens.length;
        uint256 yieldClaimed;

        for (uint256 i; i < nonMTokensLength; ++i) {
            yieldClaimed += CHAIN_YIELD_MANAGER.claimMaxGas(
                nonMTokens[i],
                address(this)
            );
        }

        if (yieldClaimed == 0) {
            revert BlastNativeYieldManager__NoYieldToClaim();
        }

        IWETH(address(WETH_YIELD_MANAGER)).deposit{ value: yieldClaimed }();
        SafeTransferLib.safeTransfer(address(WETH_YIELD_MANAGER), centralRegistry.daoAddress(), yieldClaimed);
    }

    /// @notice Used by Curvance mTokens to notify the Yield Manager native
    ///         yield has been claimed to the Yield Manager.
    /// @param marketManager The Market Manager contract associated with
    ///                      calling Curvance mToken.
    /// @param isWETH The yield type of rewards to be notified.
    ///               true corresponds to WETH, false corresponds to USDB.
    /// @param marketManager The Market Manager contract associated with
    ///                      calling Curvance mToken.
    function notifyRewards(
        address marketManager,
        bool isWETH,
        uint256 amount
    ) external {
        // Validate that `marketManager_` is configured as a market manager
        // inside the Yield Manager.
        if (!isMarketManager[marketManager]) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        // Validate that the caller is a token listed inside the associated
        // Market Manager.
        if (!IMarketManager(marketManager).isListed(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }

        if (isWETH) {
            pendingWETHYield[msg.sender] = pendingWETHYield[msg.sender] + amount;
            return;
        }

        pendingUSDBYield[msg.sender] = pendingUSDBYield[msg.sender] + amount;
    }

    /// @notice Called by the Central registry on updating isMarketManager on Blast.
    /// @dev Only callable by Curvance Central Registry.
    /// @param notifiedMarketManager The Market Manager contract to modify support
    ///                              for use in Curvance Yield Manager.
    function notifyIsMarketManager(
        address notifiedMarketManager,
        bool isSupported
    ) external {
        _checkIsCentralRegistry();

        isMarketManager[notifiedMarketManager] = isSupported;
    }

    /// @notice Helper function to view pending gas yield available for claim.
    /// @dev Returns 0 if the Yield Router is not a governor of `delegatedAddress`.
    /// @param delegatedAddress The address to check pending gas fees for.
    /// @return The pending claimable native yield.
    function getClaimableNativeYield(
        address delegatedAddress
    ) external view returns (uint256) {
        if (!CHAIN_YIELD_MANAGER.isGovernor(delegatedAddress)) {
            return 0;
        }
        return CHAIN_YIELD_MANAGER.readClaimableYield(delegatedAddress);
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev Internal helper for reverting efficiently.
    function _revert(uint256 s) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }

    function _checkIsCentralRegistry() internal view {
        address _centralRegistry = address(centralRegistry);
        assembly {
            if iszero(eq(caller(), _centralRegistry)) {
                mstore(0x00, _UNAUTHORIZED_SELECTOR)
                // Return bytes 29-32 for the selector.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            _revert(_UNAUTHORIZED_SELECTOR);
        }
    }
}
