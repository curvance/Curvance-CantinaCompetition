// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, SafeTransferLib, ERC20, Math } from "src/base/ERC4626.sol";
import { PriceRouter } from "src/PricingOperations/PriceRouter.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { Owned } from "@solmate/auth/Owned.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";

///@notice Vault Positions must have all assets ready for withdraw, IE assets can NOT be locked.
// This way assets can be easily liquidated when loans default.
abstract contract BasePositionVault is ERC4626, Initializable, KeeperCompatibleInterface, Owned {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                             GLOBAL STATE
    //////////////////////////////////////////////////////////////*/

    uint64 public platformFee;
    address public feeAccumulator;
    PriceRouter public priceRouter;
    address public positionWatchdog; // Can just be sent to an admin address/a bot that can fund upkeeps.
    uint64 public upkeepFee = 0.03e18; //TODO should be set in initialize function?
    uint64 public minHarvestYieldInUSD = 1_000e8;
    uint64 public maxGasPriceForHarvest = 1_000e9;
    address public ETH_FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    // Internal stored total assets, not accounting for
    uint256 internal _totalAssets;
    uint128 internal _rewardRate;
    uint64 internal _vestingPeriodEnd;
    uint64 internal _lastVestClaim;

    uint64 internal constant REWARD_SCALER = 1e18;

    /**
     * @notice Period newly harvested rewards are vested over.
     */
    uint32 public constant REWARD_PERIOD = 7 days;

    /*//////////////////////////////////////////////////////////////
                          SETUP LOGIC
    //////////////////////////////////////////////////////////////*/

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _owner
    ) ERC4626(_asset, _name, _symbol, _decimals) Owned(_owner) {}

    function initialize(
        ERC20 _asset,
        address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint64 _platformFee,
        address _feeAccumulator,
        PriceRouter _priceRouter,
        bytes memory _initializeData
    ) external virtual;

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows owner to set a new gas feed.
     * @notice Can be set to zero address to skip gas check.
     */
    //  TODO these need events emitted.
    function setGasFeed(address gasFeed) external onlyOwner {
        ETH_FAST_GAS_FEED = gasFeed;
    }

    function setWatchdog(address _watchdog) external onlyOwner {
        positionWatchdog = _watchdog;
    }

    function setMinHarvestYield(uint64 minYieldUSD) external onlyOwner {
        minHarvestYieldInUSD = minYieldUSD;
    }

    function setMaxGasForHarvest(uint64 maxGas) external onlyOwner {
        maxGasPriceForHarvest = maxGas;
    }

    function setPriceRouter(PriceRouter _priceRouter) external onlyOwner {
        priceRouter = _priceRouter;
    }

    // TODO needs a max value.
    function setPlatformFee(uint64 fee) external onlyOwner {
        platformFee = fee;
    }

    function setFeeAccumulator(address accumulator) external onlyOwner {
        feeAccumulator = accumulator;
    }

    // TODO needs a max value.
    function setUpkeepFee(uint64 fee) external onlyOwner {
        upkeepFee = fee;
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD/HARVESTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates pending rewards currently being vested, and vests them.
     */
    function _calculatePendingRewards() internal view returns (uint256 pendingRewards) {
        // Used by totalAssets
        uint64 currentTime = uint64(block.timestamp);
        if (_rewardRate > 0 && _lastVestClaim < _vestingPeriodEnd) {
            // There are pending rewards.
            pendingRewards = currentTime < _vestingPeriodEnd
                ? (_rewardRate * (currentTime - _lastVestClaim))
                : (_rewardRate * (_vestingPeriodEnd - _lastVestClaim));
            pendingRewards = pendingRewards / REWARD_SCALER;
        } // else there are no pending rewards.
    }

    function _vestRewards(uint256 _ta) internal {
        // Update some reward timestamp.
        _lastVestClaim = uint64(block.timestamp);

        // Set internal balance equal to totalAssets value
        _totalAssets = _ta;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        // Check for rounding error since we round down in previewDeposit.
        require((shares = _previewDeposit(assets, ta)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Add the users newly deposited assets.
        ta = ta + assets;
        if (pending > 0) _vestRewards(ta);
        else _totalAssets = ta;

        _deposit(assets);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        assets = _previewMint(shares, ta); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Add the users newly deposited assets.
        ta = ta + assets;
        if (pending > 0) _vestRewards(ta);
        else _totalAssets = ta;

        _deposit(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        shares = _previewWithdraw(assets, ta); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Remove the users withdrawn assets.
        ta = ta - assets;
        if (pending > 0) _vestRewards(ta);
        else _totalAssets = ta;
        _withdraw(assets);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        // Save _totalAssets and pendingRewards to memory.
        uint256 pending = _calculatePendingRewards();
        uint256 ta = _totalAssets + pending;

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = _previewRedeem(shares, ta)) != 0, "ZERO_ASSETS");

        // Remove the users withdrawn assets.
        ta = ta - assets;
        if (pending > 0) _vestRewards(ta);
        else _totalAssets = ta;
        _withdraw(assets);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        // Returns stored internal balance + pending rewards that are vested.
        return _totalAssets + _calculatePendingRewards();
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, totalSupply);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        return _previewMint(shares, totalAssets());
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _previewWithdraw(assets, totalAssets());
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function _convertToShares(uint256 assets, uint256 _ta) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply;

        shares = totalShares == 0 ? assets.changeDecimals(asset.decimals(), 18) : assets.mulDivDown(totalShares, _ta);
    }

    function _convertToAssets(uint256 shares, uint256 _ta) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply;

        assets = totalShares == 0 ? shares.changeDecimals(18, asset.decimals()) : shares.mulDivDown(_ta, totalShares);
    }

    function _previewDeposit(uint256 assets, uint256 _ta) internal view returns (uint256) {
        return _convertToShares(assets, _ta);
    }

    function _previewMint(uint256 shares, uint256 _ta) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply;

        assets = totalShares == 0 ? shares.changeDecimals(18, asset.decimals()) : shares.mulDivUp(_ta, totalShares);
    }

    function _previewWithdraw(uint256 assets, uint256 _ta) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply;

        shares = totalShares == 0 ? assets.changeDecimals(asset.decimals(), 18) : assets.mulDivUp(totalShares, _ta);
    }

    function _previewRedeem(uint256 shares, uint256 _ta) internal view returns (uint256) {
        return _convertToAssets(shares, _ta);
    }

    /*//////////////////////////////////////////////////////////////
                    CHAINLINK AUTOMATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function checkUpkeep(bytes calldata) external returns (bool upkeepNeeded, bytes memory performData) {
        // Figure out how much yield is pending to be harvested.
        uint256 yield = harvest();

        // Compare USD value of yield against owner set minimum.
        uint256 yieldInUSD = yield.mulDivDown(priceRouter.getPriceInUSD(asset), 10**asset.decimals());
        if (yieldInUSD < minHarvestYieldInUSD) return (false, abi.encode(0));

        // Compare current gas price against owner set minimum.
        uint256 currentGasPrice = uint256(IChainlinkAggregator(ETH_FAST_GAS_FEED).latestAnswer());
        if (currentGasPrice > maxGasPriceForHarvest) return (false, abi.encode(0));

        // If we have made it this far, then we know yield is sufficient, and gas price is low enough.
        upkeepNeeded = true;
        // performData is not used.
    }

    function performUpkeep(bytes calldata) external {
        harvest();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 assets) internal virtual;

    function _deposit(uint256 assets) internal virtual;

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvest() public virtual returns (uint256 yield);
}
