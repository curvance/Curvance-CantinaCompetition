// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ConvexPositionVault } from "contracts/deposits/adaptors/Convex2PoolPositionVault.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CurveAdaptor } from "contracts/oracles/adaptors/curve/CurveAdaptor.sol";
import { CurveReentrancyCheck } from "contracts/oracles/adaptors/curve/CurveReentrancyCheck.sol";
import "tests/market/TestBaseMarket.sol";

contract ConvexLPCollateral is TestBaseMarket {
    address internal constant _STETH_ADDRESS =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    // Curve internally uses this address to represent the address for native ETH
    address internal constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ERC20 public CONVEX_STETH_ETH_POOL =
        ERC20(0x21E27a5E5513D6e65C4f830167390997aA84843a);
    uint256 public CONVEX_STETH_ETH_POOL_ID = 177;
    address public CONVEX_STETH_ETH_REWARD =
        0x6B27D7BC63F1999D14fF9bA900069ee516669ee8;
    address public CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    ConvexPositionVault positionVault;
    CToken public cSTETH;

    function setUp() public override {
        super.setUp();

        gaugePool.start(address(lendtroller));

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

    function testBorrowWithConvexLPCollateral() public {
        CurveAdaptor crvAdaptor = new CurveAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        crvAdaptor.addAsset(
            address(CONVEX_STETH_ETH_POOL),
            address(CONVEX_STETH_ETH_POOL)
        );
        crvAdaptor.setReentrancyVerificationConfig(
            address(CONVEX_STETH_ETH_POOL),
            6500,
            CurveReentrancyCheck.N_COINS.TWO_COINS
        );
        priceRouter.addApprovedAdaptor(address(crvAdaptor));
        priceRouter.addAssetPriceFeed(
            address(CONVEX_STETH_ETH_POOL),
            address(crvAdaptor)
        );
        chainlinkAdaptor.addAsset(ETH_ADDRESS, address(chainlinkEthUsd), true);
        priceRouter.addAssetPriceFeed(ETH_ADDRESS, address(chainlinkAdaptor));
        MockV3Aggregator chainlinkStethUsd = new MockV3Aggregator(
            8,
            1500e8,
            3000e12,
            1000e6
        );
        chainlinkAdaptor.addAsset(
            _STETH_ADDRESS,
            address(chainlinkStethUsd),
            true
        );
        priceRouter.addAssetPriceFeed(
            _STETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        priceRouter.addMTokenSupport(address(cSTETH));

        // Ensure STETH/USD, ETH/USD, and USDC/USD feeds are not stale
        skip(gaugePool.startTime() - block.timestamp);
        chainlinkStethUsd.updateRoundData(
            0,
            1500e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkEthUsd.updateRoundData(
            0,
            1500e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );

        // Need funds for initial mint when listing market token
        deal(address(CONVEX_STETH_ETH_POOL), address(this), 1 ether);
        SafeTransferLib.safeApprove(
            address(CONVEX_STETH_ETH_POOL),
            address(cSTETH),
            1 ether
        );
        deal(_USDC_ADDRESS, address(this), 1 ether);
        lendtroller.listMarketToken(address(cSTETH));
        SafeTransferLib.safeApprove(_USDC_ADDRESS, address(dUSDC), 1 ether);
        lendtroller.listMarketToken(address(dUSDC));
        lendtroller.updateCollateralToken(
            IMToken(address(cSTETH)),
            2000,
            100,
            3000,
            3000,
            7000
        );
        address[] memory tokens = new address[](2);
        tokens[0] = address(dUSDC);
        tokens[1] = address(cSTETH);

        // User mints cSTETH with cvxStethEth LP tokens and then uses the cSTETH as collateral to borrow 10,000 dUSDC
        deal(_USDC_ADDRESS, address(dUSDC), 100_000e6);
        deal(address(CONVEX_STETH_ETH_POOL), user1, 10_000e18);
        vm.startPrank(user1);
        lendtroller.enterMarkets(tokens);
        IERC20(address(CONVEX_STETH_ETH_POOL)).approve(
            address(cSTETH),
            1_000e18
        );
        cSTETH.mint(1_000e18);
        assertEq(cSTETH.balanceOf(user1), 1_000e18);

        dUSDC.borrow(10_000e6);
        vm.stopPrank();

        assertEq(
            usdc.balanceOf(user1),
            10_000e6,
            "User must have borrowed 10,000 USDC"
        );
        assertEq(
            dUSDC.debtBalanceStored(user1),
            10_000e6,
            "User must have a debt balance of 10,000 USDC"
        );
        assertEq(
            dUSDC.totalBorrows(),
            10_000e6,
            "There must be a total amount of 10,000 USDC borrowed"
        );
    }
}
