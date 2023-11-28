// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";
import { CentralRegistryDeployer } from "./deployers/CentralRegistryDeployer.sol";
import { CveDeployer } from "./deployers/CveDeployer.sol";
import { CveLockerDeployer } from "./deployers/CveLockerDeployer.sol";
import { ProtocolMessagingHubDeployer } from "./deployers/ProtocolMessagingHubDeployer.sol";
import { FeeAccumulatorDeployer } from "./deployers/FeeAccumulatorDeployer.sol";
import { VeCveDeployer } from "./deployers/VeCveDeployer.sol";
import { GuagePoolDeployer } from "./deployers/GuagePoolDeployer.sol";
import { LendtrollerDeployer } from "./deployers/LendtrollerDeployer.sol";
import { ZapperDeployer } from "./deployers/ZapperDeployer.sol";
import { PositionFoldingDeployer } from "./deployers/PositionFoldingDeployer.sol";

contract DeployK2Lending is
    Script,
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
    PositionFoldingDeployer
{
    using stdJson for string;

    function setConfigurationPath() internal {
        string memory root = vm.projectRoot();
        configurationPath = string.concat(root, "/config/ethereum.json");
    }

    function setDeploymentPath() internal {
        string memory root = vm.projectRoot();
        deploymentPath = string.concat(root, "/deployments/ethereum.json");
    }

    function run() external {
        setConfigurationPath();
        setDeploymentPath();

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
        saveDeployedContracts("centralRegistry", centralRegistry);

        deployCve(
            readConfigAddress(".cve.lzEndpoint"),
            centralRegistry,
            readConfigAddress(".cve.teamAddress"),
            readConfigUint256(".cve.daoTreasuryAllocation"),
            readConfigUint256(".cve.callOptionAllocation"),
            readConfigUint256(".cve.teamAllocation"),
            readConfigUint256(".cve.initialTokenMint")
        );
        CentralRegistryDeployer.setCVE(cve);
        saveDeployedContracts("cve", cve);
        // TODO: set some params for cross-chain

        deployCveLocker(
            centralRegistry,
            readConfigAddress(".cveLocker.rewardToken")
        );
        CentralRegistryDeployer.setCVELocker(cveLocker);
        saveDeployedContracts("cveLocker", cveLocker);

        deployProtocolMessagingHub(
            centralRegistry,
            readConfigAddress(".protocolMessagingHub.feeToken"),
            readConfigAddress(".protocolMessagingHub.stargateRouter")
        );
        CentralRegistryDeployer.setProtocolMessagingHub(protocolMessagingHub);
        saveDeployedContracts("protocolMessagingHub", protocolMessagingHub);

        deployFeeAccumulator(
            centralRegistry,
            readConfigAddress(".feeAccumulator.feeToken"),
            readConfigUint256(".feeAccumulator.gasForCalldata"),
            readConfigUint256(".feeAccumulator.gasForCrosschain")
        );
        CentralRegistryDeployer.setFeeAccumulator(feeAccumulator);
        saveDeployedContracts("feeAccumulator", feeAccumulator);

        deployVeCve(
            centralRegistry,
            readConfigUint256(".veCve.clPointMultiplier")
        );
        CentralRegistryDeployer.setVeCVE(veCve);
        saveDeployedContracts("veCve", veCve);

        deployGaugePool(centralRegistry);
        CentralRegistryDeployer.addGaugeController(gaugePool);
        saveDeployedContracts("gaugePool", gaugePool);

        deployLendtroller(centralRegistry, gaugePool);
        CentralRegistryDeployer.addLendingMarket(
            lendtroller,
            readConfigUint256(".lendtroller.marketInterestFactor")
        );
        saveDeployedContracts("gaugePool", gaugePool);

        deployZapper(
            centralRegistry,
            lendtroller,
            readConfigAddress(".zapper.weth")
        );
        CentralRegistryDeployer.addZapper(zapper);
        saveDeployedContracts("zapper", zapper);

        deployPositionFolding(centralRegistry, lendtroller);
        saveDeployedContracts("positionFolding", positionFolding);

        vm.stopBroadcast();

        // TODO: transfer dao, timelock, emergency council
    }
}
