// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/market/zapper/ZapperGeneric.sol";
import "contracts/mocks/MockCToken.sol";
import "contracts/mocks/MockLendtroller.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "tests/utils/TestBase.sol";

contract TestZapperGeneric is TestBase {
    address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address frax = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    function setUp() public {
        _fork(16840000);
    }

    function testTriCryptoWithETH() public {
        address user = address(0x0000000000000000000000000000000000000001);
        vm.startPrank(user);

        // setup environment
        IERC20 token = IERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
        address minter = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
        MockCToken cToken = new MockCToken(
            address(token),
            "CToken",
            "CToken",
            18
        );
        MockLendtroller lendtroller = new MockLendtroller();
        lendtroller.setMarket(address(cToken), true);
        ZapperGeneric zapper = new ZapperGeneric(address(lendtroller), weth);

        // try zap in
        address[] memory tokens = new address[](3);
        tokens[0] = usdt;
        tokens[1] = wbtc;
        tokens[2] = weth;
        ZapperGeneric.Swap[] memory tokenSwaps = new ZapperGeneric.Swap[](0);
        zapper.curvanceIn{ value: 3 ether }(
            address(cToken),
            address(0),
            3 ether,
            minter,
            address(token),
            0,
            tokens,
            tokenSwaps
        );

        assertGt(cToken.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testTriCryptoWithDAI() public {
        address user = address(0x0000000000000000000000000000000000000001);
        vm.startPrank(user);

        // setup environment
        IERC20 token = IERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
        address minter = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
        MockCToken cToken = new MockCToken(
            address(token),
            "CToken",
            "CToken",
            18
        );
        MockLendtroller lendtroller = new MockLendtroller();
        lendtroller.setMarket(address(cToken), true);
        ZapperGeneric zapper = new ZapperGeneric(address(lendtroller), weth);

        // approve dai
        IERC20(dai).approve(address(zapper), 3000 ether);

        // try zap in
        address[] memory tokens = new address[](3);
        tokens[0] = usdt;
        tokens[1] = wbtc;
        tokens[2] = weth;
        ZapperGeneric.Swap[] memory tokenSwaps = new ZapperGeneric.Swap[](2);
        // 1000 dai -> usdt
        tokenSwaps[0].target = oneInchRouter;
        tokenSwaps[0]
            .call = hex"12aa3caf0000000000000000000000007122db0ebe4eb9b434a9f2ffe6760bc03bfbd0e00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000007122db0ebe4eb9b434a9f2ffe6760bc03bfbd0e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000003635c9adc5dea00000000000000000000000000000000000000000000000000000000000001db0bfd80000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014e0000000000000000000000000000000000000000000000000000000001305126ea5b523263bea6a5574858528bd591a3c2bea0f66b175474e89094c44da98b954eedeac495271d0f000438ed17390000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001db0bfd800000000000000000000000000000000000000000000000000000000000000a00000000000000000000000001111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000064172ee400000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000cfee7c08";
        // 1000 dai -> wbtc
        tokenSwaps[1].target = oneInchRouter;
        tokenSwaps[1]
            .call = hex"e449022e00000000000000000000000000000000000000000000003635c9adc5dea0000000000000000000000000000000000000000000000000000000000000001d344a00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001800000000000000000000000391e8501b626c623d39474afca6f9e46c2686649cfee7c08";
        zapper.curvanceIn(
            address(cToken),
            dai,
            3000 ether,
            minter,
            address(token),
            0,
            tokens,
            tokenSwaps
        );

        assertGt(cToken.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testFraxUSDCWithETH() public {
        address user = address(0x0000000000000000000000000000000000000001);
        vm.startPrank(user);

        // setup environment
        IERC20 token = IERC20(0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC);
        address minter = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;
        MockCToken cToken = new MockCToken(
            address(token),
            "CToken",
            "CToken",
            18
        );
        MockLendtroller lendtroller = new MockLendtroller();
        lendtroller.setMarket(address(cToken), true);
        ZapperGeneric zapper = new ZapperGeneric(address(lendtroller), weth);

        // try zap in
        address[] memory tokens = new address[](2);
        tokens[0] = frax;
        tokens[1] = usdc;
        ZapperGeneric.Swap[] memory tokenSwaps = new ZapperGeneric.Swap[](2);
        // 1 weth -> frax
        tokenSwaps[0].target = oneInchRouter;
        tokenSwaps[0]
            .call = hex"0502b1c5000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000301f73dded37f156a60000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000280000000000000003b6d034061eb53ee427ab4e007d78a9134aacb3101a2dc2300000000000000003b6d0340e1573b9d29e2183b1af0e743dc2754979a40d237cfee7c08";
        // 1 weth -> usdc
        tokenSwaps[1].target = oneInchRouter;
        tokenSwaps[1]
            .call = hex"0502b1c5000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000005496ac680000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000180000000000000003b6d0340b4e16d0168e52d35cacd2c6185b44281ec28c9dccfee7c08";
        zapper.curvanceIn{ value: 2 ether }(
            address(cToken),
            address(0),
            2 ether,
            minter,
            address(token),
            0,
            tokens,
            tokenSwaps
        );

        assertGt(cToken.balanceOf(user), 0);

        vm.stopPrank();
    }
}
