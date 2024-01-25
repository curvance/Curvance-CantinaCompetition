// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IAggregationRouterV5 } from "contracts/interfaces/external/1inch/IAggregationRouterV5.sol";
import { CallDataCheckerBase } from "./CallDataCheckerBase.sol";

contract CallDataCheckerFor1InchAggregationRouterV5 is CallDataCheckerBase {
    constructor(address _target) CallDataCheckerBase(_target) {}

    function checkRecipient(
        address _target,
        bytes memory _data,
        address _recipient
    ) external view override {
        require(target == _target, "Invalid target");

        bytes4 funcSigHash = getFuncSigHash(_data);
        if (funcSigHash == IAggregationRouterV5.swap.selector) {
            (, IAggregationRouterV5.SwapDescription memory desc, , ) = abi
                .decode(
                    getFuncParams(_data),
                    (
                        address,
                        IAggregationRouterV5.SwapDescription,
                        bytes,
                        bytes
                    )
                );
            require(desc.dstReceiver == _recipient, "Invalid recipient");
        } else if (
            funcSigHash ==
            IAggregationRouterV5.uniswapV3SwapToWithPermit.selector
        ) {
            (address payable recipient, , , , , ) = abi.decode(
                getFuncParams(_data),
                (address, address, uint256, uint256, uint256[], bytes)
            );
            require(recipient == _recipient, "Invalid recipient");
        } else if (
            funcSigHash == IAggregationRouterV5.uniswapV3SwapTo.selector
        ) {
            (address payable recipient, , , ) = abi.decode(
                getFuncParams(_data),
                (address, uint256, uint256, uint256[])
            );
            require(recipient == _recipient, "Invalid recipient");
        } else if (
            funcSigHash == IAggregationRouterV5.unoswapToWithPermit.selector
        ) {
            (address payable recipient, , , , , ) = abi.decode(
                getFuncParams(_data),
                (address, address, uint256, uint256, uint256[], bytes)
            );
            require(recipient == _recipient, "Invalid recipient");
        } else if (funcSigHash == IAggregationRouterV5.unoswapTo.selector) {
            (address payable recipient, , , , ) = abi.decode(
                getFuncParams(_data),
                (address, address, uint256, uint256, uint256[])
            );
            require(recipient == _recipient, "Invalid recipient");
        }
    }
}
