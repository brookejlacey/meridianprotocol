// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Core contracts
import {SecondaryMarketRouter} from "../src/SecondaryMarketRouter.sol";
import {ISecondaryMarketRouter} from "../src/interfaces/ISecondaryMarketRouter.sol";
import {ForgeVault} from "../src/forge/ForgeVault.sol";
import {ForgeFactory} from "../src/forge/ForgeFactory.sol";
import {TrancheToken} from "../src/forge/TrancheToken.sol";
import {CDSContract} from "../src/shield/CDSContract.sol";
import {ShieldFactory} from "../src/shield/ShieldFactory.sol";
import {ShieldPricer} from "../src/shield/ShieldPricer.sol";
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {IForgeVault} from "../src/interfaces/IForgeVault.sol";
import {ICDSContract} from "../src/interfaces/ICDSContract.sol";

// Mocks
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";
import {MockDEXRouter} from "../src/mocks/MockDEXRouter.sol";

// Libraries
import {MeridianMath} from "../src/libraries/MeridianMath.sol";

contract SecondaryMarketRouterTest is Test {
    // Actors
    address user = makeAddr("user");
    address originator = makeAddr("originator");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address cdsSeller = makeAddr("cdsSeller");

    // Forge layer
    ForgeFactory forgeFactory;
    ForgeVault vault;
    MockYieldSource underlying;
    TrancheToken seniorToken;
    TrancheToken mezzToken;
    TrancheToken equityToken;

    // Shield layer
    ShieldFactory shieldFactory;
    CreditEventOracle oracle;
    CDSContract cds;

    // DEX
    MockDEXRouter dex;

    // Router
    SecondaryMarketRouter router;

    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;
    uint256 constant INVEST = 100_000e18;

    function setUp() public {
        // --- Deploy Forge layer ---
        underlying = new MockYieldSource("Mock USDC", "mUSDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

        uint256 factoryNonce = vm.getNonce(address(forgeFactory));
        address predictedVault = vm.computeCreateAddress(address(forgeFactory), factoryNonce);

        seniorToken = new TrancheToken("Senior", "SR", predictedVault, 0);
        mezzToken = new TrancheToken("Mezz", "MZ", predictedVault, 1);
        equityToken = new TrancheToken("Equity", "EQ", predictedVault, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(seniorToken)});
        params[1] = IForgeVault.TrancheParams({targetApr: 800, allocationPct: 20, token: address(mezzToken)});
        params[2] = IForgeVault.TrancheParams({targetApr: 0, allocationPct: 10, token: address(equityToken)});

        vm.prank(originator);
        address vaultAddr = forgeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(underlying),
                trancheTokenAddresses: [address(seniorToken), address(mezzToken), address(equityToken)],
                trancheParams: params,
                distributionInterval: WEEK
            })
        );
        vault = ForgeVault(vaultAddr);

        // --- Deploy Shield layer (for swapAndHedge tests) ---
        oracle = new CreditEventOracle();
        shieldFactory = new ShieldFactory();

        address cdsAddr = shieldFactory.createCDS(ShieldFactory.CreateCDSParams({
            referenceAsset: address(vault),
            protectionAmount: INVEST,
            premiumRate: 200, // 2%
            maturity: block.timestamp + YEAR,
            collateralToken: address(underlying),
            oracle: address(oracle),
            paymentInterval: 30 days
        }));
        cds = CDSContract(cdsAddr);

        // Seller provides protection
        underlying.mint(cdsSeller, INVEST);
        vm.prank(cdsSeller);
        underlying.approve(address(cds), type(uint256).max);
        vm.prank(cdsSeller);
        cds.sellProtection(INVEST);

        // --- Deploy DEX ---
        dex = new MockDEXRouter(30); // 0.3% fee

        // Set rates: 1:1 for tranche tokens <-> underlying (simplified for testing)
        dex.setRate(address(seniorToken), address(underlying), 1e18);
        dex.setRate(address(underlying), address(seniorToken), 1e18);
        dex.setRate(address(mezzToken), address(underlying), 1e18);
        dex.setRate(address(seniorToken), address(mezzToken), 1e18);

        // Fund DEX with tokens for payouts
        underlying.mint(address(dex), 10_000_000e18);

        // --- Deploy Router ---
        router = new SecondaryMarketRouter(address(dex), address(this));

        // --- Fund user ---
        underlying.mint(user, 1_000_000e18);

        // User invests in senior tranche to get tranche tokens
        vm.prank(user);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(user);
        vault.invest(0, INVEST); // 100k senior tokens

        // User approves router
        vm.prank(user);
        seniorToken.approve(address(router), type(uint256).max);
        vm.prank(user);
        mezzToken.approve(address(router), type(uint256).max);
        vm.prank(user);
        underlying.approve(address(router), type(uint256).max);
    }

    // --- Constructor ---

    function test_constructor_revert_zeroDex() public {
        vm.expectRevert("SecondaryMarketRouter: zero dex");
        new SecondaryMarketRouter(address(0), address(this));
    }

    // --- Simple Swap ---

    function test_swap_trancheToUnderlying() public {
        uint256 swapAmount = 10_000e18;

        uint256 userSeniorBefore = seniorToken.balanceOf(user);
        uint256 userUsdcBefore = underlying.balanceOf(user);

        vm.prank(user);
        uint256 amountOut = router.swap(ISecondaryMarketRouter.SwapParams({
            tokenIn: address(seniorToken),
            tokenOut: address(underlying),
            amountIn: swapAmount,
            minAmountOut: 9_900e18 // 1% slippage tolerance
        }));

        // Should receive ~9970 (10000 * 1.0 * (1 - 0.003))
        assertEq(seniorToken.balanceOf(user), userSeniorBefore - swapAmount);
        assertEq(underlying.balanceOf(user), userUsdcBefore + amountOut);
        assertGt(amountOut, 9_900e18);
    }

    function test_swap_underlyingToTranche() public {
        // Fund DEX with senior tokens for payout
        vm.prank(user);
        seniorToken.transfer(address(dex), 50_000e18);

        uint256 swapAmount = 10_000e18;

        vm.prank(user);
        uint256 amountOut = router.swap(ISecondaryMarketRouter.SwapParams({
            tokenIn: address(underlying),
            tokenOut: address(seniorToken),
            amountIn: swapAmount,
            minAmountOut: 9_900e18
        }));

        assertGt(amountOut, 9_900e18);
    }

    function test_swap_emitsEvent() public {
        uint256 swapAmount = 10_000e18;
        uint256 expectedOut = dex.quoteSwap(address(seniorToken), address(underlying), swapAmount);

        vm.expectEmit(true, true, true, true);
        emit ISecondaryMarketRouter.SwapExecuted(user, address(seniorToken), address(underlying), swapAmount, expectedOut);

        vm.prank(user);
        router.swap(ISecondaryMarketRouter.SwapParams({
            tokenIn: address(seniorToken),
            tokenOut: address(underlying),
            amountIn: swapAmount,
            minAmountOut: 0
        }));
    }

    function test_swap_revert_zeroAmount() public {
        vm.prank(user);
        vm.expectRevert("SecondaryMarketRouter: zero amount");
        router.swap(ISecondaryMarketRouter.SwapParams({
            tokenIn: address(seniorToken),
            tokenOut: address(underlying),
            amountIn: 0,
            minAmountOut: 0
        }));
    }

    function test_swap_revert_slippage() public {
        vm.prank(user);
        vm.expectRevert("SecondaryMarketRouter: swap failed");
        router.swap(ISecondaryMarketRouter.SwapParams({
            tokenIn: address(seniorToken),
            tokenOut: address(underlying),
            amountIn: 10_000e18,
            minAmountOut: 10_001e18 // More than input, impossible
        }));
    }

    // --- Swap and Reinvest ---

    function test_swapAndReinvest_happyPath() public {
        uint256 swapAmount = 10_000e18;
        uint256 mezzBefore = mezzToken.balanceOf(user);

        vm.prank(user);
        uint256 invested = router.swapAndReinvest(ISecondaryMarketRouter.SwapAndReinvestParams({
            tokenIn: address(seniorToken),
            amountIn: swapAmount,
            minUnderlying: 9_900e18,
            vault: address(vault),
            trancheId: 1 // Reinvest into mezzanine
        }));

        // User should have new mezz tokens
        assertGt(mezzToken.balanceOf(user), mezzBefore);
        assertGt(invested, 9_900e18);
    }

    function test_swapAndReinvest_userGetsTranchTokens_notRouter() public {
        uint256 swapAmount = 5_000e18;

        vm.prank(user);
        router.swapAndReinvest(ISecondaryMarketRouter.SwapAndReinvestParams({
            tokenIn: address(seniorToken),
            amountIn: swapAmount,
            minUnderlying: 0,
            vault: address(vault),
            trancheId: 1
        }));

        // Router should have zero balance of everything
        assertEq(seniorToken.balanceOf(address(router)), 0);
        assertEq(mezzToken.balanceOf(address(router)), 0);
        assertEq(underlying.balanceOf(address(router)), 0);
    }

    function test_swapAndReinvest_revert_zeroVault() public {
        vm.prank(user);
        vm.expectRevert("SecondaryMarketRouter: zero vault");
        router.swapAndReinvest(ISecondaryMarketRouter.SwapAndReinvestParams({
            tokenIn: address(seniorToken),
            amountIn: 10_000e18,
            minUnderlying: 0,
            vault: address(0),
            trancheId: 0
        }));
    }

    function test_swapAndReinvest_emitsEvent() public {
        uint256 swapAmount = 10_000e18;
        uint256 expectedUnderlying = dex.quoteSwap(address(seniorToken), address(underlying), swapAmount);

        vm.expectEmit(true, false, false, true);
        emit ISecondaryMarketRouter.SwapAndReinvested(
            user, address(seniorToken), address(vault), 1, swapAmount, expectedUnderlying
        );

        vm.prank(user);
        router.swapAndReinvest(ISecondaryMarketRouter.SwapAndReinvestParams({
            tokenIn: address(seniorToken),
            amountIn: swapAmount,
            minUnderlying: 0,
            vault: address(vault),
            trancheId: 1
        }));
    }

    // --- Swap and Hedge ---

    function test_swapAndHedge_happyPath() public {
        uint256 swapAmount = 50_000e18;

        vm.prank(user);
        uint256 invested = router.swapAndHedge(ISecondaryMarketRouter.SwapAndHedgeParams({
            tokenIn: address(seniorToken),
            amountIn: swapAmount,
            minUnderlying: 0,
            vault: address(vault),
            trancheId: 1,
            cds: address(cds),
            maxPremium: 5_000e18
        }));

        // User should have mezz tokens
        assertGt(mezzToken.balanceOf(user), 0);
        // User should be CDS buyer
        assertEq(cds.buyer(), user);
        // Router should be empty
        assertEq(underlying.balanceOf(address(router)), 0);
    }

    function test_swapAndHedge_revert_insufficientForHedge() public {
        // Swap only 1000 tokens but want 5000 for premium → not enough after swap
        vm.prank(user);
        vm.expectRevert("SecondaryMarketRouter: insufficient for hedge");
        router.swapAndHedge(ISecondaryMarketRouter.SwapAndHedgeParams({
            tokenIn: address(seniorToken),
            amountIn: 1_000e18,
            minUnderlying: 0,
            vault: address(vault),
            trancheId: 1,
            cds: address(cds),
            maxPremium: 5_000e18
        }));
    }

    function test_swapAndHedge_revert_zeroCds() public {
        vm.prank(user);
        vm.expectRevert("SecondaryMarketRouter: zero cds");
        router.swapAndHedge(ISecondaryMarketRouter.SwapAndHedgeParams({
            tokenIn: address(seniorToken),
            amountIn: 50_000e18,
            minUnderlying: 0,
            vault: address(vault),
            trancheId: 1,
            cds: address(0),
            maxPremium: 5_000e18
        }));
    }

    // --- Quote ---

    function test_quoteSwap_accuracy() public view {
        uint256 quote = router.quoteSwap(address(seniorToken), address(underlying), 10_000e18);
        uint256 dexQuote = dex.quoteSwap(address(seniorToken), address(underlying), 10_000e18);
        assertEq(quote, dexQuote);
    }

    function test_quoteSwap_noRate() public view {
        // No rate set for equity → underlying
        uint256 quote = router.quoteSwap(address(equityToken), address(underlying), 10_000e18);
        assertEq(quote, 0);
    }

    // --- Fuzz ---

    function testFuzz_swap_noTokensLeftInRouter(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e18, 50_000e18);

        vm.prank(user);
        router.swap(ISecondaryMarketRouter.SwapParams({
            tokenIn: address(seniorToken),
            tokenOut: address(underlying),
            amountIn: amountIn,
            minAmountOut: 0
        }));

        assertEq(seniorToken.balanceOf(address(router)), 0);
        assertEq(underlying.balanceOf(address(router)), 0);
    }

    // --- Integration ---

    function test_integration_swapAndReinvest_thenClaimYield() public {
        // Swap senior → reinvest in mezzanine
        vm.prank(user);
        router.swapAndReinvest(ISecondaryMarketRouter.SwapAndReinvestParams({
            tokenIn: address(seniorToken),
            amountIn: 10_000e18,
            minUnderlying: 0,
            vault: address(vault),
            trancheId: 1
        }));

        uint256 mezzBalance = mezzToken.balanceOf(user);
        assertGt(mezzBalance, 0);

        // Generate yield and trigger waterfall
        underlying.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + WEEK + 1);
        vm.prank(originator);
        vault.triggerWaterfall();

        // Claim yield on mezzanine position
        uint256 claimable = vault.getClaimableYield(user, 1);
        assertGt(claimable, 0);
    }
}
