// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolRouter} from "../src/PoolRouter.sol";
import {FlashRebalancer} from "../src/FlashRebalancer.sol";
import {SecondaryMarketRouter} from "../src/SecondaryMarketRouter.sol";
import {ISecondaryMarketRouter} from "../src/interfaces/ISecondaryMarketRouter.sol";
import {CDSPool} from "../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../src/shield/CDSPoolFactory.sol";
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";
import {MockFlashLender} from "../src/mocks/MockFlashLender.sol";

contract PoolRouterPausableTest is Test {
    uint256 constant YEAR = 365 days;

    MockYieldSource usdc;
    CreditEventOracle oracle;
    CDSPoolFactory factory;
    PoolRouter router;
    CDSPool pool;

    address pauseAdmin;
    address buyer = makeAddr("buyer");
    address lp = makeAddr("lp");
    address vault = makeAddr("vault");
    address notAdmin = makeAddr("notAdmin");

    function setUp() public {
        pauseAdmin = address(this);
        usdc = new MockYieldSource("USDC", "USDC", 18);
        oracle = new CreditEventOracle();
        factory = new CDSPoolFactory(address(this), address(this), 0);
        router = new PoolRouter(address(factory), pauseAdmin);

        pool = CDSPool(factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.03e18,
            slopeWad: 0.5e18
        })));

        // LP deposits
        usdc.mint(lp, 1_000_000e18);
        vm.prank(lp);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(lp);
        pool.deposit(500_000e18);

        // Buyer approves router
        usdc.mint(buyer, 500_000e18);
        vm.prank(buyer);
        usdc.approve(address(router), type(uint256).max);
    }

    function test_pause_onlyPauseAdmin() public {
        router.pause();
        assertTrue(router.paused());
    }

    function test_pause_revertNotAdmin() public {
        vm.prank(notAdmin);
        vm.expectRevert("PoolRouter: not pause admin");
        router.pause();
    }

    function test_whenPaused_buyProtectionRoutedReverts() public {
        router.pause();

        vm.prank(buyer);
        vm.expectRevert();
        router.buyProtectionRouted(vault, 50_000e18, 100_000e18);
    }

    function test_unpause_restoresBuy() public {
        router.pause();
        router.unpause();

        vm.prank(buyer);
        router.buyProtectionRouted(vault, 50_000e18, 100_000e18);
    }
}

contract FlashRebalancerPausableTest is Test {
    FlashRebalancer rebalancer;
    MockFlashLender flashLender;

    address pauseAdmin;
    address notAdmin = makeAddr("notAdmin");
    address alice = makeAddr("alice");

    function setUp() public {
        pauseAdmin = address(this);
        flashLender = new MockFlashLender();
        rebalancer = new FlashRebalancer(address(flashLender), pauseAdmin);
    }

    function test_pause_onlyPauseAdmin() public {
        rebalancer.pause();
        assertTrue(rebalancer.paused());
    }

    function test_pause_revertNotAdmin() public {
        vm.prank(notAdmin);
        vm.expectRevert("FlashRebalancer: not pause admin");
        rebalancer.pause();
    }

    function test_whenPaused_rebalanceReverts() public {
        rebalancer.pause();

        vm.prank(alice);
        vm.expectRevert();
        rebalancer.rebalance(makeAddr("vault"), 0, 2, 100_000e18);
    }

    function test_unpause_works() public {
        rebalancer.pause();
        rebalancer.unpause();
        assertFalse(rebalancer.paused());
    }
}

contract SecondaryMarketRouterPausableTest is Test {
    SecondaryMarketRouter router;
    MockYieldSource tokenA;
    MockYieldSource tokenB;

    address pauseAdmin;
    address notAdmin = makeAddr("notAdmin");
    address user = makeAddr("user");

    function setUp() public {
        pauseAdmin = address(this);
        tokenA = new MockYieldSource("Token A", "TKA", 18);
        tokenB = new MockYieldSource("Token B", "TKB", 18);
        router = new SecondaryMarketRouter(makeAddr("dex"), pauseAdmin);

        tokenA.mint(user, 1_000_000e18);
        vm.prank(user);
        tokenA.approve(address(router), type(uint256).max);
    }

    function test_pause_onlyPauseAdmin() public {
        router.pause();
        assertTrue(router.paused());
    }

    function test_pause_revertNotAdmin() public {
        vm.prank(notAdmin);
        vm.expectRevert("SecondaryMarketRouter: not pause admin");
        router.pause();
    }

    function test_whenPaused_swapReverts() public {
        router.pause();

        vm.prank(user);
        vm.expectRevert();
        router.swap(ISecondaryMarketRouter.SwapParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            amountIn: 1_000e18,
            minAmountOut: 900e18
        }));
    }

    function test_unpause_works() public {
        router.pause();
        router.unpause();
        assertFalse(router.paused());
    }
}
