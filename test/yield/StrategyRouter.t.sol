// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StrategyRouter} from "../../src/yield/StrategyRouter.sol";
import {YieldVault} from "../../src/yield/YieldVault.sol";
import {YieldVaultFactory} from "../../src/yield/YieldVaultFactory.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract StrategyRouterTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant WEEK = 7 days;
    uint256 constant DAY = 1 days;

    MockYieldSource usdc;
    ForgeFactory forgeFactory;
    ForgeVault forgeVault;
    YieldVaultFactory yvFactory;
    StrategyRouter router;

    YieldVault yvSenior;
    YieldVault yvMezz;
    YieldVault yvEquity;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address gov = makeAddr("governance");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

        // Predict vault address
        uint256 nonce = vm.getNonce(address(forgeFactory));
        address predicted = vm.computeCreateAddress(address(forgeFactory), nonce);

        TrancheToken sr = new TrancheToken("Senior", "SR", predicted, 0);
        TrancheToken mz = new TrancheToken("Mezzanine", "MZ", predicted, 1);
        TrancheToken eq = new TrancheToken("Equity", "EQ", predicted, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(sr)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mz)});
        params[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(eq)});

        address fv = forgeFactory.createVault(ForgeFactory.CreateVaultParams({
            underlyingAsset: address(usdc),
            trancheTokenAddresses: [address(sr), address(mz), address(eq)],
            trancheParams: params,
            distributionInterval: WEEK
        }));
        forgeVault = ForgeVault(fv);

        // Create YieldVaults
        yvFactory = new YieldVaultFactory(address(this));
        yvSenior = YieldVault(yvFactory.createYieldVault(fv, 0, "acSR", "acSR", DAY));
        yvMezz = YieldVault(yvFactory.createYieldVault(fv, 1, "acMZ", "acMZ", DAY));
        yvEquity = YieldVault(yvFactory.createYieldVault(fv, 2, "acEQ", "acEQ", DAY));

        // Strategy router
        router = new StrategyRouter(gov);

        // Fund users
        usdc.mint(alice, 10_000_000e18);
        usdc.mint(bob, 10_000_000e18);

        vm.prank(alice);
        usdc.approve(address(router), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(router), type(uint256).max);
    }

    // --- Strategy Creation ---

    function test_createStrategy_conservative() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(yvSenior);
        vaults[1] = address(yvMezz);
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 8_000;
        allocs[1] = 2_000;

        vm.prank(gov);
        uint256 id = router.createStrategy("Conservative", vaults, allocs);

        (string memory name, address[] memory v, uint256[] memory a, bool active) = router.getStrategy(id);
        assertEq(name, "Conservative");
        assertEq(v.length, 2);
        assertEq(v[0], address(yvSenior));
        assertEq(a[0], 8_000);
        assertTrue(active);
    }

    function test_createStrategy_revert_allocSumNot10000() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(yvSenior);
        vaults[1] = address(yvMezz);
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 5_000;
        allocs[1] = 3_000;

        vm.prank(gov);
        vm.expectRevert("StrategyRouter: must sum to 10000");
        router.createStrategy("Bad", vaults, allocs);
    }

    function test_createStrategy_revert_lengthMismatch() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(yvSenior);
        vaults[1] = address(yvMezz);
        uint256[] memory allocs = new uint256[](1);
        allocs[0] = 10_000;

        vm.prank(gov);
        vm.expectRevert("StrategyRouter: length mismatch");
        router.createStrategy("Bad", vaults, allocs);
    }

    function test_createStrategy_revert_notGovernance() public {
        address[] memory vaults = new address[](1);
        vaults[0] = address(yvSenior);
        uint256[] memory allocs = new uint256[](1);
        allocs[0] = 10_000;

        vm.prank(alice);
        vm.expectRevert("StrategyRouter: not governance");
        router.createStrategy("Bad", vaults, allocs);
    }

    function test_pauseStrategy() public {
        uint256 id = _createConservativeStrategy();

        vm.prank(gov);
        router.pauseStrategy(id);

        (,,, bool active) = router.getStrategy(id);
        assertFalse(active);
    }

    // --- Position ---

    function test_openPosition_basic() public {
        uint256 stratId = _createConservativeStrategy();

        vm.prank(alice);
        uint256 posId = router.openPosition(stratId, 100_000e18);

        (address user, uint256 sid, uint256 deposited) = router.getPositionInfo(posId);
        assertEq(user, alice);
        assertEq(sid, stratId);
        assertEq(deposited, 100_000e18);

        // Check position value
        uint256 val = router.getPositionValue(posId);
        assertApproxEqRel(val, 100_000e18, 1e15, "Position value ~ deposit");
    }

    function test_openPosition_allocationSplit() public {
        // 80% Senior + 20% Mezz
        uint256 stratId = _createConservativeStrategy();

        uint256 usdcBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        router.openPosition(stratId, 100_000e18);
        uint256 usdcAfter = usdc.balanceOf(alice);

        assertEq(usdcBefore - usdcAfter, 100_000e18, "Pulled 100k");
    }

    function test_openPosition_revert_pausedStrategy() public {
        uint256 stratId = _createConservativeStrategy();

        vm.prank(gov);
        router.pauseStrategy(stratId);

        vm.prank(alice);
        vm.expectRevert("StrategyRouter: strategy not active");
        router.openPosition(stratId, 100_000e18);
    }

    function test_openPosition_revert_zeroAmount() public {
        uint256 stratId = _createConservativeStrategy();

        vm.prank(alice);
        vm.expectRevert("StrategyRouter: zero amount");
        router.openPosition(stratId, 0);
    }

    // --- Close Position ---

    function test_closePosition_basic() public {
        uint256 stratId = _createConservativeStrategy();

        vm.prank(alice);
        uint256 posId = router.openPosition(stratId, 100_000e18);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 totalOut = router.closePosition(posId);
        uint256 received = usdc.balanceOf(alice) - balBefore;

        assertEq(received, totalOut);
        assertApproxEqRel(totalOut, 100_000e18, 1e15, "Got back ~deposit");
    }

    function test_closePosition_revert_notOwner() public {
        uint256 stratId = _createConservativeStrategy();

        vm.prank(alice);
        uint256 posId = router.openPosition(stratId, 100_000e18);

        vm.prank(bob);
        vm.expectRevert("StrategyRouter: not owner");
        router.closePosition(posId);
    }

    // --- Rebalance ---

    function test_rebalance_basic() public {
        uint256 conservativeId = _createConservativeStrategy();
        uint256 aggressiveId = _createAggressiveStrategy();

        vm.prank(alice);
        uint256 posId = router.openPosition(conservativeId, 100_000e18);

        uint256 valueBefore = router.getPositionValue(posId);

        vm.prank(alice);
        router.rebalance(posId, aggressiveId);

        (,uint256 newSid,) = router.getPositionInfo(posId);
        assertEq(newSid, aggressiveId, "Strategy switched");

        uint256 valueAfter = router.getPositionValue(posId);
        assertApproxEqRel(valueAfter, valueBefore, 1e15, "Value preserved");
    }

    function test_rebalance_revert_notOwner() public {
        uint256 conservativeId = _createConservativeStrategy();
        uint256 aggressiveId = _createAggressiveStrategy();

        vm.prank(alice);
        uint256 posId = router.openPosition(conservativeId, 100_000e18);

        vm.prank(bob);
        vm.expectRevert("StrategyRouter: not owner");
        router.rebalance(posId, aggressiveId);
    }

    function test_rebalance_revert_targetNotActive() public {
        uint256 conservativeId = _createConservativeStrategy();
        uint256 aggressiveId = _createAggressiveStrategy();

        vm.prank(alice);
        uint256 posId = router.openPosition(conservativeId, 100_000e18);

        vm.prank(gov);
        router.pauseStrategy(aggressiveId);

        vm.prank(alice);
        vm.expectRevert("StrategyRouter: target not active");
        router.rebalance(posId, aggressiveId);
    }

    // --- View ---

    function test_getUserPositions() public {
        uint256 stratId = _createConservativeStrategy();

        vm.startPrank(alice);
        router.openPosition(stratId, 50_000e18);
        router.openPosition(stratId, 30_000e18);
        vm.stopPrank();

        uint256[] memory positions = router.getUserPositions(alice);
        assertEq(positions.length, 2);
        assertEq(positions[0], 0);
        assertEq(positions[1], 1);
    }

    // --- Fuzz ---

    function testFuzz_openClose_noLoss(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        uint256 stratId = _createConservativeStrategy();

        vm.prank(alice);
        uint256 posId = router.openPosition(stratId, amount);

        vm.prank(alice);
        uint256 totalOut = router.closePosition(posId);

        // No loss beyond BPS rounding
        assertGe(totalOut + 1e15, amount, "No significant loss");
    }

    // --- Helpers ---

    function _createConservativeStrategy() internal returns (uint256) {
        address[] memory vaults = new address[](2);
        vaults[0] = address(yvSenior);
        vaults[1] = address(yvMezz);
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 8_000;
        allocs[1] = 2_000;

        vm.prank(gov);
        return router.createStrategy("Conservative", vaults, allocs);
    }

    function _createAggressiveStrategy() internal returns (uint256) {
        address[] memory vaults = new address[](2);
        vaults[0] = address(yvMezz);
        vaults[1] = address(yvEquity);
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 3_000;
        allocs[1] = 7_000;

        vm.prank(gov);
        return router.createStrategy("Aggressive", vaults, allocs);
    }
}
