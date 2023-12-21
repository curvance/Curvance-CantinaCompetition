// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

contract DeployConfiguration is Script {
    using stdJson for string;

    string configurationPath;
    string deploymentPath;

    function _readConfigUint256(
        string memory jsonPath
    ) internal view returns (uint256) {
        require(
            bytes(configurationPath).length != 0,
            "Set the configurationPath!"
        );

        string memory json = vm.readFile(configurationPath);
        return abi.decode(json.parseRaw(jsonPath), (uint256));
    }

    function _readConfigAddress(
        string memory jsonPath
    ) internal view returns (address) {
        require(
            bytes(configurationPath).length != 0,
            "Set the configurationPath!"
        );

        string memory json = vm.readFile(configurationPath);
        return abi.decode(json.parseRaw(jsonPath), (address));
    }

    function _getDeployedContract(
        string memory name
    ) internal view returns (address) {
        require(bytes(deploymentPath).length != 0, "Set the deploymentPath!");

        string memory json = vm.readFile(deploymentPath);
        bytes memory data = json.parseRaw(string.concat(".", name));
        if (data.length > 0) {
            return abi.decode(data, (address));
        }
        return address(0);
    }

    function _saveDeployedContracts(
        string memory name,
        address deployed
    ) internal {
        require(bytes(deploymentPath).length != 0, "Set the deploymentPath!");

        try vm.readFile(deploymentPath) returns (string memory json) {
            string[] memory names = vm.parseJsonKeys(json, "$");
            for (uint256 i = 0; i < names.length; i++) {
                try
                    vm.parseJsonAddress(json, string.concat(".", names[i]))
                returns (address addr) {
                    vm.serializeAddress("Deployments", names[i], addr);
                } catch {}
            }
        } catch {}

        vm.writeJson(
            vm.serializeAddress("Deployments", name, deployed),
            deploymentPath
        );
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
