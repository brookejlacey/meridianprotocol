// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {CDSPool} from "../../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../../src/shield/CDSPoolFactory.sol";
import {ICDSPool} from "../../src/interfaces/ICDSPool.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";
import {ProtocolTreasury} from "../../src/ProtocolTreasury.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

contract CDSPoolProtocolFeeTest is Test {
    CDSPool pool;
    CDSPoolFactory poolFactory;
    MockYieldSource usdc;
    CreditEventOracle oracle;
    ProtocolTreasury treasury;

    address protocolAdmin = makeAddr("protocolAdmin");
    address referenceVault = makeAddr("referenceVault");
    address lp = makeAddr("lp");
    address buyer = makeAddr("buyer");

    uint256 constant YEAR = 365 days;
    uint256 constant FEE_BPS = 1000; // 10%

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        treasury = new ProtocolTreasury(address(this));
        oracle = new CreditEventOracle();

        poolFactory = new CDSPoolFactory(address(treasury), protocolAdmin, FEE_BPS);

        address poolAddr = poolFactory.createPool(
            CDSPoolFactory.CreatePoolParams({
                referenceAsset: referenceVault,
                collateralToken: address(usdc),
                oracle: address(oracle),
                maturity: block.timestamp + YEAR,
                baseSpreadWad: 0.03e18,  // 3%
                slopeWad: 0.5e18
            })
        );
        pool = CDSPool(poolAddr);

        // Fund LP and deposit
        usdc.mint(lp, 1_000_000e18);
        vm.prank(lp);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(lp);
        pool.deposit(500_000e18);

        // Fund buyer
        usdc.mint(buyer, 500_000e18);
        vm.prank(buyer);
        usdc.approve(address(pool), type(uint256).max);
    }

    function test_premiumFee_treasuryReceives() public {
        // Buy protection
        vm.prank(buyer);
        pool.buyProtection(100_000e18, 50_000e18);

        // Advance time for premium accrual
        vm.warp(block.timestamp + 30 days);

        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        pool.accrueAllPremiums();
        uint256 treasuryAfter = usdc.balanceOf(address(treasury));

        // Treasury should have received 10% of accrued premiums
        assertGt(treasuryAfter, treasuryBefore);
        assertGt(pool.totalProtocolFeesCollected(), 0);
    }

    function test_premiumFee_lpGetsNetOnly() public {
        vm.prank(buyer);
        pool.buyProtection(100_000e18, 50_000e18);

        uint256 assetsBefore = pool.totalAssets();
        vm.warp(block.timestamp + 30 days);
        pool.accrueAllPremiums();
        uint256 assetsAfter = pool.totalAssets();

        // LP assets should increase by net premium (90% of accrued)
        uint256 lpGain = assetsAfter - assetsBefore;
        uint256 treasuryGain = pool.totalProtocolFeesCollected();

        // Total accrued = lpGain + treasuryGain
        // treasuryGain should be ~10% of total
        uint256 total = lpGain + treasuryGain;
        assertApproxEqRel(treasuryGain, MeridianMath.bpsMul(total, FEE_BPS), 1e15);
    }

    function test_premiumFee_zeroFeePassthrough() public {
        // Create pool with 0% fee
        CDSPoolFactory zeroFactory = new CDSPoolFactory(address(treasury), protocolAdmin, 0);
        address poolAddr = zeroFactory.createPool(
            CDSPoolFactory.CreatePoolParams({
                referenceAsset: referenceVault,
                collateralToken: address(usdc),
                oracle: address(oracle),
                maturity: block.timestamp + YEAR,
                baseSpreadWad: 0.03e18,
                slopeWad: 0.5e18
            })
        );
        CDSPool zeroPool = CDSPool(poolAddr);

        usdc.mint(lp, 500_000e18);
        vm.prank(lp);
        usdc.approve(address(zeroPool), type(uint256).max);
        vm.prank(lp);
        zeroPool.deposit(500_000e18);

        usdc.mint(buyer, 100_000e18);
        vm.prank(buyer);
        usdc.approve(address(zeroPool), type(uint256).max);
        vm.prank(buyer);
        zeroPool.buyProtection(50_000e18, 100_000e18);

        vm.warp(block.timestamp + 30 days);

        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        zeroPool.accrueAllPremiums();
        assertEq(usdc.balanceOf(address(treasury)), treasuryBefore);
        assertEq(zeroPool.totalProtocolFeesCollected(), 0);
    }

    function test_premiumFee_accumulates() public {
        vm.prank(buyer);
        pool.buyProtection(100_000e18, 50_000e18);

        // Accrual 1
        vm.warp(block.timestamp + 30 days);
        pool.accrueAllPremiums();
        uint256 fee1 = pool.totalProtocolFeesCollected();

        // Accrual 2
        vm.warp(block.timestamp + 30 days);
        pool.accrueAllPremiums();
        uint256 fee2 = pool.totalProtocolFeesCollected();

        assertGt(fee2, fee1);
    }

    function test_setProtocolFee_byAdmin() public {
        assertEq(pool.protocolFeeBps(), FEE_BPS);

        vm.prank(protocolAdmin);
        pool.setProtocolFee(2000);
        assertEq(pool.protocolFeeBps(), 2000);
    }

    function test_setProtocolFee_revertNotAdmin() public {
        vm.prank(buyer);
        vm.expectRevert("CDSPool: not protocol admin");
        pool.setProtocolFee(2000);
    }

    function test_setProtocolFee_revertAboveCap() public {
        vm.prank(protocolAdmin);
        vm.expectRevert("CDSPool: fee exceeds max");
        pool.setProtocolFee(5001);
    }

    function test_immutables() public view {
        assertEq(pool.treasury(), address(treasury));
        assertEq(pool.protocolAdmin(), protocolAdmin);
        assertEq(pool.protocolFeeBps(), FEE_BPS);
    }

    function testFuzz_feeProportional(uint256 notional) public {
        notional = bound(notional, 1_000e18, 200_000e18);

        vm.prank(buyer);
        pool.buyProtection(notional, 200_000e18);

        vm.warp(block.timestamp + 90 days);
        pool.accrueAllPremiums();

        uint256 treasuryBal = usdc.balanceOf(address(treasury));
        uint256 lpEarnings = pool.totalAssets() - 500_000e18; // subtract initial deposit

        if (treasuryBal > 0 && lpEarnings > 0) {
            uint256 totalAccrued = treasuryBal + lpEarnings;
            // Treasury should be ~10% of total
            assertApproxEqRel(treasuryBal, MeridianMath.bpsMul(totalAccrued, FEE_BPS), 1e15);
        }
    }
}
