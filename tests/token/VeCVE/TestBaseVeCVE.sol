// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBase } from "tests/utils/TestBase.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { CVE } from "contracts/token/CVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract TestBaseVeCVE is TestBase {
    address internal constant _USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant _TOKEN_BRIDGE_RELAYER =
        0xCafd2f0A35A4459fA40C0517e17e6fA2939441CA;

    CentralRegistry public centralRegistry;
    CVE public cve;
    CVELocker public cveLocker;
    VeCVE public veCVE;
    IERC20 public usdc;

    RewardsData public rewardsData;

    modifier setRewardsData(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) {
        rewardsData = RewardsData(
            _USDC_ADDRESS,
            shouldLock,
            isFreshLock,
            isFreshLockContinuous
        );
        _;
    }

    function setUp() public virtual {
        _fork(18031848);

        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();

        _deployVeCVE();

        usdc = IERC20(_USDC_ADDRESS);
        rewardsData = RewardsData(_USDC_ADDRESS, true, true, true);
    }

    function _deployCentralRegistry() internal {
        centralRegistry = new CentralRegistry(
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            _ZERO_ADDRESS,
            0,
            address(0)
        );
    }

    function _deployCVE() internal {
        cve = new CVE(
            ICentralRegistry(address(centralRegistry)),
            _TOKEN_BRIDGE_RELAYER,
            _ZERO_ADDRESS,
            0,
            0,
            0,
            0
        );
        centralRegistry.setCVE(address(cve));
    }

    function _deployCVELocker() internal {
        cveLocker = new CVELocker(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );
        centralRegistry.setCVELocker(address(cveLocker));
    }

    function _deployVeCVE() internal {
        veCVE = new VeCVE(ICentralRegistry(address(centralRegistry)));

        centralRegistry.setVeCVE(address(veCVE));
        cveLocker.startLocker();
    }
}
