// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { BorrowZapper } from "contracts/market/utils/BorrowZapper.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";

import { ITokenBridgeRelayer } from "contracts/interfaces/external/wormhole/ITokenBridgeRelayer.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IUniswapV3Router } from "contracts/interfaces/external/uniswap/IUniswapV3Router.sol";

contract TestBorrowAndBridge is TestBaseMarket {
    address private _UNISWAP_V3_SWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ITokenBridgeRelayer public tokenBridgeRelayer =
        ITokenBridgeRelayer(_TOKEN_BRIDGE_RELAYER);

    address public owner;

    MockDataFeed public mockDaiFeed;
    MockDataFeed public mockWethFeed;
    MockDataFeed public mockRethFeed;

    BorrowZapper public borrowZapper;

    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        owner = address(this);

        // use mock pricing for testing
        mockDaiFeed = new MockDataFeed(_CHAINLINK_DAI_USD);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, address(mockDaiFeed), 0, true);
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(mockDaiFeed),
            0,
            true
        );
        mockWethFeed = new MockDataFeed(_CHAINLINK_ETH_USD);
        chainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(mockWethFeed),
            0,
            true
        );
        dualChainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(mockWethFeed),
            0,
            true
        );
        mockRethFeed = new MockDataFeed(_CHAINLINK_RETH_ETH);
        chainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(mockRethFeed),
            0,
            false
        );
        dualChainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(mockRethFeed),
            0,
            false
        );

        // start epoch
        gaugePool.start(address(marketManager));
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockWethFeed.setMockUpdatedAt(block.timestamp);
        mockRethFeed.setMockUpdatedAt(block.timestamp);

        (, int256 ethPrice, , , ) = mockWethFeed.latestRoundData();
        chainlinkEthUsd.updateAnswer(ethPrice);

        // setup dDAI
        {
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            marketManager.listToken(address(dDAI));
            // add MToken support on price router
            oracleRouter.addMTokenSupport(address(dDAI));
        }

        // setup CBALRETH
        {
            // support market
            _prepareBALRETH(owner, _ONE);
            balRETH.approve(address(cBALRETH), _ONE);
            marketManager.listToken(address(cBALRETH));
            // set collateral factor
            marketManager.updateCollateralToken(
                IMToken(address(cBALRETH)),
                7000,
                4000,
                3000,
                200,
                400,
                10,
                1000
            );
            address[] memory tokens = new address[](1);
            tokens[0] = address(cBALRETH);
            uint256[] memory caps = new uint256[](1);
            caps[0] = 100_000e18;
            marketManager.setCTokenCollateralCaps(tokens, caps);
        }

        // provide enough liquidity
        _provideEnoughLiquidityForLeverage();

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(42161);
        wormholeChainIDs.push(23);

        centralRegistry.registerWormholeChainIDs(chainIDs, wormholeChainIDs);

        ITokenBridgeRelayer.SwapRateUpdate[]
            memory swapRateUpdate = new ITokenBridgeRelayer.SwapRateUpdate[](
                1
            );
        swapRateUpdate[0] = ITokenBridgeRelayer.SwapRateUpdate({
            token: address(cve),
            value: 10e8
        });

        vm.startPrank(tokenBridgeRelayer.owner());
        tokenBridgeRelayer.registerToken(2, address(cve));
        tokenBridgeRelayer.updateSwapRate(2, swapRateUpdate);
        vm.stopPrank();

        deal(user1, _ONE);

        borrowZapper = new BorrowZapper(
            ICentralRegistry(address(centralRegistry))
        );
    }

    function _provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = makeAddr("liquidityProvider");
        _prepareDAI(liquidityProvider, 200000e18);
        _prepareBALRETH(liquidityProvider, 10e18);
        // mint dDAI
        vm.startPrank(liquidityProvider);
        dai.approve(address(dDAI), 200000e18);
        dDAI.mint(200000e18);
        // mint cBALETH
        balRETH.approve(address(cBALRETH), 10e18);
        cBALRETH.deposit(10e18, liquidityProvider);
        vm.stopPrank();
    }

    function testDTokenBorrowAndBridge() public {
        _prepareBALRETH(user1, _ONE);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), _ONE);
        cBALRETH.deposit(_ONE, user1);
        marketManager.postCollateral(user1, address(cBALRETH), _ONE);
        vm.stopPrank();

        assertEq(cBALRETH.balanceOf(user1), _ONE);
        assertEq(cBALRETH.exchangeRateCached(), _ONE);

        centralRegistry.addSwapper(_UNISWAP_V3_SWAP_ROUTER);
        centralRegistry.setExternalCallDataChecker(
            _UNISWAP_V3_SWAP_ROUTER,
            address(new MockCallDataChecker(_UNISWAP_V3_SWAP_ROUTER))
        );

        SwapperLib.Swap memory swapData;
        swapData.inputToken = _DAI_ADDRESS;
        swapData.inputAmount = 500e18;
        swapData.outputToken = _USDC_ADDRESS;
        swapData.target = _UNISWAP_V3_SWAP_ROUTER;
        IUniswapV3Router.ExactInputSingleParams memory params;
        params.tokenIn = _DAI_ADDRESS;
        params.tokenOut = _USDC_ADDRESS;
        params.fee = 3000;
        params.recipient = address(borrowZapper);
        params.deadline = block.timestamp;
        params.amountIn = 500e18;
        params.amountOutMinimum = 0;
        params.sqrtPriceLimitX96 = 0;
        swapData.call = abi.encodeWithSelector(
            IUniswapV3Router.exactInputSingle.selector,
            params
        );

        uint256 messageFee = borrowZapper.quoteWormholeFee(23, false);

        // try borrow()
        vm.startPrank(user1);

        dDAI.setBorrowApproval(address(borrowZapper), true);
        borrowZapper.borrowAndBridge{ value: messageFee }(
            address(dDAI),
            500e18,
            swapData,
            42161
        );
        dDAI.borrow(500e18);

        vm.stopPrank();
    }
}
