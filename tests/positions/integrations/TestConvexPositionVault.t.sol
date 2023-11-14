// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ERC20 } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ConvexPositionVault } from "contracts/deposits/adaptors/Convex2PoolPositionVault.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";

import "tests/market/TestBaseMarket.sol";

contract TestConvexPositionVault is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ERC20 public constant CVX =
        ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 public constant CRV =
        ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public CONVEX_STETH_ETH_POOL =
        ERC20(0x21E27a5E5513D6e65C4f830167390997aA84843a);
    uint256 public CONVEX_STETH_ETH_POOL_ID = 177;
    address public CONVEX_STETH_ETH_REWARD =
        0x6B27D7BC63F1999D14fF9bA900069ee516669ee8;
    address public CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    ConvexPositionVault positionVault;
    CToken public cSTETH;

    /*
    LP token address	0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4
    Deposit contract address	0xF403C135812408BFbE8713b5A23a04b3D48AAE31
    Rewards contract address	0xb05262D4aaAA38D0Af4AaB244D446ebDb5afd4A7
    Convex pool id	188
    Convex pool url	https://www.convexfinance.com/stake/ethereum/188
    */

    receive() external payable {}

    fallback() external payable {}

    // this is to use address(this) as mock CToken address
    function tokenType() external pure returns (uint256) {
        return 1;
    }

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        _deployGaugePool();
        _deployLendtroller();

        centralRegistry.addHarvester(address(this));
        centralRegistry.setFeeAccumulator(address(this));

        positionVault = new ConvexPositionVault(
            CONVEX_STETH_ETH_POOL,
            ICentralRegistry(address(centralRegistry)),
            CONVEX_STETH_ETH_POOL_ID,
            CONVEX_STETH_ETH_REWARD,
            CONVEX_BOOSTER
        );

        cSTETH = new CToken(
            ICentralRegistry(address(centralRegistry)),
            address(CONVEX_STETH_ETH_POOL),
            address(lendtroller),
            address(positionVault)
        );
        positionVault.initiateVault(address(cSTETH));
    }

    function testConvexStethEthPool() public {
        uint256 assets = 100e18;
        deal(address(CONVEX_STETH_ETH_POOL), address(cSTETH), assets);

        vm.prank(address(cSTETH));
        CONVEX_STETH_ETH_POOL.approve(address(positionVault), assets);

        vm.prank(address(cSTETH));
        positionVault.deposit(assets, address(this));

        assertEq(
            positionVault.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Mint some extra rewards for Vault.
        deal(address(CRV), address(positionVault), 100e18);
        deal(address(CVX), address(positionVault), 100e18);
        deal(address(positionVault), 1 ether);

        positionVault.harvest(abi.encode(new SwapperLib.Swap[](0)));

        assertEq(
            positionVault.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );

        vm.warp(block.timestamp + 8 days);

        // Mint some extra rewards for Vault.
        deal(address(CRV), address(positionVault), 100e18);
        deal(address(CVX), address(positionVault), 100e18);
        deal(address(positionVault), 1 ether);
        positionVault.harvest(abi.encode(new SwapperLib.Swap[](0)));
        vm.warp(block.timestamp + 7 days);

        uint256 totalAssets = positionVault.totalAssets();

        assertGt(
            totalAssets,
            assets,
            "Total Assets should greater than original deposit."
        );

        vm.prank(address(cSTETH));
        positionVault.withdraw(totalAssets, address(this), address(this));
    }
}
