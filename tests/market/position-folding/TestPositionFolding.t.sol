// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { PositionFolding } from "contracts/market/leverage/PositionFolding.sol";
import "tests/market/TestBaseMarket.sol";

contract TestPositionFolding is TestBaseMarket {
    address public UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    PositionFolding public positionFolding;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        priceOracle.setDirectPrice(E_ADDRESS, 2000 ether);

        // prepare 200K DAI
        vm.store(
            DAI_ADDRESS,
            keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))),
            bytes32(uint256(200000 ether))
        );
        // prepare 200K ETH
        vm.deal(user, 200000 ether);

        _deployCDAI();

        // support market
        vm.prank(admin);
        Lendtroller(lendtroller)._supportMarket(CToken(address(cDAI)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cDAI)),
            75e16
        );

        _deployCEther();

        // support market
        vm.prank(admin);
        Lendtroller(lendtroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cETH)),
            75e16
        );

        positionFolding = new PositionFolding(
            lendtroller,
            address(priceOracle),
            address(cETH),
            WETH_ADDRESS
        );
        // set position folding
        vm.prank(admin);
        Lendtroller(lendtroller)._setPositionFolding(address(positionFolding));

        // provide enough liquidity for leverage
        provideEnoughLiquidityForLeverage();
    }

    function provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = address(new User());
        vm.startPrank(liquidityProvider);
        // prepare 200K DAI
        vm.store(
            DAI_ADDRESS,
            keccak256(
                abi.encodePacked(
                    uint256(uint160(liquidityProvider)),
                    uint256(2)
                )
            ),
            bytes32(uint256(200000 ether))
        );
        // prepare 200K ETH
        vm.deal(liquidityProvider, 200000 ether);

        _enterMarkets(liquidityProvider);

        // mint cDAI
        dai.approve(address(cDAI), 200000 ether);
        cDAI.mint(200000 ether);

        // mint cETH
        cETH.mint{ value: 200000 ether }();

        vm.stopPrank();
    }

    function testLeverageMaxWithOnlyCToken() public {
        vm.startPrank(user);

        // enter markets
        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100 ether);

        // mint
        assertTrue(cDAI.mint(100 ether));
        assertEq(cDAI.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = dai.balanceOf(user);
        // borrow
        cDAI.borrow(25 ether);
        assertEq(cDAI.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, dai.balanceOf(user));

        assertEq(
            positionFolding.queryAmountToBorrowForLeverageMax(
                user,
                CToken(address(cDAI))
            ),
            172 ether
        );
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cDAI)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cDAI
            .getAccountSnapshot(user);
        assertEq(cTokenBalance, 272 ether);
        assertEq(borrowBalance, 197 ether);

        vm.stopPrank();
    }

    function testDeLeverageWithOnlyCToken() public {
        vm.startPrank(user);

        // enter markets
        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100 ether);

        // mint
        assertTrue(cDAI.mint(100 ether));
        assertEq(cDAI.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = dai.balanceOf(user);
        // borrow
        cDAI.borrow(25 ether);
        assertEq(cDAI.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, dai.balanceOf(user));

        assertEq(
            positionFolding.queryAmountToBorrowForLeverageMax(
                user,
                CToken(address(cDAI))
            ),
            172 ether
        );
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cDAI)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cDAI
            .getAccountSnapshot(user);
        assertEq(cTokenBalance, 272 ether);
        assertEq(borrowBalance, 197 ether);

        positionFolding.deleverage(
            CToken(address(cDAI)),
            197 ether,
            CToken(address(cDAI)),
            197 ether,
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (cTokenBalance, borrowBalance, ) = cDAI.getAccountSnapshot(user);
        assertEq(cTokenBalance, 75 ether);
        assertEq(borrowBalance, 0 ether);

        vm.stopPrank();
    }

    function testLeverageMaxWithOnlyCEther() public {
        vm.startPrank(user);

        // enter markets
        _enterCEtherMarket(user);

        // mint
        cETH.mint{ value: 100 ether }();
        assertEq(cETH.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(25 ether);
        assertEq(cETH.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, user.balance);

        assertEq(
            positionFolding.queryAmountToBorrowForLeverageMax(
                user,
                CToken(address(cETH))
            ),
            172 ether
        );
        positionFolding.leverageMax(
            CToken(address(cETH)),
            CToken(address(cETH)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cETH
            .getAccountSnapshot(user);
        assertEq(cTokenBalance, 272 ether);
        assertEq(borrowBalance, 197 ether);

        vm.stopPrank();
    }

    function testDeLeverageWithOnlyCEther() public {
        vm.startPrank(user);

        // enter markets
        _enterCEtherMarket(user);

        // mint
        cETH.mint{ value: 100 ether }();
        assertEq(cETH.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(25 ether);
        assertEq(cETH.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, user.balance);

        assertEq(
            positionFolding.queryAmountToBorrowForLeverageMax(
                user,
                CToken(address(cETH))
            ),
            172 ether
        );
        positionFolding.leverageMax(
            CToken(address(cETH)),
            CToken(address(cETH)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cETH
            .getAccountSnapshot(user);
        assertEq(cTokenBalance, 272 ether);
        assertEq(borrowBalance, 197 ether);

        positionFolding.deleverage(
            CToken(address(cETH)),
            197 ether,
            CToken(address(cETH)),
            197 ether,
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (cTokenBalance, borrowBalance, ) = cETH.getAccountSnapshot(user);
        assertEq(cTokenBalance, 75 ether);
        assertEq(borrowBalance, 0 ether);

        vm.stopPrank();
    }

    function testLeverageMaxIntegration1() public {
        vm.startPrank(user);

        // enter markets
        _enterMarkets(user);

        // mint 2000 DAI_ADDRESS
        dai.approve(address(cDAI), 2000 ether);
        cDAI.mint(2000 ether);

        // mint 1 ether
        cETH.mint{ value: _ONE }();

        // borrow 500 DAI_ADDRESS
        cDAI.borrow(500 ether);

        // borrow 0.25 ether
        cETH.borrow(0.25 ether);

        uint256 amountForLeverage = positionFolding
            .queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI)));
        assertEq(amountForLeverage, 6880 ether);

        address[] memory path = new address[](2);
        path[0] = DAI_ADDRESS;
        path[1] = WETH_ADDRESS;
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cETH)),
            PositionFolding.Swap({
                target: UNISWAP_V2_ROUTER,
                call: abi.encodeWithSignature(
                    "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                    amountForLeverage,
                    0,
                    path,
                    address(positionFolding),
                    block.timestamp
                )
            }),
            3000
        );

        (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI
            .getAccountSnapshot(user);
        (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH
            .getAccountSnapshot(user);
        assertEq(cDAIBalance, 2000 ether); // $2000
        assertGt(cETHBalance, 3.7 ether); // $7400
        assertEq(daiBorrowBalance, 7380 ether); // $7380
        assertEq(ethBorrowBalance, 0.25 ether); // $500

        (
            uint256 sumCollateral,
            uint256 maxBorrow,
            uint256 sumBorrow
        ) = Lendtroller(lendtroller).getAccountPosition(user);
        assertGt(sumCollateral, 9400 ether);
        assertGt(maxBorrow, (9400 ether * 75) / 100);
        assertEq(sumBorrow, 7880 ether);

        vm.stopPrank();
    }

    function testDeLeverageIntegration1() public {
        vm.startPrank(user);

        _enterMarkets(user);

        // mint 2000 DAI_ADDRESS
        dai.approve(address(cDAI), 2000 ether);
        cDAI.mint(2000 ether);

        // mint 1 ether
        cETH.mint{ value: _ONE }();

        // borrow 500 DAI_ADDRESS
        cDAI.borrow(500 ether);

        // borrow 0.25 ether
        cETH.borrow(0.25 ether);

        {
            uint256 amountForLeverage = positionFolding
                .queryAmountToBorrowForLeverageMax(
                    user,
                    CToken(address(cDAI))
                );
            assertEq(amountForLeverage, 6880 ether);

            address[] memory path = new address[](2);
            path[0] = DAI_ADDRESS;
            path[1] = WETH_ADDRESS;

            positionFolding.leverageMax(
                CToken(address(cDAI)),
                CToken(address(cETH)),
                PositionFolding.Swap({
                    target: UNISWAP_V2_ROUTER,
                    call: abi.encodeWithSignature(
                        "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                        amountForLeverage,
                        0,
                        path,
                        address(positionFolding),
                        block.timestamp
                    )
                }),
                3000
            );
        }

        {
            (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI
                .getAccountSnapshot(user);
            (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH
                .getAccountSnapshot(user);
            assertEq(cDAIBalance, 2000 ether); // $2000
            assertGt(cETHBalance, 3.7 ether); // $7400
            assertEq(daiBorrowBalance, 7380 ether); // $7380
            assertEq(ethBorrowBalance, 0.25 ether); // $500

            (
                uint256 sumCollateral,
                uint256 maxBorrow,
                uint256 sumBorrow
            ) = Lendtroller(lendtroller).getAccountPosition(user);
            assertGt(sumCollateral, 9400 ether);
            assertGt(maxBorrow, (9400 ether * 75) / 100);
            assertEq(sumBorrow, 7880 ether);
        }

        {
            address[] memory path = new address[](2);
            path[0] = WETH_ADDRESS;
            path[1] = DAI_ADDRESS;
            positionFolding.deleverage(
                CToken(address(cETH)),
                3.7 ether,
                CToken(address(cDAI)),
                6300 ether,
                PositionFolding.Swap({
                    target: UNISWAP_V2_ROUTER,
                    call: abi.encodeWithSignature(
                        "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                        3.7 ether,
                        0,
                        path,
                        address(positionFolding),
                        block.timestamp
                    )
                }),
                3000
            );
        }

        {
            (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI
                .getAccountSnapshot(user);
            (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH
                .getAccountSnapshot(user);
            assertGt(cDAIBalance, 2000 ether); // $2000
            assertGt(cETHBalance, 0 ether); // $7400
            assertEq(daiBorrowBalance, 1080 ether);
            assertEq(ethBorrowBalance, 0.25 ether); // $500

            (
                uint256 sumCollateral,
                uint256 maxBorrow,
                uint256 sumBorrow
            ) = Lendtroller(lendtroller).getAccountPosition(user);
            assertGt(sumCollateral, 2000 ether);
            assertGt(maxBorrow, (2000 ether * 75) / 100);
            assertEq(sumBorrow, 1580 ether);
        }

        vm.stopPrank();
    }

    function testLeverageMaxCheckAccountHealthy() public {
        vm.startPrank(user);

        // enter markets
        _enterMarkets(user);

        // mint 2000 DAI_ADDRESS
        dai.approve(address(cDAI), 2000 ether);
        cDAI.mint(2000 ether);

        // mint 1 ether
        cETH.mint{ value: _ONE }();

        // borrow 500 DAI_ADDRESS
        cDAI.borrow(500 ether);

        // borrow 0.25 ether
        cETH.borrow(0.25 ether);

        uint256 amountForLeverage = positionFolding
            .queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI)));
        assertEq(amountForLeverage, 6880 ether);

        address[] memory path = new address[](2);
        path[0] = DAI_ADDRESS;
        path[1] = WETH_ADDRESS;

        vm.deal(address(positionFolding), 0.01 ether);
        vm.expectRevert(LendtrollerInterface.InsufficientLiquidity.selector);
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cETH)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        vm.stopPrank();
    }
}
