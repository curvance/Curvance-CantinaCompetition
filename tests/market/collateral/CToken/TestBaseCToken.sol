// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { AuraPositionVault } from "contracts/deposits/adaptors/AuraPositionVault.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract TestBaseCToken is TestBaseMarket {
    address internal constant _AURA_BOOSTER =
        0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address internal constant _REWARDER =
        0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;

    AuraPositionVault public vault;

    function setUp() public virtual override {
        super.setUp();

        _deployAuraPositionVault();
        _deployCBALRETH(address(vault));

        vault.initiateVault(address(cBALRETH));
        gaugePool.start(address(lendtroller));

        _prepareBALRETH(user1, _ONE);
        _prepareBALRETH(address(this), _ONE);

        SafeTransferLib.safeApprove(
            _BALANCER_WETH_RETH,
            address(cBALRETH),
            _ONE
        );
        lendtroller.listMarketToken(address(cBALRETH));
    }

    function _deployAuraPositionVault() internal {
        vault = new AuraPositionVault(
            ERC20(_BALANCER_WETH_RETH),
            ICentralRegistry(address(centralRegistry)),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );
    }
}
