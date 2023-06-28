// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import { ERC4626, SafeTransferLib, ERC20} from "contracts/libraries/ERC4626.sol";
import { Math } from "contracts/libraries/Math.sol";
import { PriceRouter } from "contracts/oracles/PriceRouterV2.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";

///@notice Vault Positions must have all assets ready for withdraw, IE assets can NOT be locked.
// This way assets can be easily liquidated when loans default.
///@dev The position vaults run must be a LOSSLESS position, since totalAssets is not actually using the balances stored in the position, rather it only uses an internal balance.
abstract contract BasePositionVault is
    ERC4626,
    Initializable,
    KeeperCompatibleInterface,
    ReentrancyGuard
{
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                             STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct PositionVaultMetaData {
        uint64 platformFee;
        uint64 upkeepFee;
        uint64 minHarvestYieldInUSD;
        uint64 maxGasPriceForHarvest;
        address feeAccumulator;
        address positionWatchdog;
        address ethFastGasFeed;
        PriceRouter priceRouter;
        address automationRegistry;
        bool isShutdown;
    }

    struct PositionVaultAccounting {
        uint128 _rewardRate;
        uint64 _vestingPeriodEnd;
        uint64 _lastVestClaim;
    }

    /*//////////////////////////////////////////////////////////////
                             GLOBAL STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Address for Curvance DAO registry contract for ownership and location data.
     */
    ICentralRegistry public centralRegistry;

    ERC20 private _asset;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    PositionVaultMetaData public positionVaultMetaData;
    PositionVaultAccounting public positionVaultAccounting;

    // Internal stored total assets, share price high watermark.
    uint256 internal _totalAssets;
    uint256 internal _sharePriceHighWatermark;

    uint64 internal constant REWARD_SCALER = 1e18;

    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant LINK =
        ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    /**
     * @notice Period newly harvested rewards are vested over.
     */
    uint32 public constant REWARD_PERIOD = 7 days;

    /**
     * @notice Maximum possible platform fee.
     */
    uint64 public constant MAX_PLATFORM_FEE = 0.3e18;

    /**
     * @notice Maximum possible upkeep fee.
     */
    uint64 public constant MAX_UPKEEP_FEE = 0.1e18;

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    modifier whenNotShutdown() {
        if (positionVaultMetaData.isShutdown)
            revert BasePositionVault__ContractShutdown();

        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event GasFeedChanged(address feed);
    event WatchdogChanged(address watchdog);
    event MinYieldForHarvestChanged(uint64 minYieldUSD);
    event MaxGasForHarvestChanged(uint64 maxGas);
    event PriceRouterChanged(address router);
    event PlatformFeeChanged(uint64 fee);
    event FeeAccumulatorChanged(address accumulator);
    event UpkeepFeeChanged(uint64 fee);
    event ShutdownChanged(bool isShutdown);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error BasePositionVault__InvalidPlatformFee(uint64 invalidFee);
    error BasePositionVault__InvalidUpkeepFee(uint64 invalidFee);
    error BasePositionVault__ContractShutdown();
    error BasePositionVault__ContractNotShutdown();

    /*//////////////////////////////////////////////////////////////
                          SETUP LOGIC
    //////////////////////////////////////////////////////////////*/

    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        ICentralRegistry _centralRegistry
    ) {
        _asset = asset_;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        centralRegistry = _centralRegistry;
    }

    function initialize(
        ERC20 asset_,
        ICentralRegistry _centralRegistry,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        PositionVaultMetaData calldata _metaData,
        bytes memory
    ) public virtual {
        _asset = asset_;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        centralRegistry = _centralRegistry;
        if (_metaData.platformFee > MAX_PLATFORM_FEE)
            revert BasePositionVault__InvalidPlatformFee(
                _metaData.platformFee
            );
        if (_metaData.upkeepFee > MAX_UPKEEP_FEE)
            revert BasePositionVault__InvalidUpkeepFee(_metaData.upkeepFee);
        positionVaultMetaData = _metaData;
    }

    // Only callable by DAO
    modifier onlyDaoManager() {
        require(
            msg.sender == centralRegistry.daoAddress(),
            "priceRouter: UNAUTHORIZED"
        );
        _;
    }

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @dev Returns the address of the underlying asset.
    function asset() public view override returns (address) {
        return address(_asset);
    }

    /// @dev Returns the decimals of the underlying asset.
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows owner to set a new gas feed.
     * @notice Can be set to zero address to skip gas check.
     */
    function setGasFeed(address gasFeed) external onlyDaoManager {
        positionVaultMetaData.ethFastGasFeed = gasFeed;
        emit GasFeedChanged(gasFeed);
    }

    function setWatchdog(address _watchdog) external onlyDaoManager {
        positionVaultMetaData.positionWatchdog = _watchdog;
        emit WatchdogChanged(_watchdog);
    }

    function setMinHarvestYield(uint64 minYieldUSD) external onlyDaoManager {
        positionVaultMetaData.minHarvestYieldInUSD = minYieldUSD;
        emit MinYieldForHarvestChanged(minYieldUSD);
    }

    function setMaxGasForHarvest(uint64 maxGas) external onlyDaoManager {
        positionVaultMetaData.maxGasPriceForHarvest = maxGas;
        emit MaxGasForHarvestChanged(maxGas);
    }

    function setPriceRouter(PriceRouter _priceRouter) external onlyDaoManager {
        positionVaultMetaData.priceRouter = _priceRouter;
        emit PriceRouterChanged(address(_priceRouter));
    }

    function setPlatformFee(uint64 fee) external onlyDaoManager {
        if (fee > MAX_PLATFORM_FEE)
            revert BasePositionVault__InvalidPlatformFee(fee);
        positionVaultMetaData.platformFee = fee;
        emit PlatformFeeChanged(fee);
    }

    function setFeeAccumulator(address accumulator) external onlyDaoManager {
        positionVaultMetaData.feeAccumulator = accumulator;
        emit FeeAccumulatorChanged(accumulator);
    }

    function setUpkeepFee(uint64 fee) external onlyDaoManager {
        if (fee > MAX_UPKEEP_FEE)
            revert BasePositionVault__InvalidUpkeepFee(fee);
        positionVaultMetaData.upkeepFee = fee;
        emit UpkeepFeeChanged(fee);
    }

    /**
     * @notice Shutdown the vault. Used in an emergency or if the vault has been deprecated.
     * @dev In the case where
     */
    function initiateShutdown() external whenNotShutdown onlyDaoManager {
        positionVaultMetaData.isShutdown = true;

        emit ShutdownChanged(true);
    }

    /**
     * @notice Restart the vault.
     */
    function liftShutdown() external onlyDaoManager {
        if (!positionVaultMetaData.isShutdown)
            revert BasePositionVault__ContractNotShutdown();
        positionVaultMetaData.isShutdown = false;

        emit ShutdownChanged(false);
    }

    function isShutdown() external view returns (bool) {
        return positionVaultMetaData.isShutdown;
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD/HARVESTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates pending rewards currently being vested, and vests them.
     */
    function _calculatePendingRewards()
        internal
        view
        returns (uint256 pendingRewards)
    {
        // Used by totalAssets
        uint64 currentTime = uint64(block.timestamp);
        if (
            positionVaultAccounting._rewardRate > 0 &&
            positionVaultAccounting._lastVestClaim <
            positionVaultAccounting._vestingPeriodEnd
        ) {
            // There are pending rewards.
            pendingRewards = currentTime <
                positionVaultAccounting._vestingPeriodEnd
                ? (positionVaultAccounting._rewardRate *
                    (currentTime - positionVaultAccounting._lastVestClaim))
                : (positionVaultAccounting._rewardRate *
                    (positionVaultAccounting._vestingPeriodEnd -
                        positionVaultAccounting._lastVestClaim));
            pendingRewards = pendingRewards / REWARD_SCALER;
        } // else there are no pending rewards.
    }

    function _vestRewards(uint256 _ta) internal {
        // Update some reward timestamp.
        positionVaultAccounting._lastVestClaim = uint64(block.timestamp);

        // Set internal balance equal to totalAssets value
        _totalAssets = _ta;

        // Update share price high watermark since rewards have been vested.
        _sharePriceHighWatermark = _convertToAssets(10**_decimals, _ta);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotShutdown
        nonReentrant
        returns (uint256 shares)
    {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewDeposit.
        require((shares = _previewDeposit(assets, ta)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(asset(), msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Add the users newly deposited assets.
        ta = ta + assets;
        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) _vestRewards(ta);
        else _totalAssets = ta;

        _deposit(assets);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        whenNotShutdown
        nonReentrant
        returns (uint256 assets)
    {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        assets = _previewMint(shares, ta); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(asset(), msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Add the users newly deposited assets.
        ta = ta + assets;
        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) _vestRewards(ta);
        else _totalAssets = ta;

        _deposit(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        shares = _previewWithdraw(assets, ta); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            //uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                decreaseAllowance(owner, allowed - shares);
                //allowance[owner][msg.sender] = allowed - shares;
        }

        // Remove the users withdrawn assets.
        ta = ta - assets;
        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) _vestRewards(ta);
        else _totalAssets = ta;
        _withdraw(assets);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransfer(asset(), receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            //uint256 allowed = allowance[owner][msg.sender]; // modified 4626 implementation

            if (allowed != type(uint256).max)
                decreaseAllowance(owner, allowed - shares);
                //allowance[owner][msg.sender] = allowed - shares; // modified 4626 implementation
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = _previewRedeem(shares, ta)) != 0, "ZERO_ASSETS");

        // Remove the users withdrawn assets.
        ta = ta - assets;
        // If there are pending rewards to vest, or if high watermark is not set, vestRewards.
        if (pending > 0 || _sharePriceHighWatermark == 0) _vestRewards(ta);
        else _totalAssets = ta;
        _withdraw(assets);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransfer(asset(), receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        // Returns stored internal balance + pending rewards that are vested.
        return _totalAssets + _calculatePendingRewards();
    }

    function convertToShares(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return _convertToShares(assets, totalSupply());
    }

    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return _convertToAssets(shares, totalAssets());
    }

    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return _previewMint(shares, totalAssets());
    }

    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return _previewWithdraw(assets, totalAssets());
    }

    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    function _convertToShares(uint256 assets, uint256 _ta)
        internal
        view
        returns (uint256 shares)
    {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets.changeDecimals(_asset.decimals(), 18)
            : assets.mulDivDown(totalShares, _ta);
    }

    function _convertToAssets(uint256 shares, uint256 _ta)
        internal
        view
        returns (uint256 assets)
    {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares.changeDecimals(18, _asset.decimals())
            : shares.mulDivDown(_ta, totalShares);
    }

    function _previewDeposit(uint256 assets, uint256 _ta)
        internal
        view
        returns (uint256)
    {
        return _convertToShares(assets, _ta);
    }

    function _previewMint(uint256 shares, uint256 _ta)
        internal
        view
        returns (uint256 assets)
    {
        uint256 totalShares = totalSupply();

        assets = totalShares == 0
            ? shares.changeDecimals(18, _asset.decimals())
            : shares.mulDivUp(_ta, totalShares);
    }

    function _previewWithdraw(uint256 assets, uint256 _ta)
        internal
        view
        returns (uint256 shares)
    {
        uint256 totalShares = totalSupply();

        shares = totalShares == 0
            ? assets.changeDecimals(_asset.decimals(), 18)
            : assets.mulDivUp(totalShares, _ta);
    }

    function _previewRedeem(uint256 shares, uint256 _ta)
        internal
        view
        returns (uint256)
    {
        return _convertToAssets(shares, _ta);
    }

    /*//////////////////////////////////////////////////////////////
                    CHAINLINK AUTOMATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function checkUpkeep(bytes calldata data)
        external
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (positionVaultMetaData.isShutdown) return (false, abi.encode(0));

        // Compare real total assets to stored, and trigger circuit breaker if real is less than stored.
        uint256 realTotalAssets = _getRealPositionBalance();
        uint256 storedTotalAssets = totalAssets();
        if (realTotalAssets < storedTotalAssets)
            return (true, abi.encode(true, data));

        // Compare current share price to high watermark and trigger circuit breaker if less than high watermark.
        uint256 currentSharePrice = _convertToAssets(
            10**_decimals,
            storedTotalAssets
        );
        if (currentSharePrice < _sharePriceHighWatermark)
            return (true, abi.encode(true, data));

        // Figure out how much yield is pending to be harvested.
        uint256 yield = harvest(data);

        // Compare USD value of yield against owner set minimum.
        uint256 yieldInUSD = yield > 0
            ? yield.mulDivDown(
                positionVaultMetaData.priceRouter.getPriceUSD(asset()),
                10**_asset.decimals()
            )
            : 0;
        if (yieldInUSD < positionVaultMetaData.minHarvestYieldInUSD)
            return (false, abi.encode(0));

        // Compare current gas price against owner set minimum.
        uint256 currentGasPrice = uint256(
            IChainlinkAggregator(positionVaultMetaData.ethFastGasFeed)
                .latestAnswer()
        );
        if (currentGasPrice > positionVaultMetaData.maxGasPriceForHarvest)
            return (false, abi.encode(0));

        // If we have made it this far, then we know yield is sufficient, and gas price is low enough.
        upkeepNeeded = true;
        performData = abi.encode(false, data);
    }

    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != positionVaultMetaData.automationRegistry)
            revert("Not a Keeper.");
        (bool circuitBreaker, bytes memory data) = abi.decode(
            performData,
            (bool, bytes)
        );
        // If checkupkeep triggered circuit breaker, shutdown vault.
        if (circuitBreaker) {
            positionVaultMetaData.isShutdown = true;
            emit ShutdownChanged(true);
        } else harvest(data);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 assets) internal virtual;

    function _deposit(uint256 assets) internal virtual;

    function _getRealPositionBalance() internal view virtual returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvest(bytes memory) public virtual returns (uint256 yield);
}
