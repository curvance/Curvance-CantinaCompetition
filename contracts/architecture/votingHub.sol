// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICveLocker.sol";
import "contracts/interfaces/ICentralRegistry.sol";
import "../interfaces/IGaugePool.sol";
import "../interfaces/ICVE.sol";

contract CurvanceVotingHub {
    using SafeERC20 for IERC20;

    event GaugeRewardsSet(
        ChainData[] chainData,
        address[][] pools,
        uint256[][] rewards
    );

    struct ChainData {
        uint256 chainid;
        address destinationHub;
        uint256 emissionAmount;
    }

    uint256 public lastEpochPaid;
    uint256 public targetEmissionsPerEpoch;
    ICentralRegistry public immutable centralRegistry;

    uint256 public constant EPOCH_DURATION = 2 weeks;
    uint256 public constant upperBound = 10010;
    uint256 public constant lowerBound = 9990;
    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant cveDecimalOffset = 1000000000000000000;

    constructor(
        ICentralRegistry _centralRegistry,
        uint256 _targetEmissionsPerEpoch
    ) {
        centralRegistry = _centralRegistry;
        setEpochEmissions(_targetEmissionsPerEpoch);
    }

    modifier onlyDaoManager() {
        require(msg.sender == centralRegistry.daoAddress(), "UNAUTHORIZED");
        _;
    }

    function genesisEpoch() private view returns (uint256) {
        return centralRegistry.genesisEpoch();
    }

    /// @notice Returns the current epoch for the given time
    /// @param _time The timestamp for which to calculate the epoch
    /// @return The current epoch
    function currentEpoch(uint256 _time) public view returns (uint256) {
        if (_time < genesisEpoch()) return 0;
        return ((_time - genesisEpoch()) / EPOCH_DURATION);
    }

    function validateEmissions(uint256 _emissions) public view returns (bool) {
        return
            (targetEmissionsPerEpoch <
                (_emissions * upperBound) / DENOMINATOR) &&
            (targetEmissionsPerEpoch >
                (_emissions * lowerBound) / DENOMINATOR);
    }

    function executeMatchingEngine(
        address[][] calldata pools,
        uint256[][] calldata poolEmissions,
        ChainData[] calldata chainData
    ) public onlyDaoManager {
        uint256 currentEpochDistribution = currentEpoch(block.timestamp);

        uint256 numPools = pools.length;

        require(
            poolEmissions.length == numPools && numPools == chainData.length,
            "Invalid Parameters"
        );
        require(
            currentEpochDistribution > lastEpochPaid ||
                currentEpochDistribution == 0,
            "Epoch Rewards already configured"
        );
        IGaugePool gp = IGaugePool(centralRegistry.gaugeController());
        ICVE cve = ICVE(centralRegistry.CVE());

        uint256 tokensPreEmission = IERC20(address(cve)).balanceOf(
            address(this)
        );

        // check that double array length is not greater than
        // child chains.length in veCVE/centralRegistry/cveLocker
        // calculate msg.value via estimate fees
        // approve gauge pool so that tokens can be taken

        for (uint256 i; i < numPools; ) {
            if (chainData[i].chainid == block.chainid) {
                gp.setEmissionRates(
                    currentEpochDistribution,
                    pools[i],
                    poolEmissions[i]
                );
            } else {
                _sendEmissions(cve, chainData[i], pools[i], poolEmissions[i]);
            }

            unchecked {
                ++i;
            }
        }

        uint256 tokensPostEmission = IERC20(address(cve)).balanceOf(
            address(this)
        );

        require(
            tokensPostEmission < tokensPreEmission,
            "Tokens not distributed successfully"
        );
        require(
            validateEmissions(tokensPreEmission - tokensPostEmission),
            "Invalid Gauge Emission Inputs"
        );

        ++lastEpochPaid;
        emit GaugeRewardsSet(chainData, pools, poolEmissions);
    }

    function setEpochEmissions(
        uint256 _targetEmissionsPerEpoch
    ) public onlyDaoManager {
        targetEmissionsPerEpoch = _targetEmissionsPerEpoch * cveDecimalOffset;
    }

    function _sendEmissions(
        ICVE cve,
        ChainData calldata chainData,
        address[] calldata pools,
        uint256[] calldata poolEmissions
    ) internal {
        cve.sendEmissions(
            address(this),
            uint16(chainData.chainid),
            chainData.destinationHub,
            pools,
            poolEmissions,
            chainData.emissionAmount,
            payable(msg.sender),
            centralRegistry.zroAddress(),
            ""
        );
    }
}
