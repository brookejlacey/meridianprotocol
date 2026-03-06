// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";
import {ProtocolTreasury} from "../../src/ProtocolTreasury.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

contract ForgeVaultProtocolFeeTest is Test {
    ForgeFactory factory;
    ForgeVault vault;
    MockYieldSource usdc;
    ProtocolTreasury treasury;

    address originator = makeAddr("originator");
    address protocolAdmin = makeAddr("protocolAdmin");
    address alice = makeAddr("alice");

    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;
    uint256 constant FEE_BPS = 50; // 0.5%

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        treasury = new ProtocolTreasury(address(this));
        factory = new ForgeFactory(address(treasury), protocolAdmin, FEE_BPS);

        // Create vault with 0.5% fee
        vm.startPrank(originator);

        address predictedVault = vm.computeCreateAddress(
            address(factory),
            vm.getNonce(address(factory))
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

        // Fund alice and invest
        usdc.mint(alice, 1_000_000e18);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.invest(0, 700_000e18);
        vault.invest(1, 200_000e18);
        vault.invest(2, 100_000e18);
        vm.stopPrank();
    }

    function test_feeExtraction_onWaterfall() public {
        // Add yield
        usdc.mint(address(vault), 10_000e18);

        // Advance time
        vm.warp(block.timestamp + WEEK);

        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        vault.triggerWaterfall();
        uint256 treasuryAfter = usdc.balanceOf(address(treasury));

        // Fee = 0.5% of 10,000 = 50
        uint256 expectedFee = MeridianMath.bpsMul(10_000e18, FEE_BPS);
        assertEq(treasuryAfter - treasuryBefore, expectedFee);
        assertEq(vault.totalProtocolFeesCollected(), expectedFee);
    }

    function test_feeExtraction_netYieldToTranches() public {
        usdc.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + WEEK);

        uint256 totalBefore = vault.totalYieldDistributed();
        vault.triggerWaterfall();
        uint256 totalAfter = vault.totalYieldDistributed();

        // Net yield distributed should be yield minus fee
        uint256 expectedFee = MeridianMath.bpsMul(10_000e18, FEE_BPS);
        uint256 netYield = 10_000e18 - expectedFee;
        // totalYieldDistributed may be <= netYield (due to waterfall math)
        assertLe(totalAfter - totalBefore, netYield);
    }

    function test_feeZero_noTreasuryTransfer() public {
        // Create a vault with 0% fee
        ForgeFactory zeroFeeFactory = new ForgeFactory(address(treasury), protocolAdmin, 0);

        vm.startPrank(originator);
        address predictedVault2 = vm.computeCreateAddress(
            address(zeroFeeFactory),
            vm.getNonce(address(zeroFeeFactory))
        );
        TrancheToken sr2 = new TrancheToken("S2", "S2", predictedVault2, 0);
        TrancheToken mz2 = new TrancheToken("M2", "M2", predictedVault2, 1);
        TrancheToken eq2 = new TrancheToken("E2", "E2", predictedVault2, 2);

        IForgeVault.TrancheParams[3] memory p;
        p[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(0)});
        p[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(0)});
        p[2] = IForgeVault.TrancheParams({targetApr: 2000, allocationPct: 10, token: address(0)});

        address v2Addr = zeroFeeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(usdc),
                trancheTokenAddresses: [address(sr2), address(mz2), address(eq2)],
                trancheParams: p,
                distributionInterval: WEEK
            })
        );
        vm.stopPrank();

        ForgeVault v2 = ForgeVault(v2Addr);

        usdc.mint(alice, 100_000e18);
        vm.startPrank(alice);
        usdc.approve(v2Addr, type(uint256).max);
        v2.invest(0, 100_000e18);
        vm.stopPrank();

        usdc.mint(v2Addr, 1_000e18);
        vm.warp(block.timestamp + WEEK);

        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        v2.triggerWaterfall();
        assertEq(usdc.balanceOf(address(treasury)), treasuryBefore);
        assertEq(v2.totalProtocolFeesCollected(), 0);
    }

    function test_feeAtMaxCap() public {
        // Create vault with max 10% fee
        ForgeFactory maxFeeFactory = new ForgeFactory(address(treasury), protocolAdmin, 1000);

        vm.startPrank(originator);
        address pv = vm.computeCreateAddress(
            address(maxFeeFactory),
            vm.getNonce(address(maxFeeFactory))
        );
        TrancheToken sr3 = new TrancheToken("S3", "S3", pv, 0);
        TrancheToken mz3 = new TrancheToken("M3", "M3", pv, 1);
        TrancheToken eq3 = new TrancheToken("E3", "E3", pv, 2);

        IForgeVault.TrancheParams[3] memory p;
        p[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(0)});
        p[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(0)});
        p[2] = IForgeVault.TrancheParams({targetApr: 2000, allocationPct: 10, token: address(0)});

        address v3Addr = maxFeeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(usdc),
                trancheTokenAddresses: [address(sr3), address(mz3), address(eq3)],
                trancheParams: p,
                distributionInterval: WEEK
            })
        );
        vm.stopPrank();

        ForgeVault v3 = ForgeVault(v3Addr);
        usdc.mint(alice, 100_000e18);
        vm.startPrank(alice);
        usdc.approve(v3Addr, type(uint256).max);
        v3.invest(0, 100_000e18);
        vm.stopPrank();

        usdc.mint(v3Addr, 10_000e18);
        vm.warp(block.timestamp + WEEK);

        v3.triggerWaterfall();
        // 10% of 10,000 = 1,000
        assertEq(v3.totalProtocolFeesCollected(), MeridianMath.bpsMul(10_000e18, 1000));
    }

    function test_setProtocolFee_byAdmin() public {
        assertEq(vault.protocolFeeBps(), FEE_BPS);

        vm.prank(protocolAdmin);
        vault.setProtocolFee(100);
        assertEq(vault.protocolFeeBps(), 100);
    }

    function test_setProtocolFee_emitsEvent() public {
        vm.prank(protocolAdmin);
        vm.expectEmit(false, false, false, true);
        emit IForgeVault.ProtocolFeeUpdated(FEE_BPS, 200);
        vault.setProtocolFee(200);
    }

    function test_setProtocolFee_revertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert("ForgeVault: not protocol admin");
        vault.setProtocolFee(100);
    }

    function test_setProtocolFee_revertAboveCap() public {
        vm.prank(protocolAdmin);
        vm.expectRevert("ForgeVault: fee exceeds max");
        vault.setProtocolFee(1001);
    }

    function test_feesAccumulate_multipleWaterfalls() public {
        // Waterfall 1
        usdc.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + WEEK);
        vault.triggerWaterfall();
        uint256 fee1 = vault.totalProtocolFeesCollected();

        // Waterfall 2
        usdc.mint(address(vault), 20_000e18);
        vm.warp(block.timestamp + WEEK);
        vault.triggerWaterfall();
        uint256 fee2 = vault.totalProtocolFeesCollected();

        assertGt(fee2, fee1);
        assertEq(fee2, MeridianMath.bpsMul(10_000e18, FEE_BPS) + MeridianMath.bpsMul(20_000e18, FEE_BPS));
    }

    function test_waterfallEmitsProtocolFeeEvent() public {
        usdc.mint(address(vault), 5_000e18);
        vm.warp(block.timestamp + WEEK);

        uint256 expectedFee = MeridianMath.bpsMul(5_000e18, FEE_BPS);
        vm.expectEmit(false, false, false, true);
        emit IForgeVault.ProtocolFeeCollected(expectedFee);
        vault.triggerWaterfall();
    }

    function test_immutables() public view {
        assertEq(vault.treasury(), address(treasury));
        assertEq(vault.protocolAdmin(), protocolAdmin);
    }

    function testFuzz_feeExtraction(uint256 yieldAmount, uint256 feeBps) public {
        feeBps = bound(feeBps, 1, 1000);
        yieldAmount = bound(yieldAmount, 1e18, 100_000e18);

        // Set fee
        vm.prank(protocolAdmin);
        vault.setProtocolFee(feeBps);

        usdc.mint(address(vault), yieldAmount);
        vm.warp(block.timestamp + WEEK);

        uint256 treasuryBefore = usdc.balanceOf(address(treasury));
        vault.triggerWaterfall();
        uint256 treasuryAfter = usdc.balanceOf(address(treasury));

        uint256 expectedFee = MeridianMath.bpsMul(yieldAmount, feeBps);
        assertEq(treasuryAfter - treasuryBefore, expectedFee);
    }
}
