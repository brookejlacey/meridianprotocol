// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FlashRebalancer} from "../src/FlashRebalancer.sol";
import {MockFlashLender} from "../src/mocks/MockFlashLender.sol";
import {ForgeFactory} from "../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../src/forge/ForgeVault.sol";
import {TrancheToken} from "../src/forge/TrancheToken.sol";
import {IForgeVault} from "../src/interfaces/IForgeVault.sol";
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";

contract FlashRebalancerTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant WEEK = 7 days;

    MockYieldSource usdc;
    MockFlashLender flashLender;
    FlashRebalancer rebalancer;
    ForgeFactory factory;
    ForgeVault vault;

    TrancheToken seniorToken;
    TrancheToken mezzToken;
    TrancheToken equityToken;

    address alice = makeAddr("alice");
    address originator = makeAddr("originator");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");

    uint256 constant SENIOR_SIZE = 700_000e18;
    uint256 constant MEZZ_SIZE = 200_000e18;
    uint256 constant EQUITY_SIZE = 100_000e18;

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        flashLender = new MockFlashLender();
        rebalancer = new FlashRebalancer(address(flashLender), address(this));
        factory = new ForgeFactory(treasury, protocolAdmin, 0);

        // Predict vault address for circular dependency
        uint256 factoryNonce = vm.getNonce(address(factory));
        address predictedVault = vm.computeCreateAddress(address(factory), factoryNonce);

        // Deploy tranche tokens with predicted vault address
        seniorToken = new TrancheToken("Senior Tranche", "SR-T", predictedVault, 0);
        mezzToken = new TrancheToken("Mezzanine Tranche", "MZ-T", predictedVault, 1);
        equityToken = new TrancheToken("Equity Tranche", "EQ-T", predictedVault, 2);

        // Build tranche params
        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({
            targetApr: 500,
            allocationPct: 70,
            token: address(seniorToken)
        });
        params[1] = IForgeVault.TrancheParams({
            targetApr: 1000,
            allocationPct: 20,
            token: address(mezzToken)
        });
        params[2] = IForgeVault.TrancheParams({
            targetApr: 1500,
            allocationPct: 10,
            token: address(equityToken)
        });

        // Create vault via factory
        vm.prank(originator);
        address vaultAddr = factory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(usdc),
                trancheTokenAddresses: [address(seniorToken), address(mezzToken), address(equityToken)],
                trancheParams: params,
                distributionInterval: WEEK
            })
        );
        vault = ForgeVault(vaultAddr);

        // Fund flash lender
        usdc.mint(address(flashLender), 10_000_000e18);

        // Fund alice and invest in Senior
        usdc.mint(alice, 10_000_000e18);
        vm.startPrank(alice);
        usdc.approve(vaultAddr, type(uint256).max);
        vault.invest(0, SENIOR_SIZE); // 700k in Senior
        vm.stopPrank();
    }

    function test_rebalance_seniorToEquity() public {
        uint256 moveAmount = 100_000e18;

        // Alice needs to approve rebalancer for her senior tranche tokens
        IForgeVault.TrancheParams memory seniorParams = vault.getTrancheParams(0);
        vm.startPrank(alice);
        IERC20(seniorParams.token).approve(address(rebalancer), moveAmount);
        vm.stopPrank();

        uint256 aliceSeniorBefore = vault.getShares(alice, 0);
        uint256 aliceEquityBefore = vault.getShares(alice, 2);

        vm.prank(alice);
        rebalancer.rebalance(address(vault), 0, 2, moveAmount);

        uint256 aliceSeniorAfter = vault.getShares(alice, 0);
        uint256 aliceEquityAfter = vault.getShares(alice, 2);

        assertEq(aliceSeniorAfter, aliceSeniorBefore - moveAmount, "Senior decreased");
        assertEq(aliceEquityAfter, aliceEquityBefore + moveAmount, "Equity increased");
    }

    function test_rebalance_seniorToMezz() public {
        uint256 moveAmount = 50_000e18;

        IForgeVault.TrancheParams memory seniorParams = vault.getTrancheParams(0);
        vm.prank(alice);
        IERC20(seniorParams.token).approve(address(rebalancer), moveAmount);

        vm.prank(alice);
        rebalancer.rebalance(address(vault), 0, 1, moveAmount);

        assertEq(vault.getShares(alice, 0), SENIOR_SIZE - moveAmount);
        assertEq(vault.getShares(alice, 1), moveAmount);
    }

    function test_rebalance_revert_sameTranche() public {
        vm.prank(alice);
        vm.expectRevert("FlashRebalancer: same tranche");
        rebalancer.rebalance(address(vault), 0, 0, 100e18);
    }

    function test_rebalance_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("FlashRebalancer: zero amount");
        rebalancer.rebalance(address(vault), 0, 2, 0);
    }

    function test_rebalance_revert_invalidTranche() public {
        vm.prank(alice);
        vm.expectRevert("FlashRebalancer: invalid tranche");
        rebalancer.rebalance(address(vault), 0, 5, 100e18);
    }

    function test_rebalance_revert_insufficientTokens() public {
        // Alice only has 700k Senior, try to move 1M
        IForgeVault.TrancheParams memory seniorParams = vault.getTrancheParams(0);
        vm.prank(alice);
        IERC20(seniorParams.token).approve(address(rebalancer), 1_000_000e18);

        vm.prank(alice);
        vm.expectRevert(); // ERC20 insufficient balance
        rebalancer.rebalance(address(vault), 0, 2, 1_000_000e18);
    }

    function test_flashLender_standalone() public {
        // Test the mock flash lender directly
        usdc.mint(address(flashLender), 1_000_000e18);
        uint256 balance = usdc.balanceOf(address(flashLender));
        assertGt(balance, 0, "Flash lender has balance");
    }

    /// @dev Fuzz: rebalance any valid amount
    function testFuzz_rebalance_validAmount(uint256 amount) public {
        amount = bound(amount, 1e18, SENIOR_SIZE);

        IForgeVault.TrancheParams memory seniorParams = vault.getTrancheParams(0);
        vm.prank(alice);
        IERC20(seniorParams.token).approve(address(rebalancer), amount);

        vm.prank(alice);
        rebalancer.rebalance(address(vault), 0, 2, amount);

        assertEq(vault.getShares(alice, 0), SENIOR_SIZE - amount);
        assertEq(vault.getShares(alice, 2), amount);
    }
}
