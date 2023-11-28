// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

contract DeployConfiguration is Script {
    using stdJson for string;

    string configurationPath;

    function readConfigUint256(
        string memory jsonPath
    ) internal view returns (uint256) {
        require(
            bytes(configurationPath).length != 0,
            "Set the configurationPath!"
        );

        string memory json = vm.readFile(configurationPath);
        return abi.decode(json.parseRaw(jsonPath), (uint256));
    }

    function readConfigAddress(
        string memory jsonPath
    ) internal view returns (address) {
        require(
            bytes(configurationPath).length != 0,
            "Set the configurationPath!"
        );

        string memory json = vm.readFile(configurationPath);
        return abi.decode(json.parseRaw(jsonPath), (address));
    }

    function getDeployedContracts(
        string memory name
    ) internal view returns (address) {
        require(
            bytes(configurationPath).length != 0,
            "Set the configurationPath!"
        );

        string memory json = vm.readFile(configurationPath);
        string memory jsonPath = string.concat(".contracts.", name);
        return abi.decode(json.parseRaw(jsonPath), (address));
    }

    function saveDeployedContracts(
        string memory name,
        address contractAddress
    ) internal {
        require(
            bytes(configurationPath).length != 0,
            "Set the configurationPath!"
        );
        string memory jsonPath = string.concat(".contracts.", name);

        console.log(string(abi.encodePacked(contractAddress)));
        vm.writeJson(
            vm.toString(contractAddress),
            configurationPath,
            jsonPath
        );
    }
}
