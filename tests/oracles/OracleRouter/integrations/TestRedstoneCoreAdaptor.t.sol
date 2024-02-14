// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { EthereumRedstoneCoreAdaptor } from "contracts/oracles/adaptors/redstone/EthereumRedstoneCoreAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";

contract TestRedstoneCoreAdaptor is TestBaseOracleRouter {
    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    EthereumRedstoneCoreAdaptor public adapter;

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setOracleRouter(address(oracleRouter));

        adapter = new EthereumRedstoneCoreAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adapter.addAsset(WBTC, true, 18);

        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        oracleRouter.addApprovedAdaptor(address(adapter));
        oracleRouter.addAssetPriceFeed(WBTC, address(adapter));
    }

    function testReturnsCorrectPrice() public {
        // (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
        //     WBTC,
        //     true,
        //     false
        // );
        // assertEq(errorCode, 0);
        // assertGt(price, 0);
    }
}
