// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract DynamicTrancheRatiosTest is Test {
    // --- Actors ---
    address originator = makeAddr("originator");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address attacker = makeAddr("attacker");

    // --- Contracts ---
    ForgeFactory factory;
    ForgeVault vault;
    MockYieldSource underlying;
    TrancheToken seniorToken;
    TrancheToken mezzToken;
    TrancheToken equityToken;

    uint256 constant WEEK = 7 days;

    function setUp() public {
        underlying = new MockYieldSource("Mock USDC", "mUSDC", 18);
        factory = new ForgeFactory(treasury, protocolAdmin, 0);

        uint256 factoryNonce = vm.getNonce(address(factory));
        address predictedVault = vm.computeCreateAddress(address(factory), factoryNonce);

        seniorToken = new TrancheToken("Senior Tranche", "SR-T", predictedVault, 0);
        mezzToken = new TrancheToken("Mezzanine Tranche", "MZ-T", predictedVault, 1);
        equityToken = new TrancheToken("Equity Tranche", "EQ-T", predictedVault, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(seniorToken)});
        params[1] = IForgeVault.TrancheParams({targetApr: 800, allocationPct: 20, token: address(mezzToken)});
        params[2] = IForgeVault.TrancheParams({targetApr: 0, allocationPct: 10, token: address(equityToken)});

        vm.prank(originator);
        address vaultAddr = factory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(underlying),
                trancheTokenAddresses: [address(seniorToken), address(mezzToken), address(equityToken)],
                trancheParams: params,
                distributionInterval: WEEK
            })
        );

        vault = ForgeVault(vaultAddr);

        // Fund investors
        underlying.mint(alice, 700_000e18);
        underlying.mint(bob, 200_000e18);
        underlying.mint(carol, 100_000e18);

        vm.prank(alice);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(carol);
        underlying.approve(address(vault), type(uint256).max);
    }

    // --- Happy Path ---

    function test_adjustTrancheRatios_happyPath() public {
        uint256[3] memory newPcts = [uint256(60), uint256(25), uint256(15)];
        vm.prank(originator);
        vault.adjustTrancheRatios(newPcts);

        (,uint256 seniorPct,) = vault.trancheParamsArray(0);
        (,uint256 mezzPct,) = vault.trancheParamsArray(1);
        (,uint256 equityPct,) = vault.trancheParamsArray(2);

        assertEq(seniorPct, 60);
        assertEq(mezzPct, 25);
        assertEq(equityPct, 15);
    }

    function test_adjustTrancheRatios_emitsEvent() public {
        uint256[3] memory newPcts = [uint256(60), uint256(25), uint256(15)];
        vm.expectEmit(false, false, false, true);
        emit IForgeVault.TrancheRatiosAdjusted([uint256(70), uint256(20), uint256(10)], newPcts);
        vm.prank(originator);
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_updatesAllParams() public {
        uint256[3] memory newPcts = [uint256(85), uint256(10), uint256(5)];
        vm.prank(originator);
        vault.adjustTrancheRatios(newPcts);

        (,uint256 seniorPct,) = vault.trancheParamsArray(0);
        (,uint256 mezzPct,) = vault.trancheParamsArray(1);
        (,uint256 equityPct,) = vault.trancheParamsArray(2);

        assertEq(seniorPct, 85);
        assertEq(mezzPct, 10);
        assertEq(equityPct, 5);
    }

    function test_adjustTrancheRatios_existingDepositsUnaffected() public {
        // Invest with original ratios
        vm.prank(alice);
        vault.invest(0, 700_000e18);
        vm.prank(bob);
        vault.invest(1, 200_000e18);
        vm.prank(carol);
        vault.invest(2, 100_000e18);

        uint256 aliceSharesBefore = seniorToken.balanceOf(alice);
        uint256 bobSharesBefore = mezzToken.balanceOf(bob);
        uint256 carolSharesBefore = equityToken.balanceOf(carol);

        // Adjust ratios
        uint256[3] memory newPcts = [uint256(60), uint256(25), uint256(15)];
        vm.prank(originator);
        vault.adjustTrancheRatios(newPcts);

        // Existing balances unchanged
        assertEq(seniorToken.balanceOf(alice), aliceSharesBefore);
        assertEq(mezzToken.balanceOf(bob), bobSharesBefore);
        assertEq(equityToken.balanceOf(carol), carolSharesBefore);

        // Can still claim yield after ratio change
        uint256 claimable = vault.getClaimableYield(alice, 0);
        assertEq(claimable, 0); // No yield distributed yet, but no revert
    }

    function test_adjustTrancheRatios_multipleAdjustments() public {
        uint256[3] memory pcts1 = [uint256(60), uint256(25), uint256(15)];
        vm.prank(originator);
        vault.adjustTrancheRatios(pcts1);

        uint256[3] memory pcts2 = [uint256(75), uint256(15), uint256(10)];
        vm.prank(originator);
        vault.adjustTrancheRatios(pcts2);

        (,uint256 seniorPct,) = vault.trancheParamsArray(0);
        (,uint256 mezzPct,) = vault.trancheParamsArray(1);
        (,uint256 equityPct,) = vault.trancheParamsArray(2);

        assertEq(seniorPct, 75);
        assertEq(mezzPct, 15);
        assertEq(equityPct, 10);
    }

    // --- Revert Cases ---

    function test_adjustTrancheRatios_revert_notOriginator() public {
        uint256[3] memory newPcts = [uint256(60), uint256(25), uint256(15)];
        vm.prank(attacker);
        vm.expectRevert("ForgeVault: not originator");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_notActive() public {
        vm.prank(originator);
        vault.setPoolStatus(IForgeVault.PoolStatus.Matured);

        uint256[3] memory newPcts = [uint256(60), uint256(25), uint256(15)];
        vm.prank(originator);
        vm.expectRevert("ForgeVault: pool not active");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_sumNot100() public {
        uint256[3] memory newPcts = [uint256(60), uint256(25), uint256(20)]; // sum = 105
        vm.prank(originator);
        vm.expectRevert("ForgeVault: must sum to 100");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_seniorTooLow() public {
        uint256[3] memory newPcts = [uint256(49), uint256(35), uint256(16)]; // senior < 50
        vm.prank(originator);
        vm.expectRevert("ForgeVault: senior out of bounds");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_seniorTooHigh() public {
        uint256[3] memory newPcts = [uint256(86), uint256(10), uint256(4)]; // would fail sum OR bounds
        vm.prank(originator);
        // senior 86 > MAX_SENIOR_PCT (85)
        vm.expectRevert("ForgeVault: senior out of bounds");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_mezzTooLow() public {
        uint256[3] memory newPcts = [uint256(82), uint256(9), uint256(9)]; // mezz < 10
        vm.prank(originator);
        vm.expectRevert("ForgeVault: mezz out of bounds");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_mezzTooHigh() public {
        uint256[3] memory newPcts = [uint256(50), uint256(36), uint256(14)]; // mezz > 35
        vm.prank(originator);
        vm.expectRevert("ForgeVault: mezz out of bounds");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_equityTooLow() public {
        uint256[3] memory newPcts = [uint256(60), uint256(36), uint256(4)]; // equity < 5
        // This will fail on mezz bounds first (36 > 35)
        vm.prank(originator);
        vm.expectRevert("ForgeVault: mezz out of bounds");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_equityTooLow_valid_mezz() public {
        uint256[3] memory newPcts = [uint256(62), uint256(34), uint256(4)]; // equity < 5
        vm.prank(originator);
        vm.expectRevert("ForgeVault: equity out of bounds");
        vault.adjustTrancheRatios(newPcts);
    }

    function test_adjustTrancheRatios_revert_equityTooHigh() public {
        uint256[3] memory newPcts = [uint256(55), uint256(24), uint256(21)]; // equity > 20
        vm.prank(originator);
        vm.expectRevert("ForgeVault: equity out of bounds");
        vault.adjustTrancheRatios(newPcts);
    }

    // --- Boundary Values ---

    function test_adjustTrancheRatios_minSenior_maxMezz_maxEquity() public {
        // 50 + 30 + 20 = 100
        uint256[3] memory newPcts = [uint256(50), uint256(30), uint256(20)];
        vm.prank(originator);
        vault.adjustTrancheRatios(newPcts);

        (,uint256 seniorPct,) = vault.trancheParamsArray(0);
        assertEq(seniorPct, 50);
    }

    function test_adjustTrancheRatios_maxSenior_minMezz_minEquity() public {
        // 85 + 10 + 5 = 100
        uint256[3] memory newPcts = [uint256(85), uint256(10), uint256(5)];
        vm.prank(originator);
        vault.adjustTrancheRatios(newPcts);

        (,uint256 seniorPct,) = vault.trancheParamsArray(0);
        assertEq(seniorPct, 85);
    }

    // --- Fuzz ---

    function testFuzz_adjustTrancheRatios_validCombinations(
        uint256 senior,
        uint256 mezz,
        uint256 equity
    ) public {
        senior = bound(senior, 50, 85);
        mezz = bound(mezz, 10, 35);
        equity = bound(equity, 5, 20);

        // Skip if doesn't sum to 100
        if (senior + mezz + equity != 100) return;

        uint256[3] memory newPcts = [senior, mezz, equity];
        vm.prank(originator);
        vault.adjustTrancheRatios(newPcts);

        (,uint256 sPct,) = vault.trancheParamsArray(0);
        (,uint256 mPct,) = vault.trancheParamsArray(1);
        (,uint256 ePct,) = vault.trancheParamsArray(2);

        assertEq(sPct, senior);
        assertEq(mPct, mezz);
        assertEq(ePct, equity);
    }
}
