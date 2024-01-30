// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBase } from "tests/utils/TestBase.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { DynamicInterestRateModel } from "contracts/market/DynamicInterestRateModel.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

contract TestBaseOracleRouter is TestBase {
    address internal constant _USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant _CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant _CHAINLINK_USDC_USD =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant _CHAINLINK_USDC_ETH =
        0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;

    CentralRegistry public centralRegistry;
    ChainlinkAdaptor public chainlinkAdaptor;
    ChainlinkAdaptor public dualChainlinkAdaptor;
    DynamicInterestRateModel public interestRateModel;
    MarketManager public marketManager;
    OracleRouter public oracleRouter;
    DToken public mUSDC;
    MockDataFeed public sequencer;

    function setUp() public virtual {
        _fork(18031848);

        _deployCentralRegistry();
        _deployOracleRouter();
        _deployChainlinkAdaptors();

        _deployMarketManager();
        _deployDynamicInterestRateModel();
        _deployMUSDC();
    }

    function _deployCentralRegistry() internal {
        sequencer = new MockDataFeed(address(0));

        centralRegistry = new CentralRegistry(
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            0,
            address(sequencer),
            _USDC_ADDRESS
        );
        centralRegistry.transferEmergencyCouncil(address(this));
    }

    function _deployOracleRouter() internal {
        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry)),
            _CHAINLINK_ETH_USD
        );

        centralRegistry.setOracleRouter(address(oracleRouter));
    }

    function _deployChainlinkAdaptors() internal {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        dualChainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        chainlinkAdaptor.addAsset(_USDC_ADDRESS, _CHAINLINK_USDC_USD, 0, true);
        chainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            _CHAINLINK_USDC_ETH,
            0,
            false
        );

        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            _CHAINLINK_USDC_USD,
            0,
            true
        );
        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            _CHAINLINK_USDC_ETH,
            0,
            false
        );
    }

    function _deployMarketManager() internal {
        GaugePool gaugePool = new GaugePool(
            ICentralRegistry(address(centralRegistry))
        );
        marketManager = new MarketManager(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );
        centralRegistry.addMarketManager(address(marketManager), 0);
    }

    function _deployDynamicInterestRateModel() internal {
        interestRateModel = new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000, // baseRatePerYear
            1000, // vertexRatePerYear
            5000, // vertexUtilizationStart
            12 hours, // adjustmentRate
            5000, // adjustmentVelocity
            100000000, // 1000x maximum vertex multiplier
            100 // decayRate
        );
    }

    function _deployMUSDC() internal {
        mUSDC = new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(marketManager),
            address(interestRateModel)
        );
    }

    function _addSinglePriceFeed() internal {
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function _addDualPriceFeed() internal {
        _addSinglePriceFeed();

        oracleRouter.addApprovedAdaptor(address(dualChainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(dualChainlinkAdaptor)
        );
    }
}
