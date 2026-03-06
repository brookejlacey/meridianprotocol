// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../../src/yield/YieldVault.sol";
import {YieldVaultFactory} from "../../src/yield/YieldVaultFactory.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {StrategyRouter} from "../../src/yield/StrategyRouter.sol";
import {LPIncentiveGauge} from "../../src/yield/LPIncentiveGauge.sol";
import {CDSPool} from "../../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../../src/shield/CDSPoolFactory.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract YieldVaultPausableTest is Test {
    uint256 constant WEEK = 7 days;
    uint256 constant DAY = 1 days;

    MockYieldSource usdc;
    ForgeFactory forgeFactory;
    ForgeVault forgeVault;
    YieldVaultFactory yvFactory;
    YieldVault yv;

    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address pauseAdmin = makeAddr("pauseAdmin");
    address alice = makeAddr("alice");
    address notAdmin = makeAddr("notAdmin");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

        uint256 nonce = vm.getNonce(address(forgeFactory));
        address predicted = vm.computeCreateAddress(address(forgeFactory), nonce);

        TrancheToken senior = new TrancheToken("Senior", "SR", predicted, 0);
        TrancheToken mezz = new TrancheToken("Mezz", "MZ", predicted, 1);
        TrancheToken equity = new TrancheToken("Equity", "EQ", predicted, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(senior)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mezz)});
        params[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(equity)});

        vm.prank(makeAddr("originator"));
        address fv = forgeFactory.createVault(ForgeFactory.CreateVaultParams({
            underlyingAsset: address(usdc),
            trancheTokenAddresses: [address(senior), address(mezz), address(equity)],
            trancheParams: params,
            distributionInterval: WEEK
        }));
        forgeVault = ForgeVault(fv);

        yvFactory = new YieldVaultFactory(pauseAdmin);
        address yvAddr = yvFactory.createYieldVault(fv, 0, "Auto Senior", "acSR", DAY);
        yv = YieldVault(yvAddr);

        usdc.mint(alice, 10_000_000e18);
        vm.prank(alice);
        usdc.approve(address(yv), type(uint256).max);

        // Deposit before pause
        vm.prank(alice);
        yv.deposit(500_000e18, alice);
    }

    function test_pause_onlyPauseAdmin() public {
        vm.prank(pauseAdmin);
        yv.pause();
        assertTrue(yv.paused());
    }

    function test_pause_revertNotAdmin() public {
        vm.prank(notAdmin);
        vm.expectRevert("YieldVault: not pause admin");
        yv.pause();
    }

    function test_whenPaused_depositReverts() public {
        vm.prank(pauseAdmin);
        yv.pause();

        vm.prank(alice);
        vm.expectRevert();
        yv.deposit(10_000e18, alice);
    }

    function test_whenPaused_compoundReverts() public {
        // Generate yield
        usdc.mint(address(forgeVault), 10_000e18);
        vm.warp(block.timestamp + WEEK);
        forgeVault.triggerWaterfall();

        vm.prank(pauseAdmin);
        yv.pause();

        vm.warp(block.timestamp + DAY);
        vm.expectRevert();
        yv.compound();
    }

    function test_whenPaused_withdrawWorks() public {
        vm.prank(pauseAdmin);
        yv.pause();

        uint256 shares = yv.balanceOf(alice);
        vm.prank(alice);
        yv.redeem(shares, alice, alice);
    }

    function test_unpause_restoresDeposit() public {
        vm.prank(pauseAdmin);
        yv.pause();

        vm.prank(pauseAdmin);
        yv.unpause();

        vm.prank(alice);
        yv.deposit(10_000e18, alice);
    }
}

