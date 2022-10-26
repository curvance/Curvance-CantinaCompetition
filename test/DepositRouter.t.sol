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

        router.depositToPosition(address(this), 1, uint128(assets));
    }

    function testWithdraw() external {
        uint256 assets = 100e18;
        router.deposit(assets);

        router.depositToPosition(address(this), 1, uint128(assets));

        uint256 assetsToWithdraw = (daiVault.balanceOf(address(router)) * daiVault.pricePerShare()) / 1e18;
        console.log(assetsToWithdraw);
        router.withdrawFromPosition(address(this), 1, uint128(assetsToWithdraw));
    }

    function testHarvest() external {
        uint256 assets = 100e18;
        router.deposit(assets);

        router.depositToPosition(address(this), 1, uint128(assets));

        uint256 sharePrice = daiVault.pricePerShare();

        stdstore.target(address(daiVault)).sig(daiVault.pricePerShare.selector).checked_write(
            uint256(sharePrice + 100)
        );

        router.harvestPosition(1);
    }

    // ========================================= HELPER FUNCTIONS =========================================
}
