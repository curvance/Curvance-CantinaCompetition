// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IUniswapV3Router } from "contracts/interfaces/external/uniswap/IUniswapV3Router.sol";
import { IPendleRouter, ApproxParams } from "contracts/interfaces/external/pendle/IPendleRouter.sol";
import { PendleLPCToken, IERC20 } from "contracts/market/collateral/PendleLPCToken.sol";
import { MockCallDataChecker } from "contracts/mocks/MockCallDataChecker.sol";

import "tests/market/TestBaseMarket.sol";

contract TestPendleLPCToken is TestBaseMarket {
    address private _UNISWAP_V3_SWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    IPendleRouter private _ROUTER =
        IPendleRouter(0x0000000001E4ef00d069e71d6bA041b0A16F7eA0);
    address private _STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private _PT_STETH = 0x7758896b6AC966BbABcf143eFA963030f17D3EdF; // PT-stETH-26DEC24
    address private _PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
    IERC20 private _LP_STETH =
        IERC20(0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2); // PT-stETH-26DEC24/SY-stETH Market

    PendleLPCToken cSTETH;

    receive() external payable {}

    fallback() external payable {}

    // this is to use address(this) as mock cToken address
    function tokenType() external pure returns (uint256) {
        return 1;
    }

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();
        _deployVeCVE();
        _deployGaugePool();
        _deployMarketManager();

        centralRegistry.addHarvester(address(this));
        centralRegistry.setFeeAccumulator(address(this));

        cSTETH = new PendleLPCToken(
            ICentralRegistry(address(centralRegistry)),
            _LP_STETH,
            address(marketManager),
            _ROUTER
        );

        centralRegistry.addSwapper(_UNISWAP_V3_SWAP_ROUTER);
        centralRegistry.setExternalCallDataChecker(
            _UNISWAP_V3_SWAP_ROUTER,
            address(new MockCallDataChecker(_UNISWAP_V3_SWAP_ROUTER))
        );

        gaugePool.start(address(marketManager));
        vm.warp(veCVE.nextEpochStartTime());
    }

    // TODO: Rewrite this but limit order api call as recommended by Pendle.
    // function testPendleStethLP() public {
    //     uint256 assets = 100e18;
    //     deal(address(_LP_STETH), user1, assets);
    //     deal(address(_LP_STETH), address(this), 42069);

    //     _LP_STETH.approve(address(cSTETH), 42069);
    //     marketManager.listToken(address(cSTETH));

    //     vm.prank(user1);
    //     _LP_STETH.approve(address(cSTETH), assets);

    //     vm.prank(user1);
    //     cSTETH.deposit(assets, user1);

    //     assertEq(
    //         cSTETH.totalAssets(),
    //         assets + 42069,
    //         "Total Assets should equal user deposit plus initial mint."
    //     );

    //     // Advance time to earn CRV and CVX rewards
    //     vm.warp(block.timestamp + 3 days);

    //     // Mint some extra rewards for Vault.
    //     deal(address(_PENDLE), address(cSTETH), 100e18);
    //     deal(address(cSTETH), 1e18);

    //     uint256 rewardAmount = (100e18 * 84) / 100; // 16% for protocol harvest fee;
    //     SwapperLib.Swap[] memory swaps = new SwapperLib.Swap[](1);
    //     swaps[0].inputToken = _PENDLE;
    //     swaps[0].inputAmount = rewardAmount;
    //     swaps[0].outputToken = _WETH_ADDRESS;
    //     swaps[0].target = _UNISWAP_V3_SWAP_ROUTER;
    //     IUniswapV3Router.ExactInputSingleParams memory params;
    //     params.tokenIn = _PENDLE;
    //     params.tokenOut = _WETH_ADDRESS;
    //     params.fee = 3000;
    //     params.recipient = address(cSTETH);
    //     params.deadline = block.timestamp;
    //     params.amountIn = rewardAmount;
    //     params.amountOutMinimum = 0;
    //     params.sqrtPriceLimitX96 = 0;
    //     swaps[0].call = abi.encodeWithSelector(
    //         IUniswapV3Router.exactInputSingle.selector,
    //         params
    //     );

    //     ApproxParams memory approx;
    //     approx.guessMin = 1e10;
    //     approx.guessMax = 1e18;
    //     approx.guessOffchain = 0;
    //     approx.maxIteration = 200;
    //     approx.eps = 1e18;

    //     cSTETH.harvest(abi.encode(swaps, 0, approx));

    //     vm.warp(block.timestamp + 8 days);

    //     uint256 totalAssets = cSTETH.totalAssets();
    //     assertGt(
    //         totalAssets,
    //         assets + 42069,
    //         "Total Assets should equal user deposit plus initial mint."
    //     );

    //     vm.prank(user1);
    //     cSTETH.withdraw(assets, user1, user1);
    // }

    function testRevertWithInvalidSwapper() external {
        uint256 assets = 100e18;
        deal(address(_LP_STETH), user1, assets);
        deal(address(_LP_STETH), address(this), 42069);

        _LP_STETH.approve(address(cSTETH), 42069);
        marketManager.listToken(address(cSTETH));

        vm.prank(user1);
        _LP_STETH.approve(address(cSTETH), assets);

        vm.prank(user1);
        cSTETH.deposit(assets, user1);

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Mint some extra rewards for Vault.
        deal(address(_PENDLE), address(cSTETH), 100e18);

        uint256 rewardAmount = (100e18 * 84) / 100; // 16% for protocol harvest fee;
        SwapperLib.Swap[] memory swaps = new SwapperLib.Swap[](1);
        swaps[0].inputToken = _PENDLE;
        swaps[0].inputAmount = rewardAmount;
        swaps[0].outputToken = _WETH_ADDRESS;
        swaps[0].target = address(0);

        ApproxParams memory approx;
        approx.guessMin = 1e10;
        approx.guessMax = 1e18;
        approx.guessOffchain = 0;
        approx.maxIteration = 200;
        approx.eps = 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                PendleLPCToken.PendleLPCToken__InvalidSwapper.selector,
                0,
                address(0)
            )
        );
        cSTETH.harvest(abi.encode(swaps, 0, approx));
    }

    function testReQueryRewardTokens() external {
        cSTETH.reQueryRewardTokens();

        assertEq(cSTETH.rewardTokens().length, 1);
    }

    function testReQueryUnderlyingTokens() external {
        cSTETH.reQueryUnderlyingTokens();

        assertEq(cSTETH.underlyingTokens().length, 4);
    }
}
