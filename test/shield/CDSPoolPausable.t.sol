// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {CDSPool} from "../../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../../src/shield/CDSPoolFactory.sol";
import {ICDSPool} from "../../src/interfaces/ICDSPool.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {ICreditEventOracle} from "../../src/interfaces/ICreditEventOracle.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract CDSPoolPausableTest is Test {
    CDSPool pool;
    CDSPoolFactory poolFactory;
    MockYieldSource usdc;
    CreditEventOracle oracle;

    address protocolAdmin = makeAddr("protocolAdmin");
    address referenceVault = makeAddr("referenceVault");
    address lp = makeAddr("lp");
    address buyer = makeAddr("buyer");

    uint256 constant YEAR = 365 days;

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        oracle = new CreditEventOracle();
        poolFactory = new CDSPoolFactory(address(this), protocolAdmin, 0);

        address poolAddr = poolFactory.createPool(
            CDSPoolFactory.CreatePoolParams({
                referenceAsset: referenceVault,
                collateralToken: address(usdc),
                oracle: address(oracle),
                maturity: block.timestamp + YEAR,
                baseSpreadWad: 0.03e18,
                slopeWad: 0.5e18
            })
        );
        pool = CDSPool(poolAddr);

        usdc.mint(lp, 1_000_000e18);
        vm.prank(lp);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(lp);
        pool.deposit(500_000e18);

        usdc.mint(buyer, 500_000e18);
        vm.prank(buyer);
        usdc.approve(address(pool), type(uint256).max);
    }

    function test_pause_onlyProtocolAdmin() public {
        vm.prank(protocolAdmin);
        pool.pause();
        assertTrue(pool.paused());
    }

    function test_pause_revertNotAdmin() public {
        vm.prank(buyer);
        vm.expectRevert("CDSPool: not protocol admin");
        pool.pause();
    }

    function test_whenPaused_depositReverts() public {
        vm.prank(protocolAdmin);
        pool.pause();

        vm.prank(lp);
        vm.expectRevert();
        pool.deposit(10_000e18);
    }

    function test_whenPaused_buyProtectionReverts() public {
        vm.prank(protocolAdmin);
        pool.pause();

        vm.prank(buyer);
        vm.expectRevert();
        pool.buyProtection(50_000e18, 100_000e18);
    }

    function test_whenPaused_withdrawWorks() public {
        // Advance past LP deposit cooldown
        vm.warp(block.timestamp + 2 hours);
        vm.prank(protocolAdmin);
        pool.pause();

        uint256 shares = pool.sharesOf(lp);
        vm.prank(lp);
        pool.withdraw(shares);
    }

    function test_whenPaused_closeProtectionWorks() public {
        vm.prank(buyer);
        uint256 posId = pool.buyProtection(50_000e18, 100_000e18);

        vm.prank(protocolAdmin);
        pool.pause();

        vm.prank(buyer);
        pool.closeProtection(posId);
    }

    function test_whenPaused_triggerCreditEventWorks() public {
        // Setup oracle event
        oracle.reportCreditEvent(referenceVault, ICreditEventOracle.EventType.Default, 500_000e18);
        oracle.setThreshold(referenceVault, 1);

        vm.prank(protocolAdmin);
        pool.pause();

        // Safety function should still work
        pool.triggerCreditEvent();
    }

    function test_unpause_restoresDeposit() public {
        vm.prank(protocolAdmin);
        pool.pause();

        vm.prank(protocolAdmin);
        pool.unpause();

        vm.prank(lp);
        pool.deposit(10_000e18);
    }
}
