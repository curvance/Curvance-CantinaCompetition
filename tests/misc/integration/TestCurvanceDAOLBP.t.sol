// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { CurvanceDAOLBP } from "contracts/misc/CurvanceDAOLBP.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import "tests/market/TestBaseMarket.sol";

contract TestCurvanceDAOLBP is TestBaseMarket {
    CurvanceDAOLBP public lbp;

    uint256 softPrice = 10e18; // $10
    uint256 cveAmountForSale = 10000e18;

    function setUp() public override {
        super.setUp();

        lbp = new CurvanceDAOLBP(
            ICentralRegistry(address(centralRegistry))
        );

        cve.transfer(address(lbp), cve.balanceOf(address(this)));
    }

    function testInitialize() public {
        assertEq(lbp.cve(), address(cve));
    }

    function testStartRevertWhenInvalidStartTime() public {
        vm.expectRevert(
            CurvanceDAOLBP.CurvanceDAOLBP__InvalidStartTime.selector
        );
        lbp.start(
            block.timestamp - 1,
            softPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );
    }

    function testStartRevertWhenAlreadyStarted() public {
        lbp.start(
            block.timestamp,
            softPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );

        vm.expectRevert(CurvanceDAOLBP.CurvanceDAOLBP__AlreadyStarted.selector);
        lbp.start(
            block.timestamp,
            softPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );
    }

    function testStartSuccess() public {
        lbp.start(
            block.timestamp,
            softPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );

        assertEq(lbp.startTime(), block.timestamp);
        assertEq(lbp.cveAmountForSale(), cveAmountForSale);
        assertEq(lbp.paymentToken(), _WETH_ADDRESS);
        assertApproxEqRel(
            lbp.softCap(),
            (cveAmountForSale * softPrice) / lbp.paymentTokenPrice(),
            0.0001e18
        );
    }

    function testCommitRevertWhenlbpNotStarted() public {
        _prepareCommit(address(this), 1e18);

        vm.expectRevert(CurvanceDAOLBP.CurvanceDAOLBP__NotStarted.selector);
        lbp.commit(1e18);
    }

    function testCommitRevertWhenlbpClosed() public {
        testStartSuccess();

        _prepareCommit(address(this), 1e18);

        skip(lbp.SALE_PERIOD() + 1);

        vm.expectRevert(CurvanceDAOLBP.CurvanceDAOLBP__Closed.selector);
        lbp.commit(1e18);
    }

    function testCommitSuccess() public {
        testStartSuccess();

        // before softcap
        uint256 commitAmount = lbp.softCap();
        _prepareCommit(address(this), commitAmount);
        lbp.commit(commitAmount);
        assertEq(lbp.saleCommitted(), commitAmount);
        assertEq(lbp.userCommitted(address(this)), commitAmount);
        assertEq(
            lbp.currentPrice(),
            lbp.softPriceInpaymentToken()
        );
    }

    function testClaimRevertWhenPubliSaleNotStarted() public {
        vm.expectRevert(CurvanceDAOLBP.CurvanceDAOLBP__NotStarted.selector);
        lbp.claim();
    }

    function testClaimRevertWhenPubliSaleInProgress() public {
        testStartSuccess();

        vm.expectRevert(CurvanceDAOLBP.CurvanceDAOLBP__InSale.selector);
        lbp.claim();
    }

    function testClaimSuccess() public {
        testStartSuccess();

        uint256 commitAmount = lbp.softCap();
        _prepareCommit(address(this), commitAmount);
        lbp.commit(commitAmount);

        skip(lbp.SALE_PERIOD() + 1);

        assertEq(
            lbp.currentPrice(),
            lbp.softPriceInpaymentToken()
        );

        lbp.claim();

        assertEq(lbp.userCommitted(address(this)), 0);
        assertEq(
            cve.balanceOf(address(this)),
            (commitAmount * 1e18) / lbp.currentPrice()
        );
    }

    function testCommitSaleAmount() public {
        testStartSuccess();

        address user1 = address(100000001);
        address user2 = address(100000002);

        uint256 commitAmount = 100e18;
        _prepareCommit(user1, commitAmount);
        _prepareCommit(user2, commitAmount);

        vm.prank(user1);
        lbp.commit(commitAmount);
        vm.prank(user2);
        lbp.commit(commitAmount);

        skip(lbp.SALE_PERIOD() + 1);

        vm.prank(user1);
        lbp.claim();
        vm.prank(user2);
        lbp.claim();

        assertGt(cve.balanceOf(user1), 0);
        assertEq(cve.balanceOf(user1), cve.balanceOf(user2));
    }

    function _prepareCommit(address user, uint256 amount) internal {
        deal(_WETH_ADDRESS, user, amount);
        vm.startPrank(user);
        IERC20(_WETH_ADDRESS).approve(address(lbp), amount);
        vm.stopPrank();
    }
}
