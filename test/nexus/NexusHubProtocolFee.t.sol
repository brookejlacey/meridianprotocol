// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {NexusHub} from "../../src/nexus/NexusHub.sol";
import {CollateralOracle} from "../../src/nexus/CollateralOracle.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";
import {MockTeleporter} from "../../src/mocks/MockTeleporter.sol";
import {ProtocolTreasury} from "../../src/ProtocolTreasury.sol";
import {INexusHub} from "../../src/interfaces/INexusHub.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

contract NexusHubProtocolFeeTest is Test {
    NexusHub hub;
    CollateralOracle oracle;
    MockYieldSource usdc;
    MockYieldSource weth;
    MockTeleporter teleporter;
    ProtocolTreasury treasury;

    address admin = address(this);
    address alice = makeAddr("alice");
    address liquidator = makeAddr("liquidator");

    uint256 constant THRESHOLD = 1.1e18; // 110%
    uint256 constant PENALTY_BPS = 500; // 5%
    uint256 constant LIQ_FEE_BPS = 1000; // 10%

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        weth = new MockYieldSource("WETH", "WETH", 18);
        teleporter = new MockTeleporter(bytes32("fuji"));
        treasury = new ProtocolTreasury(admin);

        oracle = new CollateralOracle();
        oracle.registerAsset(address(usdc), 1e18, 10000); // $1, 100% weight
        oracle.registerAsset(address(weth), 2000e18, 8500); // $2000, 85% weight

        hub = new NexusHub(
            address(oracle),
            address(teleporter),
            THRESHOLD,
            PENALTY_BPS
        );

        // Set treasury and fee
        hub.setTreasury(address(treasury));
        hub.setLiquidationFeeBps(LIQ_FEE_BPS);

        // Setup alice with margin account
        vm.startPrank(alice);
        hub.openMarginAccount();

        usdc.mint(alice, 100_000e18);
        usdc.approve(address(hub), type(uint256).max);
        hub.depositCollateral(address(usdc), 10_000e18);
        vm.stopPrank();

        // Set obligation so alice is unhealthy
        hub.setObligation(alice, 9_500e18);
    }

    function test_liquidationFeeSplit() public {
        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        uint256 liquidatorBefore = usdc.balanceOf(liquidator);

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        uint256 treasuryGain = usdc.balanceOf(address(treasury)) - treasuryBefore;
        uint256 liquidatorGain = usdc.balanceOf(liquidator) - liquidatorBefore;

        // Treasury should get 10% of seized, liquidator 90%
        assertGt(treasuryGain, 0);
        assertGt(liquidatorGain, 0);
        // Treasury is 10% of total seized
        uint256 totalGain = treasuryGain + liquidatorGain;
        assertApproxEqRel(treasuryGain, MeridianMath.bpsMul(totalGain, LIQ_FEE_BPS), 1e15);
    }

    function test_liquidationFeeZero_liquidatorGetsAll() public {
        hub.setLiquidationFeeBps(0);

        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        uint256 liquidatorBefore = usdc.balanceOf(liquidator);

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        assertEq(usdc.balanceOf(address(treasury)), treasuryBefore);
        assertGt(usdc.balanceOf(liquidator), liquidatorBefore);
    }

    function test_liquidationFee_multiAsset() public {
        // Give alice WETH too
        weth.mint(alice, 5e18); // 5 WETH = $10,000
        vm.startPrank(alice);
        weth.approve(address(hub), type(uint256).max);
        hub.depositCollateral(address(weth), 5e18);
        vm.stopPrank();

        // Increase obligation so both assets get seized
        hub.setObligation(alice, 18_000e18);

        uint256 treasuryUsdcBefore = usdc.balanceOf(address(treasury));
        uint256 treasuryWethBefore = weth.balanceOf(address(treasury));

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        // Treasury should have received fees in both tokens
        uint256 treasuryUsdcGain = usdc.balanceOf(address(treasury)) - treasuryUsdcBefore;
        uint256 treasuryWethGain = weth.balanceOf(address(treasury)) - treasuryWethBefore;

        // At least one asset should have a fee
        assertTrue(treasuryUsdcGain > 0 || treasuryWethGain > 0);
    }

    function test_setTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        hub.setTreasury(newTreasury);
        assertEq(hub.treasury(), newTreasury);
    }

    function test_setTreasury_revertZeroAddress() public {
        vm.expectRevert("NexusHub: zero treasury");
        hub.setTreasury(address(0));
    }

    function test_setTreasury_emitsEvent() public {
        address newTreasury = makeAddr("newTreasury");
        vm.expectEmit(false, false, false, true);
        emit INexusHub.TreasuryUpdated(address(treasury), newTreasury);
        hub.setTreasury(newTreasury);
    }

    function test_setLiquidationFeeBps() public {
        hub.setLiquidationFeeBps(2000);
        assertEq(hub.liquidationFeeBps(), 2000);
    }

    function test_setLiquidationFeeBps_revertAboveMax() public {
        vm.expectRevert("NexusHub: fee exceeds max");
        hub.setLiquidationFeeBps(5001);
    }

    function test_setLiquidationFeeBps_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit INexusHub.LiquidationFeeUpdated(LIQ_FEE_BPS, 2000);
        hub.setLiquidationFeeBps(2000);
    }

    function test_totalProtocolFeesCollected_tracks() public {
        assertEq(hub.totalProtocolFeesCollected(), 0);

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        assertGt(hub.totalProtocolFeesCollected(), 0);
    }
}
