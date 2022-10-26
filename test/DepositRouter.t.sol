// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IYearnVault } from "src/interfaces/Yearn/IYearnVault.sol";
import { DepositRouter } from "src/DepositRouter.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract DepositRouterTest is Test {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    DepositRouter private router;

    IYearnVault daiVault = IYearnVault(0xdA816459F1AB5631232FE5e97a05BBBb94970c95);

    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() external {
        router = new DepositRouter();

        router.addPosition(address(DAI), DepositRouter.Platform.YEARN, abi.encode(address(daiVault)));

        router.addOperator(address(this), address(this), address(DAI), 1, 0);

        deal(address(DAI), address(this), type(uint256).max);
        DAI.safeApprove(address(router), type(uint256).max);

        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit() external {
        uint256 assets = 100e18;
        router.deposit(assets);

        // router.depositToPosition(address(this), 1, uint128(assets));
        router.rebalance(address(this), 0, 1, assets);
    }

    function testWithdraw() external {
        uint256 assets = 100e18;
        router.deposit(assets);

        // router.depositToPosition(address(this), 1, uint128(assets));
        router.rebalance(address(this), 0, 1, assets);

        uint256 assetsToWithdraw = (daiVault.balanceOf(address(router)) * daiVault.pricePerShare()) / 1e18;
        console.log(assetsToWithdraw);
        router.rebalance(address(this), 1, 0, assets);
        router.withdraw(assetsToWithdraw);
        // router.withdrawFromPosition(address(this), 1, uint128(assetsToWithdraw));
    }

    function testHarvest() external {
        uint256 assets = 100e18;
        router.deposit(assets);

        // router.depositToPosition(address(this), 1, uint128(assets));
        router.rebalance(address(this), 0, 1, assets);

        _simulateYearnYield(daiVault, 1_000_000e18);

        router.harvestPosition(1);

        console.log("Operator Balance", router.balanceOf(address(this)));

        console.log("Time", block.timestamp);
        vm.warp(block.timestamp + 7 days);
        console.log("Time", block.timestamp);

        console.log("Operator Balance", router.balanceOf(address(this)));

        uint256 assetsToWithdraw = 100.5e18;

        console.log("DAI", DAI.balanceOf(address(router)));
        router.rebalance(address(this), 1, 0, assetsToWithdraw);
        console.log("DAI", DAI.balanceOf(address(router)));
        router.withdraw(assetsToWithdraw);
        // router.withdrawFromPosition(address(this), 1, uint128(assetsToWithdraw));
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _simulateYearnYield(IYearnVault vault, uint256 yield) internal {
        // Simulates yield earned by increasing totalDebt which increases totalAssets which increases the share price.
        uint256 currentDebt = vault.totalDebt();
        stdstore.target(address(vault)).sig(vault.totalDebt.selector).checked_write(uint256(currentDebt + yield));
    }
}
