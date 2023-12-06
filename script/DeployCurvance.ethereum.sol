// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";
import { CentralRegistryDeployer } from "./deployers/CentralRegistryDeployer.s.sol";
import { CveDeployer } from "./deployers/CveDeployer.s.sol";
import { CveLockerDeployer } from "./deployers/CveLockerDeployer.s.sol";
import { ProtocolMessagingHubDeployer } from "./deployers/ProtocolMessagingHubDeployer.s.sol";
import { FeeAccumulatorDeployer } from "./deployers/FeeAccumulatorDeployer.s.sol";
import { VeCveDeployer } from "./deployers/VeCveDeployer.s.sol";
import { GuagePoolDeployer } from "./deployers/GuagePoolDeployer.s.sol";
import { LendtrollerDeployer } from "./deployers/LendtrollerDeployer.s.sol";
import { ZapperDeployer } from "./deployers/ZapperDeployer.s.sol";
import { PositionFoldingDeployer } from "./deployers/PositionFoldingDeployer.s.sol";

contract DeployCurvanceEthereum is
    DeployConfiguration,
    CentralRegistryDeployer,
    CveDeployer,
    CveLockerDeployer,
    ProtocolMessagingHubDeployer,
    FeeAccumulatorDeployer,
    VeCveDeployer,
    GuagePoolDeployer,
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

        deployCentralRegistry(
            deployer,
            deployer,
            deployer,
            readConfigUint256(".centralRegistry.genesisEpoch"),
            readConfigAddress(".centralRegistry.sequencer")
        );
        CentralRegistryDeployer.setLockBoostMultiplier(
            readConfigUint256(".centralRegistry.lockBoostMultiplier")
        );
        CentralRegistryDeployer.addHarvester(
            readConfigAddress(".centralRegistry.harvester")
        );

        deployCve(
            centralRegistry,
            readConfigAddress(".cve.teamAddress"),
            readConfigUint256(".cve.daoTreasuryAllocation"),
            readConfigUint256(".cve.callOptionAllocation"),
            readConfigUint256(".cve.teamAllocation"),
            readConfigUint256(".cve.initialTokenMint")
        );
        CentralRegistryDeployer.setCVE(cve);
        // TODO: set some params for cross-chain

        deployCveLocker(
            centralRegistry,
            readConfigAddress(".cveLocker.rewardToken")
        );
        CentralRegistryDeployer.setCVELocker(cveLocker);

        deployProtocolMessagingHub(
            centralRegistry,
            readConfigAddress(".protocolMessagingHub.feeToken"),
            readConfigAddress(".protocolMessagingHub.wormholeRelayer"),
            readConfigAddress(".protocolMessagingHub.circleRelayer")
        );
        CentralRegistryDeployer.setProtocolMessagingHub(protocolMessagingHub);

        deployFeeAccumulator(
            centralRegistry,
            readConfigAddress(".feeAccumulator.feeToken"),
            readConfigUint256(".feeAccumulator.gasForCalldata"),
            readConfigUint256(".feeAccumulator.gasForCrosschain")
        );
        CentralRegistryDeployer.setFeeAccumulator(feeAccumulator);

        deployVeCve(
            centralRegistry,
            readConfigUint256(".veCve.clPointMultiplier")
        );
        CentralRegistryDeployer.setVeCVE(veCve);

        deployGaugePool(centralRegistry);
        CentralRegistryDeployer.addGaugeController(gaugePool);

        deployLendtroller(centralRegistry, gaugePool);
        CentralRegistryDeployer.addLendingMarket(
            lendtroller,
            readConfigUint256(".lendtroller.marketInterestFactor")
        );

        deployZapper(
            centralRegistry,
            lendtroller,
            readConfigAddress(".zapper.weth")
        );
        CentralRegistryDeployer.addZapper(zapper);

        deployPositionFolding(centralRegistry, lendtroller);

        deployPriceRouter(
            centralRegistry,
            readConfigAddress(".priceRouter.chainlinkEthUsd")
        );
        CentralRegistryDeployer.setPriceRouter(priceRouter);

        // transfer dao, timelock, emergency council
        // CentralRegistryDeployer.transferDaoOwnership(
        //     readConfigAddress(".centralRegistry.daoAddress")
        // );
        // CentralRegistryDeployer.migrateTimelockConfiguration(
        //     readConfigAddress(".centralRegistry.timelock")
        // );
        // CentralRegistryDeployer.transferEmergencyCouncil(
        //     readConfigAddress(".centralRegistry.emergencyCouncil")
        // );

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
