// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract TestBaseCToken is TestBaseMarket {
    function setUp() public virtual override {
        super.setUp();

        _deployCBALRETH();

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
}
