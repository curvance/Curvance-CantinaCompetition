// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { PropertiesAsserts } from "tests/fuzzing/helpers/PropertiesHelper.sol";
import { ErrorConstants } from "tests/fuzzing/helpers/ErrorConstants.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import { MockToken } from "contracts/mocks/MockToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { MockV3Aggregator } from "contracts/mocks/MockV3Aggregator.sol";
import { MockCircleRelayer, MockWormhole } from "contracts/mocks/MockCircleRelayer.sol";
import { MockTokenBridgeRelayer } from "contracts/mocks/MockTokenBridgeRelayer.sol";

import { CVE } from "contracts/token/CVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { AuraCToken } from "contracts/market/collateral/AuraCToken.sol";
import { DynamicInterestRateModel } from "contracts/market/DynamicInterestRateModel.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { Zapper } from "contracts/market/zapper/Zapper.sol";
import { PositionFolding } from "contracts/market/leverage/PositionFolding.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

contract StatefulBaseMarket is PropertiesAsserts, ErrorConstants {
    address internal _WETH_ADDRESS;
    address internal _USDC_ADDRESS;
    address internal _RETH_ADDRESS;
    address internal _BALANCER_WETH_RETH;
    address internal _DAI_ADDRESS;

    CVE public cve;
    VeCVE public veCVE;
    CVELocker public cveLocker;
    CentralRegistry public centralRegistry;
    FeeAccumulator public feeAccumulator;
    ProtocolMessagingHub public protocolMessagingHub;
    ChainlinkAdaptor public chainlinkAdaptor;
    ChainlinkAdaptor public dualChainlinkAdaptor;
    DynamicInterestRateModel public InterestRateModel;
    MarketManager public marketManager;
    PositionFolding public positionFolding;
    OracleRouter public oracleRouter;

    AuraCToken public auraCToken;
    AuraCToken public cBALRETH;

    DToken public dUSDC;
    DToken public dDAI;

    MockCToken public cDAI;
    MockCToken public cUSDC;
    MockToken public usdc;
    MockToken public dai;
    MockToken public WETH;
    MockToken public balRETH;
    MockTokenBridgeRelayer public bridgeRelayer;

    MockV3Aggregator public chainlinkUsdcUsd;
    MockV3Aggregator public chainlinkUsdcEth;
    MockV3Aggregator public chainlinkRethEth;
    MockV3Aggregator public chainlinkEthUsd;
    MockV3Aggregator public chainlinkDaiUsd;
    MockV3Aggregator public chainlinkDaiEth;

    MockToken public rewardToken;
    GaugePool public gaugePool;
    PartnerGaugePool public partnerGaugePool;

    address public harvester;
    uint256 public voteBoostMultiplier = 10001; // 110%
    uint256 public lockBoostMultiplier = 10001; // 110%
    uint256 public marketInterestFactor = 1; // 10%

    Zapper public zapper;
<<<<<<< HEAD
=======
    mapping(address => uint256) postedCollateralAt;
    // the maximum collateral cap for a specific mtoken
    mapping(address => uint256) maxCollateralCap;
>>>>>>> b663daca (Cherry-picked f04cff94 for function, helper, and system folders)

    constructor() {
        // _fork(18031848);
        WETH = new MockToken("WETH", "WETH", 18);
        _WETH_ADDRESS = address(WETH);
        usdc = new MockToken("USDC", "USDC", 6);
        _USDC_ADDRESS = address(usdc);
        dai = new MockToken("DAI", "DAI", 18);
        _DAI_ADDRESS = address(dai);
        balRETH = new MockToken("balWethReth", "balWethReth", 18);
        _BALANCER_WETH_RETH = address(balRETH);

        emit LogString("DEPLOYED: centralRegistry");
        _deployCentralRegistry();
        emit LogString("DEPLOYED: CVE");
        _deployCVE();
        emit LogString("DEPLOYED: CVELocker");
        _deployCVELocker();
        emit LogString("DEPLOYED: ProtocolMessagingHub");
        _deployProtocolMessagingHub();
        emit LogString("DEPLOYED: FeeAccumulator");
        _deployFeeAccumulator();

        emit LogString("DEPLOYED: VECVE");
        _deployVeCVE();
        emit LogString("DEPLOYED: Mock Chainlink V3 Aggregator");
        chainlinkEthUsd = new MockV3Aggregator(8, 1500e8, 1e50, 1e6);
        emit LogString("DEPLOYED: OracleRouter");
        _deployOracleRouter();
        _deployChainlinkAdaptors();
        emit LogString("DEPLOYED: GaugePool");
        _deployGaugePool();
        emit LogString("DEPLOYED: MarketManager");
        _deployMarketManager();
        emit LogString("DEPLOYED: DynamicInterestRateModel");
        _deployDynamicInterestRateModel();
        emit LogString("DEPLOYED: DUSDC");
        _deployDUSDC();
        emit LogString("DEPLOYED: DDAI");
        _deployDDAI();
        emit LogString("DEPLOYED: CUSDC");
        _deployCUSDC();
        emit LogString("DEPLOYED: DAI");
        _deployCDAI();
        // emit LogString("DEPLOYED: ZAPPER");
        // _deployZapper();
        emit LogString("DEPLOYED: PositionFolding");
        _deployPositionFolding();
        emit LogString("DEPLOYED: Adding dUSDC to router");
        oracleRouter.addMTokenSupport(address(dUSDC));
        // emit LogString("DEPLOYED: Adding cBalReth to router");
        // oracleRouter.addMTokenSupport(address(cBALRETH));
    }

    function _deployCentralRegistry() internal {
        centralRegistry = new CentralRegistry(
            address(this),
            address(this),
            address(this),
            0,
            address(0),
            address(usdc)
        );
        centralRegistry.transferEmergencyCouncil(address(this));
        centralRegistry.setLockBoostMultiplier(lockBoostMultiplier);
    }

    function _deployCVE() internal {
        bridgeRelayer = new MockTokenBridgeRelayer();
        cve = new CVE(
            ICentralRegistry(address(centralRegistry)),
            address(this)
        );
        centralRegistry.setCVE(address(cve));
    }

    function _deployCVELocker() internal {
        cveLocker = new CVELocker(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );
        centralRegistry.setCVELocker(address(cveLocker));
    }

    function _deployVeCVE() internal {
        veCVE = new VeCVE(ICentralRegistry(address(centralRegistry)));
        centralRegistry.setVeCVE(address(veCVE));
        centralRegistry.setVoteBoostMultiplier(voteBoostMultiplier);
        cveLocker.startLocker();
    }

    function _deployOracleRouter() internal {
        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry)),
            address(chainlinkEthUsd)
        );

        centralRegistry.setOracleRouter(address(oracleRouter));
    }

    function _deployProtocolMessagingHub() internal {
        protocolMessagingHub = new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setProtocolMessagingHub(address(protocolMessagingHub));
    }

    function _deployFeeAccumulator() internal {
        // harvester = makeAddr("harvester");
        harvester = address(this);
        centralRegistry.addHarvester(harvester);

        emit LogUint256("woowowo", 0);
        feeAccumulator = new FeeAccumulator(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            1e9,
            1e9
        );
        centralRegistry.setFeeAccumulator(address(feeAccumulator));
    }

    function _deployChainlinkAdaptors() internal {
        chainlinkUsdcUsd = new MockV3Aggregator(8, 1e8, 1e11, 1e6);
        chainlinkDaiUsd = new MockV3Aggregator(8, 1e8, 1e11, 1e6);
        chainlinkUsdcEth = new MockV3Aggregator(18, 1e18, 1e24, 1e13);
        chainlinkRethEth = new MockV3Aggregator(18, 1e18, 1e24, 1e13);
        chainlinkDaiEth = new MockV3Aggregator(18, 1e18, 1e24, 1e13);

        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(chainlinkEthUsd),
            0,
            true
        );
        chainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcUsd),
            0,
            true
        );
        chainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcEth),
            0,
            false
        );
        chainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiUsd),
            0,
            true
        );
        chainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiEth),
            0,
            false
        );
        chainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(chainlinkRethEth),
            0,
            false
        );

        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _WETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(
            _DAI_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(
            _RETH_ADDRESS,
            address(chainlinkAdaptor)
        );

        dualChainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        dualChainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(chainlinkEthUsd),
            0,
            true
        );

        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcUsd),
            0,
            true
        );

        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcEth),
            0,
            false
        );
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiUsd),
            0,
            true
        );
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiEth),
            0,
            false
        );
        dualChainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(chainlinkRethEth),
            0,
            false
        );
        oracleRouter.addApprovedAdaptor(address(dualChainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _WETH_ADDRESS,
            address(dualChainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(dualChainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(
            _DAI_ADDRESS,
            address(dualChainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(
            _RETH_ADDRESS,
            address(dualChainlinkAdaptor)
        );
    }

    function _deployGaugePool() internal {
        gaugePool = new GaugePool(ICentralRegistry(address(centralRegistry)));
        centralRegistry.addGaugeController(address(gaugePool));

        // Additional logic for partner gauge pool fuzzing logic
        // partnerGaugePool = new PartnerGaugePool(
        //     address(gaugePool),
        //     address(usdc),
        //     ICentralRegistry(address(centralRegistry))
        // );
        // gaugePool.addPartnerGauge(address(partnerGaugePool));
    }

    function _deployMarketManager() internal {
        marketManager = new MarketManager(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );
        centralRegistry.addMarketManager(
            address(marketManager),
            marketInterestFactor
        );
        try gaugePool.start(address(marketManager)) {} catch {
            assertWithMsg(false, "start gauge pool failed");
        }
    }

    function _deployDynamicInterestRateModel() internal {
        // TODO: this can be setup using dynamic values as per fuzzing suite
        InterestRateModel = new DynamicInterestRateModel(
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

    function _deployDUSDC() internal returns (DToken) {
        dUSDC = _deployDToken(_USDC_ADDRESS);
        return dUSDC;
    }

    function _deployDDAI() internal returns (DToken) {
        dDAI = _deployDToken(_DAI_ADDRESS);
        return dDAI;
    }

    function _deployCUSDC() internal returns (MockCToken) {
        cUSDC = new MockCToken(
            ICentralRegistry(address(centralRegistry)),
            IERC20(address(usdc)),
            address(marketManager)
        );
        return cUSDC;
    }

    function _deployCDAI() internal returns (MockCToken) {
        cDAI = new MockCToken(
            ICentralRegistry(address(centralRegistry)),
            IERC20(address(dai)),
            address(marketManager)
        );
        return cDAI;
    }

    function _deployDToken(address token) internal returns (DToken) {
        return
            new DToken(
                ICentralRegistry(address(centralRegistry)),
                token,
                address(marketManager),
                address(InterestRateModel)
            );
    }

    function _deployPositionFolding() internal returns (PositionFolding) {
        positionFolding = new PositionFolding(
            ICentralRegistry(address(centralRegistry)),
            address(marketManager)
        );
        return positionFolding;
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

    MockDataFeed public mockUsdcFeed;
    MockDataFeed public mockDaiFeed;
    bool feedsSetup;
    uint256 lastRoundUpdate;

    function setUpFeeds() public {
        require(centralRegistry.hasElevatedPermissions(address(this)));
        require(gaugePool.startTime() < block.timestamp);
        // use mock pricing for testing
        // StatefulBaseMarket - chainlinkAdaptor - usdc, dai
        mockUsdcFeed = new MockDataFeed(address(chainlinkUsdcUsd));
        chainlinkAdaptor.addAsset(
            address(cUSDC),
            address(mockUsdcFeed),
            0,
            true
        );
        chainlinkAdaptor.addAsset(
            address(dUSDC),
            address(mockUsdcFeed),
            0,
            true
        );

        dualChainlinkAdaptor.addAsset(
            address(cUSDC),
            address(mockUsdcFeed),
            0,
            true
        );
        mockDaiFeed = new MockDataFeed(address(chainlinkDaiUsd));
        chainlinkAdaptor.addAsset(
            address(cDAI),
            address(mockDaiFeed),
            0,
            true
        );
        chainlinkAdaptor.addAsset(
            address(dDAI),
            address(mockDaiFeed),
            0,
            true
        );
        dualChainlinkAdaptor.addAsset(
            address(cDAI),
            address(mockDaiFeed),
            0,
            true
        );

        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkDaiUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        oracleRouter.addMTokenSupport(address(cDAI));
        oracleRouter.addMTokenSupport(address(cUSDC));
        oracleRouter.addMTokenSupport(address(dDAI));
        oracleRouter.addMTokenSupport(address(dUSDC));
        feedsSetup = true;
        lastRoundUpdate = block.timestamp;
    }

    // If the price is stale, update the round data and update lastRoundUpdate
    function check_price_feed() public {
        // if lastRoundUpdate timestamp is stale
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        if (block.timestamp - chainlinkUsdcUsd.latestTimestamp() > 24 hours) {
            // TODO: Change this to a loop to loop over marketManager.assetsOf()
            // Save a mapping of assets -> chainlink oracle
            // call updateRoundData on each oracle
            chainlinkUsdcUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
            chainlinkDaiUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
        }
        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        lastRoundUpdate = block.timestamp;
    }

    MockDataFeed public mockUsdcFeed;
    MockDataFeed public mockDaiFeed;
    bool feedsSetup;
    uint256 lastRoundUpdate;

    function setUpFeeds() public {
        require(centralRegistry.hasElevatedPermissions(address(this)));
        require(gaugePool.startTime() < block.timestamp);
        // use mock pricing for testing
        // StatefulBaseMarket - chainlinkAdaptor - usdc, dai
        mockUsdcFeed = new MockDataFeed(address(chainlinkUsdcUsd));
        chainlinkAdaptor.addAsset(address(cUSDC), address(mockUsdcFeed), true);
        chainlinkAdaptor.addAsset(address(dUSDC), address(mockUsdcFeed), true);

        dualChainlinkAdaptor.addAsset(
            address(cUSDC),
            address(mockUsdcFeed),
            true
        );
        mockDaiFeed = new MockDataFeed(address(chainlinkDaiUsd));
        chainlinkAdaptor.addAsset(address(cDAI), address(mockDaiFeed), true);
        chainlinkAdaptor.addAsset(address(dDAI), address(mockDaiFeed), true);
        dualChainlinkAdaptor.addAsset(
            address(cDAI),
            address(mockDaiFeed),
            true
        );

        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkDaiUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        oracleRouter.addMTokenSupport(address(cDAI));
        oracleRouter.addMTokenSupport(address(cUSDC));
        oracleRouter.addMTokenSupport(address(dDAI));
        oracleRouter.addMTokenSupport(address(dUSDC));
        feedsSetup = true;
        lastRoundUpdate = block.timestamp;
    }

    // If the price is stale, update the round data and update lastRoundUpdate
    function check_price_feed() public {
        // if lastRoundUpdate timestamp is stale
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        if (block.timestamp - chainlinkUsdcUsd.latestTimestamp() > 24 hours) {
            // TODO: Change this to a loop to loop over marketManager.assetsOf()
            // Save a mapping of assets -> chainlink oracle
            // call updateRoundData on each oracle
            chainlinkUsdcUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
            chainlinkDaiUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
        }
        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        lastRoundUpdate = block.timestamp;
    }
}
