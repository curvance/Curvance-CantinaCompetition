// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract UpdateCTokenConfig is Script, DeployConfiguration {
    using stdJson for string;

    function run(string memory name) external {
        _update("ethereum", name);
    }

    function run(string memory network, string memory name) external {
        _update(network, name);
    }

    function _update(string memory network, string memory name) internal {
        _setConfigurationPath(network);
        _setDeploymentPath(network);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        _updateConfig(
            string.concat("C-", name),
            string.concat(".markets.cTokens.", name)
        );

        vm.stopBroadcast();
    }

    function _updateConfig(
        string memory deploymentName,
        string memory pathName
    ) internal {
        address lendtroller = _getDeployedContract("lendtroller");
        console.log("lendtroller =", lendtroller);
        require(lendtroller != address(0), "Set the lendtroller!");

        address cToken = _getDeployedContract(deploymentName);
        console.log("cToken =", cToken);
        require(cToken != address(0), "Set the cToken!");

        Lendtroller(lendtroller).updateCollateralToken(
            IMToken(cToken),
            _readConfigUint256(string.concat(pathName, ".collRatio")),
            _readConfigUint256(string.concat(pathName, ".collReqA")),
            _readConfigUint256(string.concat(pathName, ".collReqB")),
            _readConfigUint256(string.concat(pathName, ".liqIncA")),
            _readConfigUint256(string.concat(pathName, ".liqIncB")),
            _readConfigUint256(string.concat(pathName, ".liqFee")),
            _readConfigUint256(string.concat(pathName, ".baseCFactor"))
        );
        console.log("updateCollateralToken");

        address[] memory mTokens = new address[](1);
        mTokens[0] = cToken;
        uint256[] memory newCollateralCaps = new uint256[](1);
        newCollateralCaps[0] = _readConfigUint256(
            string.concat(pathName, ".collateralCaps")
        );
        Lendtroller(lendtroller).setCTokenCollateralCaps(
            mTokens,
            newCollateralCaps
        );
        console.log("setCTokenCollateralCaps");
    }
}
