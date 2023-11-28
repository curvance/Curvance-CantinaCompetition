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
    LendtrollerDeployer
{
    using stdJson for string;

    function setConfigurationPath() internal {
        string memory root = vm.projectRoot();
        configurationPath = string.concat(root, "/config/ethereum.json");
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        setConfigurationPath();

        vm.startBroadcast(deployerPrivateKey);

        deployCentralRegistry(
            readConfigAddress(".centralRegistry.daoAddress"),
            readConfigAddress(".centralRegistry.timelock"),
            readConfigAddress(".centralRegistry.emergencyCouncil"),
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
            readConfigAddress(".cve.lzEndpoint"),
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
            readConfigAddress(".protocolMessagingHub.stargateRouter")
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
        CentralRegistryDeployer.setVoteBoostMultiplier(
            readConfigUint256(".veCve.voteBoostMultiplier")
        );

        deployGaugePool(centralRegistry);
        CentralRegistryDeployer.addGaugeController(gaugePool);

        deployLendtroller(centralRegistry, gaugePool);
        CentralRegistryDeployer.addLendingMarket(
            lendtroller,
            readConfigUint256(".lendtroller.marketInterestFactor")
        );

        vm.stopBroadcast();
    }
}
