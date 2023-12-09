// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";
import { CentralRegistryDeployer } from "./deployers/CentralRegistryDeployer.s.sol";
import { CveDeployer } from "./deployers/CveDeployer.s.sol";
import { CveLockerDeployer } from "./deployers/CveLockerDeployer.s.sol";
import { ProtocolMessagingHubDeployer } from "./deployers/ProtocolMessagingHubDeployer.s.sol";
import { FeeAccumulatorDeployer } from "./deployers/FeeAccumulatorDeployer.s.sol";
import { VeCveDeployer } from "./deployers/VeCveDeployer.s.sol";
import { GaugePoolDeployer } from "./deployers/GaugePoolDeployer.s.sol";
import { LendtrollerDeployer } from "./deployers/LendtrollerDeployer.s.sol";
import { ZapperDeployer } from "./deployers/ZapperDeployer.s.sol";
import { PositionFoldingDeployer } from "./deployers/PositionFoldingDeployer.s.sol";
import { PriceRouterDeployer } from "./deployers/PriceRouterDeployer.s.sol";

contract DeployCurvance is
    DeployConfiguration,
    CentralRegistryDeployer,
    CveDeployer,
    CveLockerDeployer,
    ProtocolMessagingHubDeployer,
    FeeAccumulatorDeployer,
    VeCveDeployer,
    GaugePoolDeployer,
    LendtrollerDeployer,
    ZapperDeployer,
    PositionFoldingDeployer,
    PriceRouterDeployer
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
            _readConfigAddress(".centralRegistry.sequencer")
        );
        _setLockBoostMultiplier(
            _readConfigUint256(".centralRegistry.lockBoostMultiplier")
        );
        _addHarvester(_readConfigAddress(".centralRegistry.harvester"));
        _saveDeployedContracts("centralRegistry", centralRegistry);

        // Deploy CVE

        _deployCve(
            centralRegistry,
            _readConfigAddress(".cve.teamAddress"),
            _readConfigUint256(".cve.daoTreasuryAllocation"),
            _readConfigUint256(".cve.callOptionAllocation"),
            _readConfigUint256(".cve.teamAllocation"),
            _readConfigUint256(".cve.initialTokenMint")
        );
        _setCVE(cve);
        _saveDeployedContracts("cve", cve);
        // TODO: set some params for cross-chain

        // Deploy CveLocker

        _deployCveLocker(
            centralRegistry,
            _readConfigAddress(".cveLocker.rewardToken")
        );
        _setCVELocker(cveLocker);
        _saveDeployedContracts("cveLocker", cveLocker);

        // Deploy ProtocolMessagingHub

        _deployProtocolMessagingHub(
            centralRegistry,
            _readConfigAddress(".protocolMessagingHub.feeToken"),
            _readConfigAddress(".protocolMessagingHub.wormholeRelayer"),
            _readConfigAddress(".protocolMessagingHub.circleRelayer")
        );
        _setProtocolMessagingHub(protocolMessagingHub);
        _saveDeployedContracts("protocolMessagingHub", protocolMessagingHub);

        // Deploy FeeAccumulator

        _deployFeeAccumulator(
            centralRegistry,
            _readConfigAddress(".feeAccumulator.feeToken"),
            _readConfigUint256(".feeAccumulator.gasForCalldata"),
            _readConfigUint256(".feeAccumulator.gasForCrosschain")
        );
        _setFeeAccumulator(feeAccumulator);
        _saveDeployedContracts("feeAccumulator", feeAccumulator);

        // Deploy VeCVE

        _deployVeCve(
            centralRegistry,
            _readConfigUint256(".veCve.clPointMultiplier")
        );
        _setVeCVE(veCve);
        _saveDeployedContracts("veCve", veCve);

        // Deploy GaugePool

        _deployGaugePool(centralRegistry);
        _addGaugeController(gaugePool);
        _saveDeployedContracts("gaugePool", gaugePool);

        // Deploy Lendtroller

        _deployLendtroller(centralRegistry, gaugePool);
        _addLendingMarket(
            lendtroller,
            _readConfigUint256(".lendtroller.marketInterestFactor")
        );
        _saveDeployedContracts("gaugePool", gaugePool);

        // Deploy Zapper

        _deployZapper(
            centralRegistry,
            lendtroller,
            _readConfigAddress(".zapper.weth")
        );
        _addZapper(zapper);
        _saveDeployedContracts("zapper", zapper);

        // Deploy PositionFolding

        _deployPositionFolding(centralRegistry, lendtroller);
        _saveDeployedContracts("positionFolding", positionFolding);

        // transfer dao, timelock, emergency council
        _transferDaoOwnership(
            _readConfigAddress(".centralRegistry.daoAddress")
        );
        _migrateTimelockConfiguration(
            _readConfigAddress(".centralRegistry.timelock")
        );
        _transferEmergencyCouncil(
            _readConfigAddress(".centralRegistry.emergencyCouncil")
        );

        vm.stopBroadcast();
    }

    function _setConfigurationPath(string memory network) internal {
        string memory root = vm.projectRoot();
        configurationPath = string.concat(root, "/config/", network, ".json");
    }

    function _setDeploymentPath(string memory network) internal {
        string memory root = vm.projectRoot();
        deploymentPath = string.concat(
            root,
            "/deployments/",
            network,
            ".json"
        );
    }
}
