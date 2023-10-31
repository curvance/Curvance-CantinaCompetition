// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { CVEPublicSale } from "contracts/sale/CVEPublicSale.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import "tests/market/TestBaseMarket.sol";

contract TestCVEPublicSale is TestBaseMarket {
    CVEPublicSale public publicSale;

    uint256 softPrice = 10e18; // $10
    uint256 hardPrice = 100e18; // $100
    uint256 cveAmountForSale = 10000e18;

    function setUp() public override {
        super.setUp();

        publicSale = new CVEPublicSale(
            ICentralRegistry(address(centralRegistry))
        );

        cve.transfer(address(publicSale), cve.balanceOf(address(this)));
    }

    function testInitialize() public {
        assertEq(publicSale.cve(), address(cve));
    }

    function testStartRevertWhenInvalidStartTime() public {
        vm.expectRevert(
            CVEPublicSale.CVEPublicSale__InvalidStartTime.selector
        );
        publicSale.start(
            block.timestamp - 1,
            softPrice,
            hardPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );
    }

    function testStartRevertWhenInvalidPrice() public {
        vm.expectRevert(CVEPublicSale.CVEPublicSale__InvalidPrice.selector);
        publicSale.start(
            block.timestamp,
            hardPrice + 1,
            hardPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );
    }

    function testStartRevertWhenAlreadyStarted() public {
        publicSale.start(
            block.timestamp,
            softPrice,
            hardPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );

        vm.expectRevert(CVEPublicSale.CVEPublicSale__AlreadyStarted.selector);
        publicSale.start(
            block.timestamp,
            softPrice,
            hardPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );
    }

    function testStartSuccess() public {
        publicSale.start(
            block.timestamp,
            softPrice,
            hardPrice,
            cveAmountForSale,
            _WETH_ADDRESS
        );

        assertEq(publicSale.startTime(), block.timestamp);
        assertEq(publicSale.cveAmountForSale(), cveAmountForSale);
        assertEq(publicSale.payToken(), _WETH_ADDRESS);
        assertApproxEqRel(
            publicSale.softCap(),
            (cveAmountForSale * softPrice) / publicSale.payTokenPrice(),
            0.0001e18
        );
        assertApproxEqRel(
            publicSale.hardCap(),
            (cveAmountForSale * hardPrice) / publicSale.payTokenPrice(),
            0.0001e18
        );
    }

    function testCommitRevertWhenPublicSaleNotStarted() public {
        _prepareCommit(address(this), 1e18);

        vm.expectRevert(CVEPublicSale.CVEPublicSale__NotStarted.selector);
        publicSale.commit(1e18);
    }

    function testCommitRevertWhenPublicSaleEnded() public {
        testStartSuccess();

        _prepareCommit(address(this), 1e18);

        skip(publicSale.SALE_PERIOD() + 1);

        vm.expectRevert(CVEPublicSale.CVEPublicSale__Ended.selector);
        publicSale.commit(1e18);
    }

    function testCommitRevertWhenPublicSaleHardCap() public {
        testStartSuccess();

        _prepareCommit(address(this), 10000e18);
        publicSale.commit(10000e18);

        vm.expectRevert(CVEPublicSale.CVEPublicSale__HardCap.selector);
        publicSale.commit(1e18);
    }

    function testCommitSuccess() public {
        testStartSuccess();

        // before softcap
        uint256 commitAmount = publicSale.softCap();
        _prepareCommit(address(this), commitAmount);
        publicSale.commit(commitAmount);
        assertEq(publicSale.saleCommitted(), commitAmount);
        assertEq(publicSale.userCommitted(address(this)), commitAmount);
        assertEq(publicSale.currentPrice(), publicSale.softPriceInPayToken());

        // before hardcap
        commitAmount = publicSale.hardCap();
        _prepareCommit(address(this), commitAmount);
        publicSale.commit(commitAmount);
        assertEq(publicSale.saleCommitted(), commitAmount);
        assertEq(publicSale.userCommitted(address(this)), commitAmount);
        assertEq(publicSale.currentPrice(), publicSale.hardPriceInPayToken());
    }

    function testRefundRevertWhenPubliSaleNotStarted() public {
        vm.expectRevert(CVEPublicSale.CVEPublicSale__NotStarted.selector);
        publicSale.refund();
    }

    function testRefundRevertWhenPubliSaleInProgress() public {
        testStartSuccess();

        vm.expectRevert(CVEPublicSale.CVEPublicSale__InSale.selector);
        publicSale.refund();
    }

    function testRefundRevertWhenPubliSaleSuccess() public {
        testStartSuccess();

        uint256 commitAmount = publicSale.softCap();
        _prepareCommit(address(this), commitAmount);
        publicSale.commit(commitAmount);

        skip(publicSale.SALE_PERIOD() + 1);

        vm.expectRevert(CVEPublicSale.CVEPublicSale__Success.selector);
        publicSale.refund();
    }

    function testRefundSuccess() public {
        testStartSuccess();

        uint256 commitAmount = 1e18;
        _prepareCommit(address(this), commitAmount);
        publicSale.commit(commitAmount);

        skip(publicSale.SALE_PERIOD() + 1);

        publicSale.refund();

        assertEq(publicSale.userCommitted(address(this)), 0);
        assertEq(IERC20(_WETH_ADDRESS).balanceOf(address(this)), commitAmount);
    }

    function testClaimRevertWhenPubliSaleNotStarted() public {
        vm.expectRevert(CVEPublicSale.CVEPublicSale__NotStarted.selector);
        publicSale.claim();
    }

    function testClaimRevertWhenPubliSaleInProgress() public {
        testStartSuccess();

        vm.expectRevert(CVEPublicSale.CVEPublicSale__InSale.selector);
        publicSale.claim();
    }

    function testClaimRevertWhenPubliSaleFailed() public {
        testStartSuccess();

        uint256 commitAmount = publicSale.softCap() - 1;
        _prepareCommit(address(this), commitAmount);
        publicSale.commit(commitAmount);

        skip(publicSale.SALE_PERIOD() + 1);

        vm.expectRevert(CVEPublicSale.CVEPublicSale__Failed.selector);
        publicSale.claim();
    }

    function testClaimSuccess() public {
        testStartSuccess();

        uint256 commitAmount = publicSale.softCap();
        _prepareCommit(address(this), commitAmount);
        publicSale.commit(commitAmount);

        skip(publicSale.SALE_PERIOD() + 1);

        assertEq(publicSale.currentPrice(), publicSale.softPriceInPayToken());

        publicSale.claim();

        assertEq(publicSale.userCommitted(address(this)), 0);
        assertEq(
            cve.balanceOf(address(this)),
            (commitAmount * 1e18) / publicSale.currentPrice()
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
        publicSale.commit(commitAmount);
        vm.prank(user2);
        publicSale.commit(commitAmount);

        skip(publicSale.SALE_PERIOD() + 1);

        vm.prank(user1);
        publicSale.claim();
        vm.prank(user2);
        publicSale.claim();

        assertGt(cve.balanceOf(user1), 0);
        assertEq(cve.balanceOf(user1), cve.balanceOf(user2));
    }

    function _prepareCommit(address user, uint256 amount) internal {
        deal(_WETH_ADDRESS, user, amount);
        vm.startPrank(user);
        IERC20(_WETH_ADDRESS).approve(address(publicSale), amount);
        vm.stopPrank();
    }
}
