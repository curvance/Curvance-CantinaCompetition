// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";
import { CentralRegistryDeployer } from "./deployers/CentralRegistryDeployer.s.sol";
import { CveDeployer } from "./deployers/CveDeployer.s.sol";
import { CveLockerDeployer } from "./deployers/CveLockerDeployer.s.sol";
import { ProtocolMessagingHubDeployer } from "./deployers/ProtocolMessagingHubDeployer.s.sol";
import { OneBalanceFeeManagerDeployer } from "./deployers/OneBalanceFeeManagerDeployer.s.sol";
import { FeeAccumulatorDeployer } from "./deployers/FeeAccumulatorDeployer.s.sol";
import { VeCveDeployer } from "./deployers/VeCveDeployer.s.sol";
import { GaugePoolDeployer } from "./deployers/GaugePoolDeployer.s.sol";
import { MarketManagerDeployer } from "./deployers/MarketManagerDeployer.s.sol";
import { ComplexZapperDeployer } from "./deployers/ComplexZapperDeployer.s.sol";
import { PositionFoldingDeployer } from "./deployers/PositionFoldingDeployer.s.sol";
import { OracleRouterDeployer } from "./deployers/OracleRouterDeployer.s.sol";
import { AuxiliaryDataDeployer } from "./deployers/AuxiliaryDataDeployer.s.sol";

contract DeployCurvance is
    DeployConfiguration,
    CentralRegistryDeployer,
    CveDeployer,
    CveLockerDeployer,
    ProtocolMessagingHubDeployer,
    OneBalanceFeeManagerDeployer,
    FeeAccumulatorDeployer,
    VeCveDeployer,
    GaugePoolDeployer,
    MarketManagerDeployer,
    ComplexZapperDeployer,
    PositionFoldingDeployer,
    OracleRouterDeployer,
    AuxiliaryDataDeployer
{
    function run() external {
        _deploy("ethereum");
    }

    function run(string memory network) external {
        _deploy(network);
    }

    function _deploy(string memory network) internal {
        _setConfigurationPath(network);
        _setDeploymentPath(network);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy CentralRegistry

        _deployCentralRegistry(
            deployer,
            deployer,
            deployer,
            _readConfigUint256(".centralRegistry.genesisEpoch"),
            _readConfigAddress(".centralRegistry.sequencer"),
            _readConfigAddress(".centralRegistry.feeToken")
        );
        _setLockBoostMultiplier(
            _readConfigUint256(".centralRegistry.lockBoostMultiplier")
        );
        _setWormholeCore(_readConfigAddress(".centralRegistry.wormholeCore"));
        _setWormholeRelayer(
            _readConfigAddress(".centralRegistry.wormholeRelayer")
        );
        _setCircleRelayer(
            _readConfigAddress(".centralRegistry.circleRelayer")
        );
        _setTokenBridgeRelayer(
            _readConfigAddress(".centralRegistry.tokenBridgeRelayer")
        );
        _addHarvester(_readConfigAddress(".centralRegistry.harvester"));

        // Deploy CVE

        _deployCVE(centralRegistry, _readConfigAddress(".cve.teamAddress"));
        _setCVE(cve);
        // TODO: set some params for cross-chain

        // Deploy CveLocker

        _deployCveLocker(
            centralRegistry,
            _readConfigAddress(".cveLocker.rewardToken")
        );
        _setCVELocker(cveLocker);

        // Deploy ProtocolMessagingHub

        _deployProtocolMessagingHub(centralRegistry);
        _setProtocolMessagingHub(protocolMessagingHub);

        // Deploy OneBalanceFeeManager

        _deployOneBalanceFeeManager(
            centralRegistry,
            _readConfigAddress(".oneBalanceFeeManager.gelatoOneBalance"),
            _readConfigAddress(
                ".oneBalanceFeeManager.polygonOneBalanceFeeManager"
            )
        );

        // Deploy FeeAccumulator

        _deployFeeAccumulator(
            centralRegistry,
            oneBalanceFeeManager,
            _readConfigUint256(".feeAccumulator.gasForCalldata"),
            _readConfigUint256(".feeAccumulator.gasForCrosschain")
        );
        _setFeeAccumulator(feeAccumulator);

        // Deploy VeCVE

        _deployVeCve(centralRegistry);
        _setVeCVE(veCve);

        // Deploy GaugePool

        _deployGaugePool(centralRegistry);
        _addGaugeController(gaugePool);

        // Deploy MarketManager

        _deployMarketManager(centralRegistry, gaugePool);
        _addMarketManager(
            marketManager,
            _readConfigUint256(".marketManager.marketInterestFactor")
        );

        // Deploy ComplexZapper

        _deployComplexZapper(
            centralRegistry,
            marketManager,
            _readConfigAddress(".zapper.weth")
        );
        _addZapper(complexZapper);

        // Deploy PositionFolding

        _deployPositionFolding(centralRegistry, marketManager);


        _deployOracleRouter(
            centralRegistry,
            _readConfigAddress(".oracleRouter.chainlinkEthUsd")
        );

        _setOracleRouter(oracleRouter);

        //  Deploy Auxiliary Data

        _deployAuxiliaryData(centralRegistry);

        // transfer dao, timelock, emergency council
        // _transferDaoOwnership(
        //     _readConfigAddress(".centralRegistry.daoAddress")
        // );
        // _migrateTimelockConfiguration(
        //     _readConfigAddress(".centralRegistry.timelock")
        // );
        // _transferEmergencyCouncil(
        //     _readConfigAddress(".centralRegistry.emergencyCouncil")
        // );

        vm.stopBroadcast();
    }
}
