// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBase } from "tests/utils/TestBase.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { InterestRateModel } from "contracts/market/interestRates/InterestRateModel.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract TestBasePriceRouter is TestBase {
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
    InterestRateModel public jumpRateModel;
    Lendtroller public lendtroller;
    PriceRouter public priceRouter;
    DToken public mUSDC;

    function setUp() public virtual {
        _fork();

        _deployCentralRegistry();
        _deployPriceRouter();
        _deployChainlinkAdaptors();

        _deployLendtroller();
        _deployInterestRateModel();
        _deployMUSDC();
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

    function _deployPriceRouter() internal {
        priceRouter = new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            _CHAINLINK_ETH_USD
        );

        centralRegistry.setPriceRouter(address(priceRouter));
    }

    function _deployChainlinkAdaptors() internal {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
        dualChainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );

        chainlinkAdaptor.addAsset(_USDC_ADDRESS, _CHAINLINK_USDC_USD, true);
        chainlinkAdaptor.addAsset(_USDC_ADDRESS, _CHAINLINK_USDC_ETH, false);

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
    }

    function _deployLendtroller() internal {
        GaugePool gaugePool = new GaugePool(
            ICentralRegistry(address(centralRegistry))
        );
        lendtroller = new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );
        centralRegistry.addLendingMarket(address(lendtroller), 0);
    }

    function _deployInterestRateModel() internal {
        jumpRateModel = new InterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            0.1e18,
            0.1e18,
            0.5e18
        );
    }

    function _deployMUSDC() internal {
        mUSDC = new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(lendtroller),
            address(jumpRateModel)
        );
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
}
