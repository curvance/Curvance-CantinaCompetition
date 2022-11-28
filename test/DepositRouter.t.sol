// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IYearnVault } from "src/interfaces/Yearn/IYearnVault.sol";
import { DepositRouter } from "src/DepositRouter.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract DepositRouterTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    DepositRouter private router;

    IYearnVault daiVault = IYearnVault(0xdA816459F1AB5631232FE5e97a05BBBb94970c95);

    IYearnVault curve3CryptoVault = IYearnVault(0xE537B5cc158EB71037D4125BDD7538421981E6AA);

    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private curve3Crypto = ERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
    uint256 curve3PoolConvexPid = 38;
    address private curve3CryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address private curve3PoolReward = 0x9D5C5E364D81DaB193b72db9E9BE9D8ee669B652;

    address private constant crveth = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511; // use curve's new CRV-ETH crypto pool to sell our CRV
    address private constant cvxeth = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4; // use curve's new CVX-ETH crypto pool to sell our CVX

    function setUp() external {
        router = new DepositRouter();

        address[8] memory pools;
        uint16[8] memory froms;
        uint16[8] memory tos;
        DepositRouter.DepositData memory depositData;

        pools[0] = crveth;
        pools[1] = cvxeth;
        froms = [uint16(1), 1, 0, 0, 0, 0, 0, 0];
        // tos should be all zeros.

        uint8 coinsLength = 3;
        uint8 targetIndex = 2;
        bool useUnderlying = false;
        depositData = DepositRouter.DepositData(address(WETH), coinsLength, targetIndex, useUnderlying);

        router.addPosition(
            curve3Crypto,
            DepositRouter.Platform.CONVEX,
            abi.encode(curve3PoolConvexPid, curve3PoolReward, curve3CryptoPool),
            pools,
            froms,
            tos,
            depositData
        );

        uint32[8] memory positions = [uint32(0), 1, 0, 0, 0, 0, 0, 0];
        uint32[8] memory positionRatios = [uint32(0.2e8), 0.8e8, 0, 0, 0, 0, 0, 0];
        router.addOperator(address(this), address(this), curve3Crypto, positions, positionRatios, 0.3e8, 0, 0);

        deal(address(curve3Crypto), address(this), type(uint128).max);
        curve3Crypto.safeApprove(address(router), type(uint256).max);

        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // function testYearnDeposit() external {
    //     uint256 assets = 100e18;
    //     router.deposit(assets);

    //     // router.depositToPosition(address(this), 1, uint128(assets));
    //     router.rebalance(address(this), 0, 1, assets);
    // }

    // function testYearnWithdraw() external {
    //     uint256 assets = 100e18;
    //     router.deposit(assets);

    //     // router.depositToPosition(address(this), 1, uint128(assets));
    //     router.rebalance(address(this), 0, 1, assets);

    //     uint256 assetsToWithdraw = router.balanceOf(address(this));
    //     console.log(assetsToWithdraw);
    //     router.rebalance(address(this), 1, 0, assetsToWithdraw);
    //     router.withdraw(assetsToWithdraw);
    // }

    // function testYearnHarvest() external {
    //     uint256 assets = 100e18;
    //     router.deposit(assets);

    //     // router.depositToPosition(address(this), 1, uint128(assets));
    //     router.rebalance(address(this), 0, 1, assets);

    //     _simulateYearnYield(curve3CryptoVault, 100e18);

    //     router.harvestPosition(1);

    //     uint256 operatorBalanceBefore = router.balanceOf(address(this));
    //     assertLe(operatorBalanceBefore, assets, "No yield has vested yet.");

    //     vm.warp(block.timestamp + 7 days);

    //     uint256 operatorBalanceAfter = router.balanceOf(address(this));

    //     assertGt(
    //         operatorBalanceAfter,
    //         operatorBalanceBefore,
    //         "Operator balance should have increased from vested yield."
    //     );

    //     router.rebalance(address(this), 1, 0, operatorBalanceAfter);
    //     assertGe(
    //         router.balanceOf(address(this)),
    //         operatorBalanceAfter,
    //         "Balance should not decrease during a rebalance."
    //     );
    //     router.withdraw(operatorBalanceAfter);
    // }

    function testConvexDeposit() external {
        uint256 assets = 100e18;
        router.deposit(assets);

        // router.depositToPosition(address(this), 1, uint128(assets));
        router.rebalance(address(this), 0, 1, assets);
    }

    function testConvexWithdraw() external {
        uint256 assets = 100e18;
        router.deposit(assets);

        uint256 assetsToWithdraw = router.balanceOf(address(this));

        // router.depositToPosition(address(this), 1, uint128(assets));
        router.rebalance(address(this), 0, 1, assets);

        assetsToWithdraw = router.balanceOf(address(this));
        router.rebalance(address(this), 1, 0, assetsToWithdraw);

        router.withdraw(assetsToWithdraw);
    }

    function testConvexHarvest() external {
        uint256 assets = 10_000e18;
        // uint256 gas = gasleft();
        router.deposit(assets);
        // console.log("Gas Used for Deposit", gas - gasleft());

        // gas = gasleft();
        router.rebalance(address(this), 0, 1, assets);
        // console.log("Gas Used for Rebalance 0 -> 2", gas - gasleft());

        // IBaseRewardPool pool = IBaseRewardPool(curve3PoolReward);

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Harvest rewards.
        // gas = gasleft();
        router.harvestPosition(1);
        // console.log("Gas Used for Harvest", gas - gasleft());

        // Fully vest rewards
        vm.warp(block.timestamp + 7 days);

        uint256 assetsToWithdraw = router.balanceOf(address(this));
        // gas = gasleft();
        router.rebalance(address(this), 1, 0, assetsToWithdraw);
        // console.log("Gas Used for Rebalance 0 -> 2", gas - gasleft());
        deal(address(curve3Crypto), address(this), 0);
        // gas = gasleft();
        router.withdraw(assetsToWithdraw);
        // console.log("Gas Used for Withdraw", gas - gasleft());
    }

    // ========================================= HELPER FUNCTIONS =========================================

    // function _simulateYearnYield(IYearnVault vault, uint256 yield) internal {
    //     // Simulates yield earned by increasing totalDebt which increases totalAssets which increases the share price.
    //     uint256 currentDebt = vault.totalDebt();
    //     stdstore.target(address(vault)).sig(vault.totalDebt.selector).checked_write(uint256(currentDebt + yield));
    // }
}
