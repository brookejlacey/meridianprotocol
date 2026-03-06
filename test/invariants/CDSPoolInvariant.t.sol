// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {StdInvariant} from "@forge-std/StdInvariant.sol";

import {CDSPool} from "../../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../../src/shield/CDSPoolFactory.sol";
import {ICDSPool} from "../../src/interfaces/ICDSPool.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

/// @title CDSPool Invariant Handler
/// @dev Drives random actions against the pool for invariant testing
contract CDSPoolHandler is Test {
    CDSPool public pool;
    MockYieldSource public token;
    address[] public actors;

    constructor(CDSPool _pool, MockYieldSource _token) {
        pool = _pool;
        token = _token;

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            token.mint(actor, 100_000_000e18);
            vm.prank(actor);
            token.approve(address(pool), type(uint256).max);
        }
    }

    function deposit(uint256 actorIdx, uint256 amount) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        amount = bound(amount, 1e18, 1_000_000e18);
        vm.prank(actors[actorIdx]);
        pool.deposit(amount);
    }

    function withdraw(uint256 actorIdx, uint256 shares) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        address actor = actors[actorIdx];
        uint256 maxShares = pool.sharesOf(actor);
        if (maxShares == 0) return;

        // Check LP cooldown
        if (block.timestamp < pool.lastDepositTime(actor) + pool.LP_COOLDOWN()) return;

        shares = bound(shares, 1, maxShares);

        // Can't withdraw if undercollateralized
        uint256 assets = pool.convertToAssets(shares);
        if (pool.totalAssets() - assets < pool.totalProtectionSold()) return;

        vm.prank(actor);
        pool.withdraw(shares);
    }

    function buyProtection(uint256 actorIdx, uint256 notional) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        uint256 maxProtection = pool.totalAssets() * 95 / 100 - pool.totalProtectionSold();
        if (maxProtection < 1e18) return;

        notional = bound(notional, 1e18, maxProtection);
        uint256 premium = pool.quoteProtection(notional);
        if (premium == 0) return;

        vm.prank(actors[actorIdx]);
        pool.buyProtection(notional, premium + 1e18);
    }

    function accrueTime(uint256 warpSeconds) external {
        warpSeconds = bound(warpSeconds, 1 hours, 30 days);
        vm.warp(block.timestamp + warpSeconds);
        pool.accrueAllPremiums();
    }
}

/// @title CDSPool Invariant Tests
contract CDSPoolInvariantTest is StdInvariant, Test {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;

    CDSPool pool;
    MockYieldSource usdc;
    CDSPoolHandler handler;

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        CreditEventOracle oracle = new CreditEventOracle();
        CDSPoolFactory factory = new CDSPoolFactory(address(this), address(this), 0);

        pool = CDSPool(factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: makeAddr("vault"),
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        })));

        handler = new CDSPoolHandler(pool, usdc);

        // Seed initial liquidity
        usdc.mint(address(this), 10_000_000e18);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(1_000_000e18);

        targetContract(address(handler));
    }

    /// @dev Pool assets must always cover outstanding protection
    function invariant_poolSolvency() public view {
        assertGe(
            pool.totalAssets(),
            pool.totalProtectionSold(),
            "INVARIANT: pool assets < protection sold"
        );
    }

    /// @dev Total shares must be > 0 when assets > 0 (no zombie state)
    function invariant_noZombieShares() public view {
        if (pool.totalAssets() > 0) {
            assertGt(pool.totalShares(), 0, "INVARIANT: assets > 0 but shares = 0");
        }
    }

    /// @dev Utilization rate must never exceed 100%
    function invariant_utilizationCapped() public view {
        assertLe(pool.utilizationRate(), WAD, "INVARIANT: utilization > 100%");
    }
}
