// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Convex2PoolCToken, IERC20 } from "contracts/market/collateral/Convex2PoolCToken.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CurveAdaptor } from "contracts/oracles/adaptors/curve/CurveAdaptor.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import "tests/market/TestBaseMarket.sol";

contract ConvexLPCollateral is TestBaseMarket {
    event Repay(address payer, address borrower, uint256 repayAmount);

    address internal constant _STETH_ADDRESS =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    // Curve internally uses this address to represent the address for native ETH
    address internal constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IERC20 public CONVEX_STETH_ETH_POOL =
        IERC20(0x21E27a5E5513D6e65C4f830167390997aA84843a);
    uint256 public CONVEX_STETH_ETH_POOL_ID = 177;
    address public CONVEX_STETH_ETH_REWARD =
        0x6B27D7BC63F1999D14fF9bA900069ee516669ee8;
    address public CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    Convex2PoolCToken cSTETH;
    MockV3Aggregator public chainlinkStethUsd;

    function setUp() public override {
        super.setUp();

        gaugePool.start(address(lendtroller));

        cSTETH = new Convex2PoolCToken(
            ICentralRegistry(address(centralRegistry)),
            CONVEX_STETH_ETH_POOL,
            address(lendtroller),
            CONVEX_STETH_ETH_POOL_ID,
            CONVEX_STETH_ETH_REWARD,
            CONVEX_BOOSTER
        );
    }

    function testBorrowWithConvexLPCollateral() public {
        CurveAdaptor crvAdaptor = new CurveAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        crvAdaptor.setReentrancyConfig(2, 50_000);
        crvAdaptor.addAsset(
            address(CONVEX_STETH_ETH_POOL),
            address(CONVEX_STETH_ETH_POOL)
        );
        priceRouter.addApprovedAdaptor(address(crvAdaptor));
        priceRouter.addAssetPriceFeed(
            address(CONVEX_STETH_ETH_POOL),
            address(crvAdaptor)
        );
        chainlinkAdaptor.addAsset(
            ETH_ADDRESS,
            address(chainlinkEthUsd),
            0,
            true
        );
        priceRouter.addAssetPriceFeed(ETH_ADDRESS, address(chainlinkAdaptor));
        chainlinkStethUsd = new MockV3Aggregator(8, 1500e8, 3000e12, 1000e6);
        chainlinkAdaptor.addAsset(
            _STETH_ADDRESS,
            address(chainlinkStethUsd),
            0,
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
        lendtroller.listToken(address(cSTETH));
        SafeTransferLib.safeApprove(_USDC_ADDRESS, address(dUSDC), 1 ether);
        lendtroller.listToken(address(dUSDC));
        lendtroller.updateCollateralToken(
            IMToken(address(cSTETH)),
            7000,
            4000,
            3000,
            200,
            400,
            10,
            1000
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(cSTETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        lendtroller.setCTokenCollateralCaps(tokens, caps);

        // User mints cSTETH with cvxStethEth LP tokens and then uses the cSTETH as collateral to borrow 10,000 dUSDC
        deal(_USDC_ADDRESS, address(dUSDC), 100_000e6);
        deal(address(CONVEX_STETH_ETH_POOL), user1, 10_000e18);
        vm.startPrank(user1);
        CONVEX_STETH_ETH_POOL.approve(address(cSTETH), 1_000e18);

        IBaseRewardPool rewarder = IBaseRewardPool(CONVEX_STETH_ETH_REWARD);

        assertEq(
            rewarder.balanceOf(address(cSTETH)),
            42069,
            "Rewarder must have balance equal to the initial mint"
        );
        assertEq(rewarder.earned(address(cSTETH)), 0);

        cSTETH.deposit(1_000e18, user1);
        lendtroller.postCollateral(user1, address(cSTETH), 1_000e18 - 1);

        assertEq(
            rewarder.balanceOf(address(cSTETH)),
            1000000000000000042069,
            "Convex LP Tokens must be deposited into Rewarder"
        );
        assertEq(rewarder.earned(address(cSTETH)), 0);
        assertEq(cSTETH.balanceOf(user1), 1_000e18);

        dUSDC.borrow(10_000e6);
        vm.stopPrank();

        assertEq(
            usdc.balanceOf(user1),
            10_000e6,
            "User must have borrowed 10,000 USDC"
        );
        assertEq(
            dUSDC.debtBalanceCached(user1),
            10_000e6,
            "User must have a debt balance of 10,000 USDC"
        );
        assertEq(
            dUSDC.totalBorrows(),
            10_000e6,
            "There must be a total amount of 10,000 USDC borrowed"
        );
    }

    function testConvexLPCollateralRepayDebt() public {
        testBorrowWithConvexLPCollateral();
        uint256 prevBalance = usdc.balanceOf(address(dUSDC));
        // User1 needs more funds to be able to repay debt with interest
        usdc.transfer(user1, 1000e6);

        vm.startPrank(user1);
        usdc.approve(address(dUSDC), type(uint256).max);
        vm.expectRevert(Lendtroller.Lendtroller__MinimumHoldPeriod.selector);
        dUSDC.repay(0);

        // Must hold for a minimum of 20 minutes before debt can be repaid
        skip(20 minutes);
        // Pay off full debt including interest
        dUSDC.accrueInterest();
        uint256 debtWithInterest = dUSDC.debtBalanceCached(user1);
        vm.expectEmit(true, true, true, true, address(dUSDC));
        emit Repay(user1, user1, debtWithInterest);
        dUSDC.repay(0);
        vm.stopPrank();

        assertEq(dUSDC.totalBorrows(), 0, "No borrows must be left");
        assertEq(
            dUSDC.debtBalanceCached(user1),
            0,
            "User must have settled debt"
        );
        assertEq(
            usdc.balanceOf(address(dUSDC)),
            debtWithInterest + prevBalance,
            "DToken's balance must include repaid debt plus interest"
        );
    }

    function testConvexLPCollateralRedemption() public {
        testConvexLPCollateralRepayDebt();
        IERC20 cvxPool = CONVEX_STETH_ETH_POOL;
        assertEq(cvxPool.balanceOf(user1), 9_000e18);

        vm.startPrank(user1);

        skip(128 days);
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
        cSTETH.redeem(cSTETH.balanceOf(user1) - 1, user1, user1);
        vm.stopPrank();

        assertEq(cSTETH.balanceOf(user1), 1);
        assertEq(cvxPool.balanceOf(user1), 10_000e18 - 1);
    }
}