contract StrategyRouterPausableTest is Test {
    uint256 constant WEEK = 7 days;
    uint256 constant DAY = 1 days;

    MockYieldSource usdc;
    ForgeFactory forgeFactory;
    ForgeVault forgeVault;
    YieldVaultFactory yvFactory;
    YieldVault yv;
    StrategyRouter router;

    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address governance;
    address alice = makeAddr("alice");
    address notGov = makeAddr("notGov");

    function setUp() public {
        governance = address(this);
        usdc = new MockYieldSource("USDC", "USDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

        uint256 nonce = vm.getNonce(address(forgeFactory));
        address predicted = vm.computeCreateAddress(address(forgeFactory), nonce);

        TrancheToken senior = new TrancheToken("Senior", "SR", predicted, 0);
        TrancheToken mezz = new TrancheToken("Mezz", "MZ", predicted, 1);
        TrancheToken equity = new TrancheToken("Equity", "EQ", predicted, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(senior)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mezz)});
        params[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(equity)});

        vm.prank(makeAddr("originator"));
        address fv = forgeFactory.createVault(ForgeFactory.CreateVaultParams({
            underlyingAsset: address(usdc),
            trancheTokenAddresses: [address(senior), address(mezz), address(equity)],
            trancheParams: params,
            distributionInterval: WEEK
        }));
        forgeVault = ForgeVault(fv);

        yvFactory = new YieldVaultFactory(address(this));
        address yvAddr = yvFactory.createYieldVault(fv, 0, "Auto Senior", "acSR", DAY);
        yv = YieldVault(yvAddr);

        router = new StrategyRouter(governance);

        // Create a strategy
        address[] memory vaults = new address[](1);
        vaults[0] = address(yv);
        uint256[] memory allocs = new uint256[](1);
        allocs[0] = 10_000;
        router.createStrategy("All Senior", vaults, allocs);

        usdc.mint(alice, 10_000_000e18);
        vm.prank(alice);
        usdc.approve(address(router), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(yv), type(uint256).max);
    }

    function test_pause_onlyGovernance() public {
        router.pause();
        assertTrue(router.paused());
    }

    function test_pause_revertNotGovernance() public {
        vm.prank(notGov);
        vm.expectRevert("StrategyRouter: not governance");
        router.pause();
    }

    function test_whenPaused_openPositionReverts() public {
        router.pause();

        vm.prank(alice);
        vm.expectRevert();
        router.openPosition(0, 100_000e18);
    }

    function test_unpause_restoresOpenPosition() public {
        router.pause();
        router.unpause();

        vm.prank(alice);
        router.openPosition(0, 100_000e18);
    }
}

contract LPIncentiveGaugePausableTest is Test {
    uint256 constant YEAR = 365 days;

    CDSPool pool;
    CDSPoolFactory poolFactory;
    MockYieldSource usdc;
    MockYieldSource rewardToken;
    CreditEventOracle oracle;
    LPIncentiveGauge gauge;

    address protocolAdmin = makeAddr("protocolAdmin");
    address governance;
    address lp = makeAddr("lp");
    address notGov = makeAddr("notGov");

    function setUp() public {
        governance = address(this);
        usdc = new MockYieldSource("USDC", "USDC", 18);
        rewardToken = new MockYieldSource("RWD", "RWD", 18);
        oracle = new CreditEventOracle();
        poolFactory = new CDSPoolFactory(address(this), protocolAdmin, 0);

        address poolAddr = poolFactory.createPool(
            CDSPoolFactory.CreatePoolParams({
                referenceAsset: makeAddr("refVault"),
                collateralToken: address(usdc),
                oracle: address(oracle),
                maturity: block.timestamp + YEAR,
                baseSpreadWad: 0.03e18,
                slopeWad: 0.5e18
            })
        );
        pool = CDSPool(poolAddr);

        gauge = new LPIncentiveGauge(address(pool), address(rewardToken), governance);

        // LP deposits into pool
        usdc.mint(lp, 1_000_000e18);
        vm.prank(lp);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(lp);
        pool.deposit(500_000e18);
    }

    function test_pause_onlyGovernance() public {
        gauge.pause();
        assertTrue(gauge.paused());
    }

    function test_pause_revertNotGovernance() public {
        vm.prank(notGov);
        vm.expectRevert("LPIncentiveGauge: not governance");
        gauge.pause();
    }

    function test_whenPaused_notifyRewardAmountReverts() public {
        gauge.pause();

        rewardToken.mint(address(this), 100_000e18);
        rewardToken.approve(address(gauge), 100_000e18);

        vm.expectRevert();
        gauge.notifyRewardAmount(100_000e18, 30 days);
    }

    function test_whenPaused_claimRewardWorks() public {
        // Fund and start rewards
        rewardToken.mint(address(this), 100_000e18);
        rewardToken.approve(address(gauge), 100_000e18);
        gauge.notifyRewardAmount(100_000e18, 30 days);

        // Checkpoint LP and accrue
        vm.prank(lp);
        gauge.checkpoint(lp);
        vm.warp(block.timestamp + 7 days);

        gauge.pause();

        // Claim should still work when paused
        vm.prank(lp);
        gauge.claimReward();
    }

    function test_unpause_restoresNotify() public {
        gauge.pause();
        gauge.unpause();

        rewardToken.mint(address(this), 100_000e18);
        rewardToken.approve(address(gauge), 100_000e18);
        gauge.notifyRewardAmount(100_000e18, 30 days);
    }
}
