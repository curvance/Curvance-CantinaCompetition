// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { PropertiesAsserts } from "tests/fuzzing/PropertiesHelper.sol";

import { MockToken } from "contracts/mocks/MockToken.sol";
import { MockV3Aggregator } from "contracts/mocks/MockV3Aggregator.sol";
import { MockCircleRelayer, MockWormhole } from "contracts/mocks/MockCircleRelayer.sol";

import { CVE } from "contracts/token/CVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
import { AuraCToken } from "contracts/market/collateral/AuraCToken.sol";
import { DynamicInterestRateModel } from "contracts/market/interestRates/DynamicInterestRateModel.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { Zapper } from "contracts/market/zapper/Zapper.sol";
import { PositionFolding } from "contracts/market/leverage/PositionFolding.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

contract EchidnaBaseMarket is PropertiesAsserts {
    address internal _WETH_ADDRESS;
    address internal _USDC_ADDRESS;
    address internal constant _USDT_ADDRESS =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal _RETH_ADDRESS;
    address internal _BALANCER_WETH_RETH;
    address internal _DAI_ADDRESS;
    address internal constant _WBTC_ADDRESS =
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant _FRAX_ADDRESS =
        0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant _CHAINLINK_ETH_USD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant _CHAINLINK_USDC_USD =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant _CHAINLINK_USDC_ETH =
        0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address internal constant _CHAINLINK_DAI_USD =
        0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address internal constant _CHAINLINK_DAI_ETH =
        0x773616E4d11A78F511299002da57A0a94577F1f4;
    address internal constant _CHAINLINK_RETH_ETH =
        0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address internal constant _BALANCER_VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 internal constant _BAL_WETH_RETH_POOLID =
        0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;
    address internal constant _AURA_BOOSTER =
        0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address internal constant _REWARDER =
        0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;
    address internal constant _WORMHOLE =
        0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
    address internal constant _WORMHOLE_RELAYER =
        0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address internal _CIRCLE_RELAYER;

    CVE public cve;
    VeCVE public veCVE;
    CVELocker public cveLocker;
    CentralRegistry public centralRegistry;
    FeeAccumulator public feeAccumulator;
    ProtocolMessagingHub public protocolMessagingHub;
    BalancerStablePoolAdaptor public balRETHAdapter;
    ChainlinkAdaptor public chainlinkAdaptor;
    ChainlinkAdaptor public dualChainlinkAdaptor;
    DynamicInterestRateModel public InterestRateModel;
    Lendtroller public lendtroller;
    PositionFolding public positionFolding;
    PriceRouter public priceRouter;
    AuraCToken public auraCToken;
    DToken public dUSDC;
    DToken public dDAI;
    AuraCToken public cBALRETH;
    MockToken public usdc;
    MockToken public dai;
    MockToken public WETH;
    MockToken public balRETH;

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
    uint256 public clPointMultiplier = 11000; // 110%
    uint256 public voteBoostMultiplier = 11000; // 110%
    uint256 public lockBoostMultiplier = 10000; // 110%
    uint256 public marketInterestFactor = 1000; // 10%

    Zapper public zapper;

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

        _CIRCLE_RELAYER = address(new MockCircleRelayer(10));

        emit LogString("DEPLOYED: centralRegistry");
        _deployCentralRegistry();
        emit LogString("DEPLOYED: CVE");
        _deployCVE(); // CoreContractSet(@0x3f85D0b6119B38b7E6B119F7550290fec4BE0e3c) from: 0x7c276dcaab99bd16163c1bcce671cad6a1ec0945
        emit LogString("DEPLOYED: CVELocker");
        _deployCVELocker(); //CoreContractSet(@0xd5F051401ca478B34C80D0B5A119e437Dc6D9df5) from: 0x7c276dcaab99bd16163c1bcce671cad6a1ec0945
        emit LogString("DEPLOYED: ProtocolMessagingHub");
        _deployProtocolMessagingHub();
        emit LogString("DEPLOYED: FeeAccumulator");
        _deployFeeAccumulator(); //CoreContractSet(@0x492934308E98b590A626666B703A6dDf2120e85e) from: 0x7c276dcaab99bd16163c1bcce671cad6a1ec0945

        emit LogString("DEPLOYED: VECVE");
        _deployVeCVE(); //CoreContractSet(@0x0A64DF94bc0E039474DB42bb52FEca0c1d540402) from: 0x7c276dcaab99bd16163c1bcce671cad6a1ec0945
        emit LogString("DEPLOYED: Mock Chainlink V3 Aggregator");
        chainlinkEthUsd = new MockV3Aggregator(8, 1500e8, 1e50, 1e6);
        emit LogString("DEPLOYED: PriceRouter");
        _deployPriceRouter(); //CoreContractSet(@0x26C8d09E5C0B423E2827844c770F61c9af2870E7) from: 0x7c276dcaab99bd16163c1bcce671cad6a1ec0945
        // _deployChainlinkAdaptors();
        emit LogString("DEPLOYED: GaugePool");
        _deployGaugePool();
        emit LogString("DEPLOYED: Lendtroller");
        _deployLendtroller();
        emit LogString("DEPLOYED: DynamicInterestRateModel");
        _deployDynamicInterestRateModel();
        emit LogString("DEPLOYED: DUSDC");
        _deployDUSDC();
        emit LogString("DEPLOYED: DDAI");
        _deployDDAI();
        // emit LogString("DEPLOYED: CBALRETH");
        // _deployCBALRETH();
        // emit LogString("DEPLOYED: ZAPPER");
        // _deployZapper();
        emit LogString("DEPLOYED: PositionFolding");
        _deployPositionFolding();
        emit LogString("DEPLOYED: Adding dUSDC to router");
        priceRouter.addMTokenSupport(address(dUSDC));
        // emit LogString("DEPLOYED: Adding cBalReth to router");
        // priceRouter.addMTokenSupport(address(cBALRETH));
    }

    function _deployCentralRegistry() internal {
        centralRegistry = new CentralRegistry(
            address(this),
            address(this),
            address(this),
            0,
            address(this)
        );
        centralRegistry.transferEmergencyCouncil(address(this));
        centralRegistry.setLockBoostMultiplier(lockBoostMultiplier);
    }

    function _deployCVE() internal {
        cve = new CVE(
            ICentralRegistry(address(centralRegistry)),
            address(this),
            10000 ether,
            10000 ether,
            10000 ether,
            10000 ether
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
        veCVE = new VeCVE(
            ICentralRegistry(address(centralRegistry)),
            clPointMultiplier
        );
        centralRegistry.setVeCVE(address(veCVE));
        centralRegistry.setVoteBoostMultiplier(voteBoostMultiplier);
        cveLocker.startLocker();
    }

    function _deployPriceRouter() internal {
        priceRouter = new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            address(chainlinkEthUsd)
        );

        centralRegistry.setPriceRouter(address(priceRouter));
    }

    function _deployProtocolMessagingHub() internal {
        protocolMessagingHub = new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER
        );
        centralRegistry.setProtocolMessagingHub(address(protocolMessagingHub));
    }

    function _deployFeeAccumulator() internal {
        // harvester = makeAddr("harvester");
        harvester = address(this);
        centralRegistry.addHarvester(harvester);

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
            true
        );
        chainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcUsd),
            true
        );
        chainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcEth),
            false
        );
        chainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiUsd),
            true
        );
        chainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiEth),
            false
        );
        chainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(chainlinkRethEth),
            false
        );

        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(
            _WETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
        priceRouter.addAssetPriceFeed(_DAI_ADDRESS, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(
            _RETH_ADDRESS,
            address(chainlinkAdaptor)
        );

        dualChainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );

        dualChainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(chainlinkEthUsd),
            true
        );

        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcUsd),
            true
        );

        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(chainlinkUsdcEth),
            false
        );
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiUsd),
            true
        );
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(chainlinkDaiEth),
            false
        );
        dualChainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(chainlinkRethEth),
            false
        );
        priceRouter.addApprovedAdaptor(address(dualChainlinkAdaptor));
        priceRouter.addAssetPriceFeed(
            _WETH_ADDRESS,
            address(dualChainlinkAdaptor)
        );
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(dualChainlinkAdaptor)
        );
        priceRouter.addAssetPriceFeed(
            _DAI_ADDRESS,
            address(dualChainlinkAdaptor)
        );
        priceRouter.addAssetPriceFeed(
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
        priceRouter.addApprovedAdaptor(address(balRETHAdapter));
        priceRouter.addAssetPriceFeed(
            _BALANCER_WETH_RETH,
            address(balRETHAdapter)
        );
    }

    function _deployGaugePool() internal {
        gaugePool = new GaugePool(ICentralRegistry(address(centralRegistry)));
        centralRegistry.addGaugeController(address(gaugePool));
    }

    function _deployLendtroller() internal {
        lendtroller = new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );
        centralRegistry.addLendingMarket(
            address(lendtroller),
            marketInterestFactor
        );
    }

    function _deployDynamicInterestRateModel() internal {
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

    function _deployDToken(address token) internal returns (DToken) {
        return
            new DToken(
                ICentralRegistry(address(centralRegistry)),
                token,
                address(lendtroller),
                address(InterestRateModel)
            );
    }

    function _deployCBALRETH() internal returns (AuraCToken) {
        cBALRETH = new AuraCToken(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(lendtroller),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );
        return cBALRETH;
    }

    function _deployZapper() internal returns (Zapper) {
        zapper = new Zapper(
            ICentralRegistry(address(centralRegistry)),
            address(lendtroller),
            _WETH_ADDRESS
        );
        centralRegistry.addZapper(address(zapper));
        return zapper;
    }

    function _deployPositionFolding() internal returns (PositionFolding) {
        positionFolding = new PositionFolding(
            ICentralRegistry(address(centralRegistry)),
            address(lendtroller)
        );
        return positionFolding;
    }

    function _addSinglePriceFeed() internal {
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function _addDualPriceFeed() internal {
        _addSinglePriceFeed();

        priceRouter.addApprovedAdaptor(address(dualChainlinkAdaptor));
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(dualChainlinkAdaptor)
        );
    }

    function _prepareUSDC(address user, uint256 amount) internal {
        // deal(_USDC_ADDRESS, user, amount);
    }

    function _prepareDAI(address user, uint256 amount) internal {
        // deal(_DAI_ADDRESS, user, amount);
    }

    function _prepareBALRETH(address user, uint256 amount) internal {
        // deal(_BALANCER_WETH_RETH, user, amount);
    }

    function _setCbalRETHCollateralCaps(uint256 cap) internal {
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000,
            3000,
            3000,
            2000,
            2000,
            100,
            1000
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(cBALRETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;
        lendtroller.setCTokenCollateralCaps(tokens, caps);
    }

    function test_assert() public {
        assert(false);
    }
}
