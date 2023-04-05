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
// import { MockGasFeed } from "src/mocks/MockGasFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract PriceOpsTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    PriceOps private priceOps;
    DepositRouter private router;
    ConvexPositionVault private cvxPositionTriCrypto;
    ConvexPositionVault private cvxPosition3Pool;
    // MockGasFeed private gasFeed;

    address private operatorAlpha = vm.addr(111);
    address private ownerAlpha = vm.addr(1110);
    address private operatorBeta = vm.addr(222);
    address private ownerBeta = vm.addr(2220);

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // Datafeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address private STETH_ETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    function setUp() external {
        // gasFeed = new MockGasFeed();
        priceOps = new PriceOps();
        // Set heart beat to 5 days so we don't run into stale price reverts.
        PriceOps.ChainlinkSourceStorage memory stor;

        // WETH-USD
        uint64 ethUsdSource = priceOps.addSource(WETH, PriceOps.Descriptor.CHAINLINK, WETH_USD_FEED, abi.encode(stor));

        // STETH-USD
        uint64 stethUsdSource = priceOps.addSource(
            STETH,
            PriceOps.Descriptor.CHAINLINK,
            STETH_USD_FEED,
            abi.encode(stor)
        );

        // STETH-ETH
        stor.inETH = true;
        uint64 stethEthSource = priceOps.addSource(
            STETH,
            PriceOps.Descriptor.CHAINLINK,
            STETH_ETH_FEED,
            abi.encode(stor)
        );

        priceOps.addAsset(WETH, ethUsdSource, 0);
        priceOps.addAsset(STETH, stethUsdSource, stethEthSource);
    }

    function testPriceOpsHappyPath() external {
        (uint256 upper, uint256 lower) = priceOps.getPriceInBase(STETH);
        console.log("Upper", upper);
        console.log("Lower", lower);
    }
}
