// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";
import {ProtocolTreasury} from "../../src/ProtocolTreasury.sol";

contract ForgeVaultPausableTest is Test {
    ForgeFactory factory;
    ForgeVault vault;
    MockYieldSource usdc;
    ProtocolTreasury treasury;

    address originator = makeAddr("originator");
    address protocolAdmin = makeAddr("protocolAdmin");
    address alice = makeAddr("alice");

    uint256 constant WEEK = 7 days;

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        treasury = new ProtocolTreasury(address(this));
        factory = new ForgeFactory(address(treasury), protocolAdmin, 0);

        vm.startPrank(originator);
        address predictedVault = vm.computeCreateAddress(
            address(factory), vm.getNonce(address(factory))
        );

        TrancheToken senior = new TrancheToken("Senior", "SR", predictedVault, 0);
        TrancheToken mezz = new TrancheToken("Mezz", "MZ", predictedVault, 1);
        TrancheToken equity = new TrancheToken("Equity", "EQ", predictedVault, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(0)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(0)});
        params[2] = IForgeVault.TrancheParams({targetApr: 2000, allocationPct: 10, token: address(0)});

        address vaultAddr = factory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(usdc),
                trancheTokenAddresses: [address(senior), address(mezz), address(equity)],
                trancheParams: params,
                distributionInterval: WEEK
            })
        );
        vault = ForgeVault(vaultAddr);
        vm.stopPrank();

        usdc.mint(alice, 1_000_000e18);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.invest(0, 500_000e18);
        vm.stopPrank();
    }

    function test_pause_onlyProtocolAdmin() public {
        vm.prank(protocolAdmin);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_pause_revertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert("ForgeVault: not protocol admin");
        vault.pause();
    }

    function test_whenPaused_investReverts() public {
        vm.prank(protocolAdmin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.invest(0, 1_000e18);
    }

    function test_whenPaused_investForReverts() public {
        vm.prank(protocolAdmin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.investFor(0, 1_000e18, alice);
    }

    function test_whenPaused_triggerWaterfallReverts() public {
        usdc.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + WEEK);

        vm.prank(protocolAdmin);
        vault.pause();

        vm.expectRevert();
        vault.triggerWaterfall();
    }

    function test_whenPaused_withdrawWorks() public {
        vm.prank(protocolAdmin);
        vault.pause();

        vm.prank(alice);
        vault.withdraw(0, 100_000e18);
    }

    function test_whenPaused_claimYieldWorks() public {
        // Generate yield first
        usdc.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + WEEK);
        vault.triggerWaterfall();

        vm.prank(protocolAdmin);
        vault.pause();

        vm.prank(alice);
        vault.claimYield(0);
    }

    function test_unpause_restoresInvest() public {
        vm.prank(protocolAdmin);
        vault.pause();

        vm.prank(protocolAdmin);
        vault.unpause();
        assertFalse(vault.paused());

        vm.prank(alice);
        vault.invest(0, 1_000e18);
    }
}
