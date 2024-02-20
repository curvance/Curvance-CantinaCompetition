// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract TestBaseFeeAccumulator is TestBaseMarket {
    function setUp() public virtual override {
        _fork(19140000);

        usdc = IERC20(_USDC_ADDRESS);
        dai = IERC20(_DAI_ADDRESS);
        balRETH = IERC20(_BALANCER_WETH_RETH);

        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();
        _deployVeCVE();
        _deployProtocolMessagingHub();
        _deployOneBalanceFeeManager();
        _deployFeeAccumulator();
    }
}
