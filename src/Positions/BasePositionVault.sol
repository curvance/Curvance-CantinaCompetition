// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, SafeTransferLib, ERC20, Math } from "src/base/ERC4626.sol";
import { PriceRouter } from "src/PricingOperations/PriceRouter.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { IUniswapV3Router } from "src/interfaces/Uniswap/IUniswapV3Router.sol";

///@notice Vault Positions must have all assets ready for withdraw, IE assets can NOT be locked.
abstract contract BasePositionVault is ERC4626, Initializable, KeeperCompatibleInterface {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC4626(_asset, _name, _symbol, _decimals) {}

    // These values should be changeable by owner, and should also potentially be stored in a central registry contract.
    uint64 public platformFee = 0.2e18;
    address public feeAccumulator;
    PriceRouter public priceRouter;
    address public positionWatchdog;
    uint64 public upkeepFee = 0.03e18;
    IUniswapV3Router uniswapV3Router = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint64 minHarvestYieldInUSD = 1_000e8;

    /*//////////////////////////////////////////////////////////////
                        REWARD/HARVESTING LOGIC
    //////////////////////////////////////////////////////////////*/

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
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData) {
        // Checks current gas price and if low enough continues
        // calls harvest function, simulating the harvest tx.
        uint256 yield = harvest();

        uint256 wethBalance = WETH.balanceOf(address(this));
        // If balance is greater than some minimum, set a bool in perform data to true.

        // Checks dollar value of yield.
        uint256 yieldInUSD = yield.mulDivDown(priceRouter.getPriceInUSD(asset), 10**asset.decimals());
        // make sure yield is worth it.

        // Can also run WETH.balanceOf to see if WETH balance warrants a swap for LINK
    }

    function performUpkeep(bytes calldata performData) external {
        harvest();
        // Perform data can be a bool indicating whether it should swap WETH for LINK and func the upkeep?
        bool fundUpkeep = abi.decode(performData, (bool));
        if (fundUpkeep) {
            uint256 amount = _swapWETHForLINK();
            // Top up upkeep with amount.
        }
    }

    function _swapWETHForLINK() internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(LINK);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;
        bytes memory encodePackedPath = abi.encodePacked(address(WETH));
        for (uint256 i = 1; i < path.length; i++)
            encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

        // Execute the swap.
        amountOut = uniswapV3Router.exactInput(
            IUniswapV3Router.ExactInputParams({
                path: encodePackedPath,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: WETH.balanceOf(address(this)),
                amountOutMinimum: 0
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 assets) internal virtual;

    function _deposit(uint256 assets) internal virtual;

    function harvest() public virtual returns (uint256 yield);

    function initialize(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint64 _platformFee,
        address _feeAccumulator,
        PriceRouter _priceRouter,
        bytes memory _initializeData
    ) external virtual;
}
