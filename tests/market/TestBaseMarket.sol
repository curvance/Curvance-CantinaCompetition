// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBase } from "tests/utils/TestBase.sol";
import { CVE } from "contracts/token/CVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { InterestRateModel } from "contracts/market/interestRates/InterestRateModel.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract TestBaseMarket is TestBase {
    address internal constant _WETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant _USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant _RETH_ADDRESS =
        0xae78736Cd615f374D3085123A210448E74Fc6393;
    address internal constant _BALANCER_WETH_RETH =
        0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    address internal constant _DAI_ADDRESS =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;

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

    CVE public cve;
    VeCVE public veCVE;
    CentralRegistry public centralRegistry;
    ChainlinkAdaptor public chainlinkAdaptor;
    ChainlinkAdaptor public dualChainlinkAdaptor;
    InterestRateModel public jumpRateModel;
    Lendtroller public lendtroller;
    PriceRouter public priceRouter;
    DToken public dUSDC;
    DToken public dDAI;
    CToken public cBALRETH;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public balRETH;

    MockToken public rewardToken;
    GaugePool public gaugePool;

    address public protocolMessagingHub = address(999999);
    address public randomUser = address(1000000);
    address public user1 = address(1000001);
    address public user2 = address(1000002);
    address public liquidator = address(1000003);
    uint256 public clPointMultiplier = 11000; // 110%

    function setUp() public virtual {
        _fork();

        usdc = IERC20(_USDC_ADDRESS);
        dai = IERC20(_DAI_ADDRESS);
        balRETH = IERC20(_BALANCER_WETH_RETH);

        _deployCentralRegistry();
        _deployCVE();
        _deployVeCVE();
        _deployPriceRouter();
        _deployChainlinkAdaptors();
        _deployGaugePool();

        _deployLendtroller();
        _deployInterestRateModel();
        _deployDUSDC();
        _deployDDAI();
        _deployCBALRETH(address(0));

        priceRouter.addMTokenSupport(address(dUSDC));
        priceRouter.addMTokenSupport(address(cBALRETH));
    }

    function _deployCentralRegistry() internal {
        centralRegistry = new CentralRegistry(
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            0
        );
        centralRegistry.transferEmergencyCouncil(address(this));
    }

    function _deployCVE() internal {
        cve = new CVE(
            "Curvance",
            "CVE",
            18,
            address(0),
            ICentralRegistry(address(centralRegistry)),
            address(0),
            10000 ether,
            10000 ether,
            10000 ether,
            10000 ether
        );
        centralRegistry.setCVE(address(cve));
    }

    function _deployVeCVE() internal {
        veCVE = new VeCVE(
            ICentralRegistry(address(centralRegistry)),
            clPointMultiplier
        );
        centralRegistry.setVeCVE(address(veCVE));
    }

    function _deployPriceRouter() internal {
        priceRouter = new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            _CHAINLINK_ETH_USD
        );

        centralRegistry.setPriceRouter(address(priceRouter));
        centralRegistry.setProtocolMessagingHub(protocolMessagingHub);
    }

    function _deployChainlinkAdaptors() internal {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(_WETH_ADDRESS, _CHAINLINK_ETH_USD, true);
        chainlinkAdaptor.addAsset(_USDC_ADDRESS, _CHAINLINK_USDC_USD, true);
        chainlinkAdaptor.addAsset(_USDC_ADDRESS, _CHAINLINK_USDC_ETH, false);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, _CHAINLINK_DAI_USD, true);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, _CHAINLINK_DAI_ETH, false);
        chainlinkAdaptor.addAsset(_RETH_ADDRESS, _CHAINLINK_RETH_ETH, false);

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
        dualChainlinkAdaptor.addAsset(_WETH_ADDRESS, _CHAINLINK_ETH_USD, true);
        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            _CHAINLINK_USDC_USD,
            true
        );
        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            _CHAINLINK_USDC_ETH,
            false
        );
        dualChainlinkAdaptor.addAsset(_DAI_ADDRESS, _CHAINLINK_DAI_USD, true);
        dualChainlinkAdaptor.addAsset(_DAI_ADDRESS, _CHAINLINK_DAI_ETH, false);
        dualChainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            _CHAINLINK_RETH_ETH,
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
        centralRegistry.addLendingMarket(address(lendtroller));
    }

    function _deployInterestRateModel() internal {
        jumpRateModel = new InterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            0.1e18,
            0.1e18,
            0.5e18
        );
    }

    function _deployDUSDC() internal returns (DToken) {
        dUSDC = new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(lendtroller),
            InterestRateModel(address(jumpRateModel))
        );
        return dUSDC;
    }

    function _deployDDAI() internal returns (DToken) {
        dDAI = new DToken(
            ICentralRegistry(address(centralRegistry)),
            _DAI_ADDRESS,
            address(lendtroller),
            InterestRateModel(address(jumpRateModel))
        );
        return dDAI;
    }

    function _deployCBALRETH(address vault) internal returns (CToken) {
        cBALRETH = new CToken(
            ICentralRegistry(address(centralRegistry)),
            _BALANCER_WETH_RETH,
            address(lendtroller),
            vault,
            "cBAL-WETH-RETH",
            "cBAL-ETHPAIR"
        );
        return cBALRETH;
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
        vm.startPrank(0xDa9CE944a37d218c3302F6B82a094844C6ECEb17);
        usdc.transfer(user, amount);
        vm.stopPrank();
    }

    function _prepareDAI(address user, uint256 amount) internal {
        vm.store(
            _DAI_ADDRESS,
            keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))),
            bytes32(amount)
        );
    }

    function _prepareBALRETH(address user, uint256 amount) internal {
        vm.startPrank(randomUser);
        vm.deal(randomUser, amount * 2);

        // balRETH.transfer(user, amount);
        vm.stopPrank();
    }
}
