// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { Zapper } from "contracts/market/zapper/Zapper.sol";
import { ZapperSimple } from "contracts/market/zapper/ZapperSimple.sol";
import { Convex2PoolCToken, IERC20 } from "contracts/market/collateral/Convex2PoolCToken.sol";
import { Curve2PoolLPAdaptor } from "contracts/oracles/adaptors/curve/Curve2PoolLPAdaptor.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";
import { IUniswapV3Router } from "contracts/interfaces/external/uniswap/IUniswapV3Router.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestZapperSimple is TestBaseMarket {
    address private _UNISWAP_V3_SWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address _CURVE_STETH_LP = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
    address _CURVE_STETH_MINTER = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
    address _STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    IERC20 public CONVEX_STETH_ETH_POOL =
        IERC20(0x21E27a5E5513D6e65C4f830167390997aA84843a);
    uint256 public CONVEX_STETH_ETH_POOL_ID = 177;
    address public CONVEX_STETH_ETH_REWARD =
        0x6B27D7BC63F1999D14fF9bA900069ee516669ee8;
    address public CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    address public owner;
    address public user;

    Convex2PoolCToken public cSTETH;
    ZapperSimple public zapperSimple;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        owner = address(this);
        user = user1;

        zapperSimple = new ZapperSimple(
            ICentralRegistry(address(centralRegistry)),
            address(marketManager),
            _WETH_ADDRESS
        );
        centralRegistry.addZapper(address(zapperSimple));

        centralRegistry.addHarvester(address(this));
        centralRegistry.setFeeAccumulator(address(this));

        // set price oracle
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            address(chainlinkEthUsd),
            0,
            true
        );
        chainlinkAdaptor.addAsset(
            _STETH_ADDRESS,
            address(chainlinkEthUsd),
            0,
            true
        );

        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(
            _STETH_ADDRESS,
            address(chainlinkAdaptor)
        );

        Curve2PoolLPAdaptor adaptor = new Curve2PoolLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adaptor.setReentrancyConfig(2, 10000);
        Curve2PoolLPAdaptor.AdaptorData memory data;
        data.pool = _CURVE_STETH_LP;
        data
            .underlyingOrConstituent0 = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        data.underlyingOrConstituent1 = _STETH_ADDRESS;
        data.divideRate0 = true;
        data.divideRate1 = true;
        data.isCorrelated = true;
        data.upperBound = 10200;
        data.lowerBound = 10000;
        adaptor.addAsset(_CURVE_STETH_LP, data);

        oracleRouter.addApprovedAdaptor(address(adaptor));
        oracleRouter.addAssetPriceFeed(_CURVE_STETH_LP, address(adaptor));

        // start epoch
        gaugePool.start(address(marketManager));
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        chainlinkEthUsd.updateRoundData(
            0,
            1500e8,
            block.timestamp,
            block.timestamp
        );

        // deploy cSTETH
        cSTETH = new Convex2PoolCToken(
            ICentralRegistry(address(centralRegistry)),
            CONVEX_STETH_ETH_POOL,
            address(marketManager),
            CONVEX_STETH_ETH_POOL_ID,
            CONVEX_STETH_ETH_REWARD,
            CONVEX_BOOSTER
        );

        deal(address(CONVEX_STETH_ETH_POOL), address(owner), 1 ether);
        CONVEX_STETH_ETH_POOL.approve(address(cSTETH), 1 ether);
        marketManager.listToken(address(cSTETH));
        oracleRouter.addMTokenSupport(address(cSTETH));

        marketManager.updateCollateralToken(
            IMToken(address(cSTETH)),
            5000,
            1500,
            1200,
            200,
            400,
            10,
            1000
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(cSTETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        marketManager.setCTokenCollateralCaps(tokens, caps);

        // deploy dDAI
        {
            // support market
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            marketManager.listToken(address(dDAI));
            // add MToken support on price router
            oracleRouter.addMTokenSupport(address(dDAI));
        }

        address liquidityProvider = makeAddr("liquidityProvider");
        _prepareDAI(liquidityProvider, 1000 ether);
        // mint dDAI
        vm.startPrank(liquidityProvider);
        dai.approve(address(dDAI), 1000 ether);
        dDAI.mint(1000 ether);

        chainlinkDaiUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
    }

    function testInitialize() public {
        assertEq(address(zapper.marketManager()), address(marketManager));
    }

    function testZapAndDeposit() public {
        uint256 ethAmount = 3 ether;
        vm.deal(user, ethAmount);

        SwapperLib.ZapperCall memory zapperCall;
        zapperCall.inputToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        zapperCall.inputAmount = ethAmount;
        zapperCall.target = address(zapper);

        address[] memory tokens = new address[](2);
        tokens[0] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        tokens[1] = _STETH_ADDRESS;
        zapperCall.call = abi.encodeWithSelector(
            Zapper.curveIn.selector,
            address(0),
            Zapper.ZapperData(
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                ethAmount,
                _CURVE_STETH_LP,
                1,
                false
            ),
            new SwapperLib.Swap[](0),
            _CURVE_STETH_MINTER,
            tokens,
            address(zapperSimple)
        );

        vm.startPrank(user);
        zapperSimple.zapAndDeposit{ value: ethAmount }(
            zapperCall,
            address(cSTETH),
            user
        );
        vm.stopPrank();

        assertEq(user.balance, 0);
        assertGt(cSTETH.balanceOf(user), 0);
    }

    function testSwapAndRepay() external {
        testZapAndDeposit();
        vm.startPrank(user);
        marketManager.postCollateral(user, address(cSTETH), 1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user);
        dDAI.borrow(500 ether);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), 500 ether);
        assertApproxEqAbs(dDAI.debtBalanceCached(user), 500 ether, 1 ether);

        // skip min hold period
        skip(20 minutes);

        centralRegistry.addSwapper(_UNISWAP_V3_SWAP_ROUTER);
        centralRegistry.setExternalCallDataChecker(
            _UNISWAP_V3_SWAP_ROUTER,
            address(new MockCallDataChecker(_UNISWAP_V3_SWAP_ROUTER))
        );

        SwapperLib.Swap memory swapData;
        swapData.inputToken = _USDC_ADDRESS;
        swapData.inputAmount = 500e6;
        swapData.outputToken = _DAI_ADDRESS;
        swapData.target = _UNISWAP_V3_SWAP_ROUTER;
        IUniswapV3Router.ExactInputSingleParams memory params;
        params.tokenIn = _USDC_ADDRESS;
        params.tokenOut = _DAI_ADDRESS;
        params.fee = 100;
        params.recipient = address(zapperSimple);
        params.deadline = block.timestamp;
        params.amountIn = 500e6;
        params.amountOutMinimum = 0;
        params.sqrtPriceLimitX96 = 0;
        swapData.call = abi.encodeWithSelector(
            IUniswapV3Router.exactInputSingle.selector,
            params
        );

        deal(_USDC_ADDRESS, user, 500e6);
        vm.startPrank(user);
        IERC20(_USDC_ADDRESS).approve(address(zapperSimple), 500e6);
        zapperSimple.swapAndRepay(swapData, address(dDAI), 450e18, user);
        vm.stopPrank();

        assertApproxEqAbs(dai.balanceOf(user), 550 ether, 1 ether);
        assertApproxEqAbs(dDAI.debtBalanceCached(user), 50 ether, 1 ether);
    }
}
