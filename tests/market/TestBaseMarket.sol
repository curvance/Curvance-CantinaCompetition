// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { MockToken } from "contracts/mocks/MockToken.sol";
import { MockV3Aggregator } from "contracts/mocks/MockV3Aggregator.sol";
import { TestBase } from "tests/utils/TestBase.sol";

import { CVE } from "contracts/token/CVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { SimpleRewardZapper } from "contracts/architecture/utils/SimpleRewardZapper.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { OneBalanceFeeManager } from "contracts/architecture/OneBalanceFeeManager.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { AuraCToken } from "contracts/market/collateral/AuraCToken.sol";
import { DynamicInterestRateModel } from "contracts/market/DynamicInterestRateModel.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { ComplexZapper } from "contracts/market/utils/ComplexZapper.sol";
import { PositionFolding } from "contracts/market/utils/PositionFolding.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { MockTokenBridgeRelayer } from "contracts/mocks/MockTokenBridgeRelayer.sol";
import { MockAuraCTokenWithExitFee } from "contracts/mocks/MockAuraCTokenWithExitFee.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract TestBaseMarket is TestBase {
    address internal _ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal _WETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal _USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal _USDT_ADDRESS =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal _RETH_ADDRESS =
        0xae78736Cd615f374D3085123A210448E74Fc6393;
    address internal _BALANCER_WETH_RETH =
        0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    address internal _DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal _WBTC_ADDRESS =
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal _FRAX_ADDRESS =
        0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal _CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal _CHAINLINK_USDC_USD =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal _CHAINLINK_USDC_ETH =
        0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address internal _CHAINLINK_DAI_USD =
        0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address internal _CHAINLINK_DAI_ETH =
        0x773616E4d11A78F511299002da57A0a94577F1f4;
    address internal _CHAINLINK_RETH_ETH =
        0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address internal _BALANCER_VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 internal _BAL_WETH_RETH_POOLID =
        0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;
    address internal _AURA_BOOSTER =
        0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address internal _REWARDER = 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;
    address internal _WORMHOLE_CORE =
        0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
    address internal _WORMHOLE_RELAYER =
        0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address internal _CIRCLE_TOKEN_MESSENGER =
        0xBd3fa81B58Ba92a82136038B25aDec7066af3155;
    address internal _TOKEN_BRIDGE =
        0x3ee18B2214AFF97000D974cf647E7C347E8fa585;
    address internal _GELATO_ONE_BALANCE =
        0x7506C12a824d73D9b08564d5Afc22c949434755e;

    CVE public cve;
    VeCVE public veCVE;
    CVELocker public cveLocker;
    SimpleRewardZapper public simpleRewardZapper;
    CentralRegistry public centralRegistry;
    FeeAccumulator public feeAccumulator;
    ProtocolMessagingHub public protocolMessagingHub;
    OneBalanceFeeManager public oneBalanceFeeManager;
    BalancerStablePoolAdaptor public balRETHAdapter;
    ChainlinkAdaptor public chainlinkAdaptor;
    ChainlinkAdaptor public dualChainlinkAdaptor;
    DynamicInterestRateModel public interestRateModel;
    MarketManager public marketManager;
    PositionFolding public positionFolding;
    OracleRouter public oracleRouter;
    DToken public dUSDC;
    DToken public dDAI;
    AuraCToken public cBALRETH;
    MockAuraCTokenWithExitFee public cBALRETHWithExitFee;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public balRETH;

    MockV3Aggregator public chainlinkUsdcUsd;
    MockV3Aggregator public chainlinkUsdcEth;
    MockV3Aggregator public chainlinkRethEth;
    MockV3Aggregator public chainlinkEthUsd;
    MockV3Aggregator public chainlinkDaiUsd;
    MockV3Aggregator public chainlinkDaiEth;

    MockToken public rewardToken;
    GaugePool public gaugePool;

    address public harvester;
    address public randomUser = address(1000000);
    address public user1 = address(1000001);
    address public user2 = address(1000002);
    address public liquidator = address(1000003);
    uint256 public voteBoostMultiplier = 11000; // 110%
    uint256 public lockBoostMultiplier = 10000; // 110%
    uint256 public marketInterestFactor = 1000; // 10%

    ComplexZapper public complexZapper;

    function setUp() public virtual {
        _fork(18031848);

        _init();
    }

    function _init() internal {
        usdc = IERC20(_USDC_ADDRESS);
        dai = IERC20(_DAI_ADDRESS);
        balRETH = IERC20(_BALANCER_WETH_RETH);

        _deployBaseContracts();

        chainlinkEthUsd = new MockV3Aggregator(8, 1500e8, 1e50, 1e6);
        _deployOracleRouter();
        _deployChainlinkAdaptors();
        _deployGaugePool();

        _deployMarketManager();
        _deployDynamicInterestRateModel();
        _deployDUSDC();
        _deployDDAI();
        _deployCBALRETH();
        _deployCBALRETHWithExitFee();

        _deployComplexZapper();
        _deployPositionFolding();

        oracleRouter.addMTokenSupport(address(dUSDC));
        oracleRouter.addMTokenSupport(address(cBALRETH));
        oracleRouter.addMTokenSupport(address(cBALRETHWithExitFee));
    }

    function _deployBaseContracts() internal {
        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();
        _deployVeCVE();
        _deployProtocolMessagingHub();
        _deployOneBalanceFeeManager();
        _deployFeeAccumulator();
    }

    function _deployCentralRegistry() internal {
        centralRegistry = new CentralRegistry(
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            0,
            address(0),
            _USDC_ADDRESS
        );
        centralRegistry.transferEmergencyCouncil(address(this));
        centralRegistry.setLockBoostMultiplier(lockBoostMultiplier);
        centralRegistry.setCircleTokenMessenger(_CIRCLE_TOKEN_MESSENGER);
        centralRegistry.setWormholeRelayer(_WORMHOLE_RELAYER);
        centralRegistry.setWormholeCore(_WORMHOLE_CORE);
        centralRegistry.setTokenBridge(_TOKEN_BRIDGE);
        centralRegistry.setGelatoSponsor(address(1));

        uint256[] memory chainIds = new uint256[](3);
        uint16[] memory wormholeChainIds = new uint16[](3);
        uint32[] memory cctpDomains = new uint32[](3);

        chainIds[0] = 1;
        wormholeChainIds[0] = 2;
        cctpDomains[0] = 0;
        chainIds[1] = 137;
        wormholeChainIds[1] = 5;
        cctpDomains[1] = 7;
        chainIds[2] = 42161;
        wormholeChainIds[2] = 23;
        cctpDomains[2] = 3;

        centralRegistry.registerWormholeChainIDs(chainIds, wormholeChainIds);
        centralRegistry.registerCCTPDomains(chainIds, cctpDomains);
    }

    function _deployCVE() internal {
        // If TokenBridgeRelayer doesn't exist on the address,
        // deploy mock TokenBridgeRelayer on the address.
        if (_TOKEN_BRIDGE.code.length == 0) {
            vm.etch(_TOKEN_BRIDGE, address(new MockTokenBridgeRelayer()).code);
        }

        cve = new CVE(ICentralRegistry(address(centralRegistry)), address(0));
        centralRegistry.setCVE(address(cve));
    }

    function _deployCVELocker() internal {
        cveLocker = new CVELocker(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );
        centralRegistry.setCVELocker(address(cveLocker));

        simpleRewardZapper = new SimpleRewardZapper(
            ICentralRegistry(address(centralRegistry)),
            _WETH_ADDRESS
        );
    }

    function _deployVeCVE() internal {
        veCVE = new VeCVE(ICentralRegistry(address(centralRegistry)));
        centralRegistry.setVeCVE(address(veCVE));
        centralRegistry.setVoteBoostMultiplier(voteBoostMultiplier);
        cveLocker.startLocker();
    }

    function _deployOracleRouter() internal {
        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );

        centralRegistry.setOracleRouter(address(oracleRouter));
    }

    function _deployProtocolMessagingHub() internal {
        protocolMessagingHub = new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry))
        );
        centralRegistry.setProtocolMessagingHub(address(protocolMessagingHub));
    }

    function _deployOneBalanceFeeManager() internal {
        oneBalanceFeeManager = new OneBalanceFeeManager(
            ICentralRegistry(address(centralRegistry)),
            _GELATO_ONE_BALANCE,
            address(1)
        );
    }

    function _deployFeeAccumulator() internal {
        harvester = makeAddr("harvester");
        centralRegistry.addHarvester(harvester);

        feeAccumulator = new FeeAccumulator(
            ICentralRegistry(address(centralRegistry)),
            address(oneBalanceFeeManager),
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
            _ETH_ADDRESS,
            address(chainlinkEthUsd),
            0,
            true
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
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
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

        balRETHAdapter = new BalancerStablePoolAdaptor(
            ICentralRegistry(address(centralRegistry)),
            IVault(_BALANCER_VAULT)
        );
        BalancerStablePoolAdaptor.AdaptorData memory adapterData;
        adapterData.poolId = _BAL_WETH_RETH_POOLID;
        adapterData.poolDecimals = 18;
        adapterData.rateProviderDecimals[0] = 18;
        adapterData.rateProviders[
                0
            ] = 0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F;
        adapterData.underlyingOrConstituent[0] = _RETH_ADDRESS;
        adapterData.underlyingOrConstituent[1] = _WETH_ADDRESS;
        balRETHAdapter.addAsset(_BALANCER_WETH_RETH, adapterData);
        oracleRouter.addApprovedAdaptor(address(balRETHAdapter));
        oracleRouter.addAssetPriceFeed(
            _BALANCER_WETH_RETH,
            address(balRETHAdapter)
        );
    }

    function _deployGaugePool() internal {
        gaugePool = new GaugePool(ICentralRegistry(address(centralRegistry)));
        centralRegistry.addGaugeController(address(gaugePool));
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

    function _deployDUSDC() internal returns (DToken) {
        dUSDC = _deployDToken(_USDC_ADDRESS);
        return dUSDC;
    }

    function _deployDDAI() internal returns (DToken) {
        dDAI = _deployDToken(_DAI_ADDRESS);
        return dDAI;
    }

    function _deployDToken(address token) internal returns (DToken) {
        return
            new DToken(
                ICentralRegistry(address(centralRegistry)),
                token,
                address(marketManager),
                address(interestRateModel)
            );
    }

    function _deployCBALRETH() internal returns (AuraCToken) {
        cBALRETH = new AuraCToken(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );
        return cBALRETH;
    }

    function _deployCBALRETHWithExitFee()
        internal
        returns (MockAuraCTokenWithExitFee)
    {
        cBALRETHWithExitFee = new MockAuraCTokenWithExitFee(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER,
            200
        );
        return cBALRETHWithExitFee;
    }

    function _deployComplexZapper() internal returns (ComplexZapper) {
        complexZapper = new ComplexZapper(
            ICentralRegistry(address(centralRegistry)),
            address(marketManager),
            _WETH_ADDRESS
        );
        centralRegistry.addZapper(address(complexZapper));
        return complexZapper;
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

    function _prepareUSDC(address user, uint256 amount) internal {
        deal(_USDC_ADDRESS, user, amount);
    }

    function _prepareDAI(address user, uint256 amount) internal {
        deal(_DAI_ADDRESS, user, amount);
    }

    function _prepareBALRETH(address user, uint256 amount) internal {
        deal(_BALANCER_WETH_RETH, user, amount);
    }

    function _setCbalRETHCollateralCaps(uint256 cap) internal {
        marketManager.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000,
            4000,
            3000,
            200, // 2% liq incentive
            400,
            0,
            1000
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(cBALRETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;
        marketManager.setCTokenCollateralCaps(tokens, caps);
    }
}
