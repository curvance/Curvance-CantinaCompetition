// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { IERC20Metadata } from "contracts/interfaces/IERC20Metadata.sol";
import { ICircleRelayer } from "contracts/interfaces/wormhole/ICircleRelayer.sol";
import { IWormhole } from "contracts/interfaces/wormhole/IWormhole.sol";

contract MockCircleRelayer is ICircleRelayer {
    uint256 fee;
    MockWormhole wormhole_instance;

    constructor(uint256 _fee) {
        wormhole_instance = new MockWormhole(_fee);
        fee = _fee;
    }

    function transferTokensWithRelay(
        IERC20Metadata token,
        uint256 amount,
        uint256 toNativeTokenAmount,
        uint16 targetChain,
        bytes32 targetRecipient
    ) external payable returns (uint64 messageSequence) {}

    function relayerFee(
        uint16 dstChainId,
        address token
    ) external view returns (uint256) {}

    function wormhole() external view returns (IWormhole) {
        return IWormhole(wormhole_instance);
    }
}

contract MockWormhole is IWormhole {
    uint256 fee;

    constructor(uint256 _fee) {
        fee = _fee;
    }

    function messageFee() external view returns (uint256) {
        return fee;
    }
}
