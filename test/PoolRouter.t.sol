// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";

import {PoolRouter} from "../src/PoolRouter.sol";
import {CDSPool} from "../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../src/shield/CDSPoolFactory.sol";
import {ICDSPool} from "../src/interfaces/ICDSPool.sol";
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";

contract PoolRouterTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;

    MockYieldSource usdc;
    CreditEventOracle oracle;
    CDSPoolFactory factory;
    PoolRouter router;

    address alice = makeAddr("alice"); // LP
    address bob = makeAddr("bob"); // Buyer
    address vault = makeAddr("vault");

    CDSPool pool1;
    CDSPool pool2;
    CDSPool pool3;

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        oracle = new CreditEventOracle();
        factory = new CDSPoolFactory(address(this), address(this), 0);
        router = new PoolRouter(address(factory), address(this));

        // Create 3 pools with different base spreads (different pricing)
        pool1 = CDSPool(factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18, // 2% — cheapest
            slopeWad: 0.05e18
        })));

        pool2 = CDSPool(factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.03e18, // 3% — mid
            slopeWad: 0.05e18
        })));

        pool3 = CDSPool(factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.05e18, // 5% — most expensive
            slopeWad: 0.05e18
        })));

        // Fund and deposit liquidity
        usdc.mint(alice, 100_000_000e18);
        vm.startPrank(alice);
        usdc.approve(address(pool1), type(uint256).max);
        usdc.approve(address(pool2), type(uint256).max);
        usdc.approve(address(pool3), type(uint256).max);
        pool1.deposit(500_000e18);
        pool2.deposit(500_000e18);
        pool3.deposit(500_000e18);
        vm.stopPrank();

        // Fund buyer
        usdc.mint(bob, 100_000_000e18);
        vm.prank(bob);
        usdc.approve(address(router), type(uint256).max);
    }

    function test_quoteRouted_basic() public view {
        PoolRouter.RouteQuote memory quote = router.quoteRouted(vault, 100_000e18);
        assertGt(quote.totalPremium, 0, "Total premium > 0");
        assertEq(quote.totalNotional, 100_000e18, "Full notional quoted");
        // Should route to cheapest pool first
        assertEq(quote.pools[0], address(pool1), "Cheapest pool first");
    }

    function test_quoteRouted_largeOrder_splitAcrossPools() public view {
        // Order large enough to need multiple pools
        PoolRouter.RouteQuote memory quote = router.quoteRouted(vault, 1_200_000e18);
        assertEq(quote.totalNotional, 1_200_000e18, "Full notional quoted");
        // Should use at least 3 pools
        assertGt(quote.pools.length, 1, "Multiple pools used");
    }

    function test_buyProtectionRouted_basic() public {
        PoolRouter.RouteQuote memory quote = router.quoteRouted(vault, 100_000e18);

        vm.prank(bob);
        PoolRouter.FillResult[] memory results = router.buyProtectionRouted(
            vault, 100_000e18, quote.totalPremium + 1e18
        );

        assertEq(results.length, 1, "Single pool fill");
        assertEq(results[0].pool, address(pool1), "Cheapest pool used");
        assertEq(results[0].notional, 100_000e18, "Full notional filled");
    }

    function test_buyProtectionRouted_multiPool() public {
        // Buy enough to span multiple pools
        PoolRouter.RouteQuote memory quote = router.quoteRouted(vault, 1_200_000e18);

        vm.prank(bob);
        PoolRouter.FillResult[] memory results = router.buyProtectionRouted(
            vault, 1_200_000e18, quote.totalPremium + 1_000e18
        );

        uint256 totalFilled;
        for (uint256 i = 0; i < results.length; i++) {
            totalFilled += results[i].notional;
        }
        assertEq(totalFilled, 1_200_000e18, "Full notional filled");
        assertGt(results.length, 1, "Multiple pools used");
    }

    function test_buyProtectionRouted_cheapestFirst() public {
        PoolRouter.RouteQuote memory quote = router.quoteRouted(vault, 200_000e18);

        vm.prank(bob);
        PoolRouter.FillResult[] memory results = router.buyProtectionRouted(
            vault, 200_000e18, quote.totalPremium + 1_000e18
        );

        // First fill should be from cheapest pool
        assertEq(results[0].pool, address(pool1), "Pool1 (cheapest) filled first");
    }

    function test_buyProtectionRouted_revert_zeroNotional() public {
        vm.prank(bob);
        vm.expectRevert("PoolRouter: zero notional");
        router.buyProtectionRouted(vault, 0, 100_000e18);
    }

    function test_buyProtectionRouted_revert_noPools() public {
        address fakeVault = makeAddr("fakeVault");
        vm.prank(bob);
        vm.expectRevert("PoolRouter: no pools");
        router.buyProtectionRouted(fakeVault, 100_000e18, 100_000e18);
    }

    function test_quoteRouted_noPools() public {
        address fakeVault = makeAddr("fakeVault");
        PoolRouter.RouteQuote memory quote = router.quoteRouted(fakeVault, 100_000e18);
        assertEq(quote.totalPremium, 0);
    }
}
