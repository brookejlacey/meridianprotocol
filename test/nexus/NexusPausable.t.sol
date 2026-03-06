// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {NexusHub} from "../../src/nexus/NexusHub.sol";
import {InsurancePool} from "../../src/nexus/InsurancePool.sol";
import {CollateralOracle} from "../../src/nexus/CollateralOracle.sol";
import {MockTeleporter} from "../../src/mocks/MockTeleporter.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract NexusHubPausableTest is Test {
    NexusHub hub;
    CollateralOracle oracle;
    MockTeleporter teleporter;
    MockYieldSource usdc;

    address alice = makeAddr("alice");
    address notOwner = makeAddr("notOwner");

    bytes32 constant CCHAIN_ID = bytes32(uint256(43113));

    function setUp() public {
        oracle = new CollateralOracle();
        teleporter = new MockTeleporter(CCHAIN_ID);

        hub = new NexusHub(
            address(oracle),
            address(teleporter),
            11e17, // 110% liquidation threshold
            500    // 5% penalty
        );

        usdc = new MockYieldSource("Mock USDC", "mUSDC", 18);
        oracle.registerAsset(address(usdc), 1e18, 9500);

        usdc.mint(alice, 1_000_000e18);
        vm.prank(alice);
        usdc.approve(address(hub), type(uint256).max);

        // Alice opens margin account and deposits before pause
        vm.prank(alice);
        hub.openMarginAccount();
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 500_000e18);
    }

    function test_pause_onlyOwner() public {
        hub.pause();
        assertTrue(hub.paused());
    }

    function test_pause_revertNotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        hub.pause();
    }

    function test_whenPaused_openMarginAccountReverts() public {
        hub.pause();

        address newUser = makeAddr("newUser");
        vm.prank(newUser);
        vm.expectRevert();
        hub.openMarginAccount();
    }

    function test_whenPaused_depositCollateralReverts() public {
        hub.pause();

        vm.prank(alice);
        vm.expectRevert();
        hub.depositCollateral(address(usdc), 10_000e18);
    }

    function test_whenPaused_withdrawCollateralWorks() public {
        hub.pause();

        vm.prank(alice);
        hub.withdrawCollateral(address(usdc), 10_000e18);
    }

    function test_unpause_restoresDeposit() public {
        hub.pause();
        hub.unpause();
        assertFalse(hub.paused());

        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);
    }
}

contract InsurancePoolPausableTest is Test {
    InsurancePool pool;
    MockYieldSource usdc;

    address hub = makeAddr("hub");
    address alice = makeAddr("alice");
    address notOwner = makeAddr("notOwner");

    function setUp() public {
        usdc = new MockYieldSource("Mock USDC", "mUSDC", 18);
        pool = new InsurancePool(address(usdc), hub, 50);

        usdc.mint(alice, 1_000_000e18);
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);

        // Deposit before pause
        vm.prank(alice);
        pool.deposit(500_000e18);
    }

    function test_pause_onlyOwner() public {
        pool.pause();
        assertTrue(pool.paused());
    }

    function test_pause_revertNotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        pool.pause();
    }

    function test_whenPaused_depositReverts() public {
        pool.pause();

        vm.prank(alice);
        vm.expectRevert();
        pool.deposit(10_000e18);
    }

    function test_whenPaused_withdrawWorks() public {
        pool.pause();

        vm.prank(alice);
        pool.withdraw(100_000e18);
    }

    function test_unpause_restoresDeposit() public {
        pool.pause();
        pool.unpause();

        vm.prank(alice);
        pool.deposit(10_000e18);
    }
}
