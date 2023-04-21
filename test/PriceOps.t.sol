// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { SafeTransferLib } from "src/base/SafeTransferLib.sol";
import { DepositRouterV2 as DepositRouter } from "src/DepositRouterV2.sol";
import { ConvexPositionVault, BasePositionVault } from "src/positions/ConvexPositionVault.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { PriceOps } from "src/PricingOperations/PriceOps.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { ICurvePool } from "src/interfaces/Curve/ICurvePool.sol";
import { UniswapV3Pool } from "src/interfaces/Uniswap/UniswapV3Pool.sol";
import { CurveV1Extension } from "src/PricingOperations/Extensions/CurveV1Extension.sol";
import { CurveV2Extension } from "src/PricingOperations/Extensions/CurveV2Extension.sol";

// import { MockGasFeed } from "src/mocks/MockGasFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract PriceOpsTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    PriceOps private priceOps;
    CurveV1Extension private curveV1Extension;
    CurveV2Extension private curveV2Extension;
    // MockGasFeed private gasFeed;

    address private operatorAlpha = vm.addr(111);
    address private ownerAlpha = vm.addr(1110);
    address private operatorBeta = vm.addr(222);
    address private ownerBeta = vm.addr(2220);

    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Datafeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address private STETH_ETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private USDC_ETH_FEED = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // Uniswap V3 Pools
    address private WBTC_WETH_05_POOL = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0;

    // Curve Assets
    address private CRV_DAI_USDC_USDT = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address private curve3CrvPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address private CRV_3_CRYPTO = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;
    address private curve3CryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;

    ICurvePool stEthEth = ICurvePool(payable(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022));

    function setUp() external {
        // PriceOps.ChainlinkSourceStorage memory stor;
        // stor.inUsd = true;
        // priceOps = new PriceOps(abi.encode(stor));
        // curveV1Extension = new CurveV1Extension(priceOps);
        // curveV2Extension = new CurveV2Extension(priceOps);
        // // WETH-USD
        // // uint64 ethUsdSource = priceOps.addSource(WETH, PriceOps.Descriptor.CHAINLINK, WETH_USD_FEED, abi.encode(stor));
        // // USDC-USD
        // uint64 usdcUsdSource = priceOps.addSource(USDC, PriceOps.Descriptor.CHAINLINK, USDC_USD_FEED, abi.encode(stor));
        // // DAI-USD
        // uint64 daiUsdSource = priceOps.addSource(DAI, PriceOps.Descriptor.CHAINLINK, DAI_USD_FEED, abi.encode(stor));
        // // USDT-USD
        // uint64 usdtUsdSource = priceOps.addSource(USDT, PriceOps.Descriptor.CHAINLINK, USDT_USD_FEED, abi.encode(stor));
        // // STETH-USD
        // uint64 stethUsdSource = priceOps.addSource(
        //     STETH,
        //     PriceOps.Descriptor.CHAINLINK,
        //     STETH_USD_FEED,
        //     abi.encode(stor)
        // );
        // // STETH-ETH
        // stor.inUsd = false;
        // uint64 stethEthSource = priceOps.addSource(
        //     STETH,
        //     PriceOps.Descriptor.CHAINLINK,
        //     STETH_ETH_FEED,
        //     abi.encode(stor)
        // );
        // // uint64 usdcEthSource = priceOps.addSource(USDC, PriceOps.Descriptor.CHAINLINK, USDC_ETH_FEED, abi.encode(stor));
        // // priceOps.addAsset(WETH, ethUsdSource, 0);
        // priceOps.addAsset(USDC, usdcUsdSource, 0);
        // priceOps.addAsset(DAI, daiUsdSource, 0);
        // priceOps.addAsset(USDT, usdtUsdSource, 0);
        // priceOps.addAsset(STETH, stethUsdSource, stethEthSource);
        // UniswapV3Pool(WBTC_WETH_05_POOL).increaseObservationCardinalityNext(3_600);
    }

    // function testPriceOpsHappyPath() external {
    //     (uint256 upper, uint256 lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(STETH);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);

    //     // WBTC-WETH TWAP
    //     PriceOps.TwapSourceStorage memory twapStor;
    //     twapStor.secondsAgo = 600;
    //     twapStor.baseToken = WBTC;
    //     twapStor.quoteToken = WETH;
    //     twapStor.baseDecimals = ERC20(WBTC).decimals();
    //     uint64 wbtcWethSource_600 = priceOps.addSource(
    //         WBTC,
    //         PriceOps.Descriptor.UNIV3_TWAP,
    //         WBTC_WETH_05_POOL,
    //         abi.encode(twapStor)
    //     );
    //     priceOps.addAsset(WBTC, wbtcWethSource_600, 0);

    //     twapStor.secondsAgo = 3_600;
    //     twapStor.baseToken = WBTC;
    //     twapStor.quoteToken = WETH;
    //     twapStor.baseDecimals = ERC20(WBTC).decimals();
    //     uint64 wbtcWethSource_3_600 = priceOps.addSource(
    //         WBTC,
    //         PriceOps.Descriptor.UNIV3_TWAP,
    //         WBTC_WETH_05_POOL,
    //         abi.encode(twapStor)
    //     );
    //     priceOps.addAsset(WBTC, wbtcWethSource_600, wbtcWethSource_3_600);

    //     (upper, lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(WBTC);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);

    //     uint64 crv3PoolSource = priceOps.addSource(
    //         CRV_DAI_USDC_USDT,
    //         PriceOps.Descriptor.EXTENSION,
    //         address(curveV1Extension),
    //         abi.encode(curve3CrvPool)
    //     );

    //     priceOps.addAsset(CRV_DAI_USDC_USDT, crv3PoolSource, 0);

    //     (upper, lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_DAI_USDC_USDT);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);

    //     uint64 crvTriCryptoSource = priceOps.addSource(
    //         CRV_3_CRYPTO,
    //         PriceOps.Descriptor.EXTENSION,
    //         address(curveV2Extension),
    //         abi.encode(curve3CryptoPool)
    //     );

    //     priceOps.addAsset(CRV_3_CRYPTO, crvTriCryptoSource, 0);

    //     (upper, lower, ) = priceOps.getPriceInBaseEnforceNonZeroLower(CRV_3_CRYPTO);
    //     console.log("Upper", upper);
    //     console.log("Lower", lower);
    // }

    function testCurveReentrancy() external {
        ERC20 STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        STETH.approve(address(stEthEth), 10e18);
        // Might need to add liquidity to the pool, then re-enter when I remove liquidity
        stEthEth.exchange{ value: 10 ether }(0, 1, 10 ether, 0);

        console.log("BalanceOf STETH", STETH.balanceOf(address(this)));

        stEthEth.exchange(1, 0, 1e18, 0);
        // stEthEth.exchange{ value: 10 ether }(0, 1, 10 ether, 0);
    }

    receive() external payable {
        console.log("Time for Reentrnacy");
        // stEthEth.exchange{ value: 10 ether }(0, 1, 10 ether, 0);
        ensureNotInVaultContext(address(stEthEth));
    }

    function ensureNotInVaultContext(address curvePool) internal {
        // Perform the following operation to trigger the Vault's reentrancy guard.
        // Use a static call so that it can be a view function (even though the
        // function is non-view).
        //
        // IVault.UserBalanceOp[] memory noop = new IVault.UserBalanceOp[](0);
        // _vault.manageUserBalance(noop);

        // solhint-disable-next-line var-name-mixedcase
        bytes32 REENTRANCY_ERROR_HASH = keccak256(bytes("lock"));

        // read-only re-entrancy protection - this call is always unsuccessful but we need to make sure
        // it didn't fail due to a re-entrancy attack
        (, bytes memory revertData) = curvePool.staticcall(
            abi.encodeWithSelector(ICurvePool.exchange.selector, 1, 0, 1e18, 0)
        );

        console.log("Revert Data Length", revertData.length);

        stEthEth.exchange(1, 0, 1e18, 0);

        if (keccak256(revertData) == REENTRANCY_ERROR_HASH) revert("Reentrancy");
    }
}
