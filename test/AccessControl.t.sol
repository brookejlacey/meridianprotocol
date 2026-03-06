// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";

// Core contracts
import {ForgeFactory} from "../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../src/forge/ForgeVault.sol";
import {TrancheToken} from "../src/forge/TrancheToken.sol";
import {IForgeVault} from "../src/interfaces/IForgeVault.sol";
import {CDSPool} from "../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../src/shield/CDSPoolFactory.sol";
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {ShieldPricer} from "../src/shield/ShieldPricer.sol";
import {NexusHub} from "../src/nexus/NexusHub.sol";
import {CollateralOracle} from "../src/nexus/CollateralOracle.sol";
import {MockTeleporter} from "../src/mocks/MockTeleporter.sol";

// Yield
import {YieldVault} from "../src/yield/YieldVault.sol";
import {YieldVaultFactory} from "../src/yield/YieldVaultFactory.sol";
import {StrategyRouter} from "../src/yield/StrategyRouter.sol";
import {LPIncentiveGauge} from "../src/yield/LPIncentiveGauge.sol";

// Routers
import {HedgeRouter} from "../src/HedgeRouter.sol";
import {PoolRouter} from "../src/PoolRouter.sol";
import {FlashRebalancer} from "../src/FlashRebalancer.sol";
import {SecondaryMarketRouter} from "../src/SecondaryMarketRouter.sol";
import {MockFlashLender} from "../src/mocks/MockFlashLender.sol";

// Treasury
import {ProtocolTreasury} from "../src/ProtocolTreasury.sol";

// Mocks
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";

// ============================================================
// Phase 1: Ownable2Step Tests (OZ contracts)
// ============================================================

contract CDSPoolFactoryOwnable2StepTest is Test {
    CDSPoolFactory factory;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        factory = new CDSPoolFactory(address(this), makeAddr("admin"), 0);
    }

    function test_transferOwnership_setsPending() public {
        factory.transferOwnership(alice);
        assertEq(factory.pendingOwner(), alice);
        assertEq(factory.owner(), address(this));
    }

    function test_transferOwnership_revertNotOwner() public {
        vm.prank(nobody);
        vm.expectRevert();
        factory.transferOwnership(alice);
    }

    function test_acceptOwnership_transfers() public {
        factory.transferOwnership(alice);
        vm.prank(alice);
        factory.acceptOwnership();
        assertEq(factory.owner(), alice);
        assertEq(factory.pendingOwner(), address(0));
    }

    function test_acceptOwnership_revertNotPending() public {
        factory.transferOwnership(alice);
        vm.prank(nobody);
        vm.expectRevert();
        factory.acceptOwnership();
    }

    function test_renounceOwnership() public {
        factory.renounceOwnership();
        assertEq(factory.owner(), address(0));
    }
}

contract NexusHubOwnable2StepTest is Test {
    NexusHub hub;
    CollateralOracle oracle;
    MockTeleporter teleporter;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        oracle = new CollateralOracle();
        teleporter = new MockTeleporter(bytes32(uint256(43113)));
        hub = new NexusHub(address(oracle), address(teleporter), 11e17, 500);
    }

    function test_transferOwnership_setsPending() public {
        hub.transferOwnership(alice);
        assertEq(hub.pendingOwner(), alice);
        assertEq(hub.owner(), address(this));
    }

    function test_transferOwnership_revertNotOwner() public {
        vm.prank(nobody);
        vm.expectRevert();
        hub.transferOwnership(alice);
    }

    function test_acceptOwnership_transfers() public {
        hub.transferOwnership(alice);
        vm.prank(alice);
        hub.acceptOwnership();
        assertEq(hub.owner(), alice);
    }

    function test_acceptOwnership_revertNotPending() public {
        hub.transferOwnership(alice);
        vm.prank(nobody);
        vm.expectRevert();
        hub.acceptOwnership();
    }

    function test_newOwner_canPause() public {
        hub.transferOwnership(alice);
        vm.prank(alice);
        hub.acceptOwnership();
        vm.prank(alice);
        hub.pause();
        assertTrue(hub.paused());
    }
}

contract ProtocolTreasuryOwnable2StepTest is Test {
    ProtocolTreasury treasury;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        treasury = new ProtocolTreasury(address(this));
    }

    function test_transferOwnership_setsPending() public {
        treasury.transferOwnership(alice);
        assertEq(treasury.pendingOwner(), alice);
    }

    function test_acceptOwnership_transfers() public {
        treasury.transferOwnership(alice);
        vm.prank(alice);
        treasury.acceptOwnership();
        assertEq(treasury.owner(), alice);
    }

    function test_acceptOwnership_revertNotPending() public {
        treasury.transferOwnership(alice);
        vm.prank(nobody);
        vm.expectRevert();
        treasury.acceptOwnership();
    }
}

// ============================================================
// Phase 2: Custom Admin Transfers
// ============================================================

contract ForgeFactoryOwnershipTest is Test {
    ForgeFactory factory;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        factory = new ForgeFactory(makeAddr("treasury"), makeAddr("admin"), 0);
    }

    function test_transferOwnership_setsPending() public {
        factory.transferOwnership(alice);
        assertEq(factory.pendingOwner(), alice);
        assertEq(factory.owner(), address(this));
    }

    function test_transferOwnership_revertNotOwner() public {
        vm.prank(nobody);
        vm.expectRevert("ForgeFactory: not owner");
        factory.transferOwnership(alice);
    }

    function test_transferOwnership_revertZeroAddress() public {
        vm.expectRevert("ForgeFactory: zero address");
        factory.transferOwnership(address(0));
    }

    function test_acceptOwnership_transfers() public {
        factory.transferOwnership(alice);
        vm.prank(alice);
        factory.acceptOwnership();
        assertEq(factory.owner(), alice);
        assertEq(factory.pendingOwner(), address(0));
    }

    function test_acceptOwnership_revertNotPending() public {
        factory.transferOwnership(alice);
        vm.prank(nobody);
        vm.expectRevert("ForgeFactory: not pending owner");
        factory.acceptOwnership();
    }
}

contract YieldVaultFactoryOwnershipTest is Test {
    YieldVaultFactory factory;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        factory = new YieldVaultFactory(makeAddr("pauseAdmin"));
    }

    function test_transferOwnership_setsPending() public {
        factory.transferOwnership(alice);
        assertEq(factory.pendingOwner(), alice);
        assertEq(factory.owner(), address(this));
    }

    function test_transferOwnership_revertNotOwner() public {
        vm.prank(nobody);
        vm.expectRevert("YieldVaultFactory: not owner");
        factory.transferOwnership(alice);
    }

    function test_transferOwnership_revertZeroAddress() public {
        vm.expectRevert("YieldVaultFactory: zero address");
        factory.transferOwnership(address(0));
    }

    function test_acceptOwnership_transfers() public {
        factory.transferOwnership(alice);
        vm.prank(alice);
        factory.acceptOwnership();
        assertEq(factory.owner(), alice);
    }

    function test_acceptOwnership_revertNotPending() public {
        factory.transferOwnership(alice);
        vm.prank(nobody);
        vm.expectRevert("YieldVaultFactory: not pending owner");
        factory.acceptOwnership();
    }
}

contract StrategyRouterGovernanceTest is Test {
    StrategyRouter router;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        router = new StrategyRouter(address(this));
    }

    function test_transferGovernance_setsPending() public {
        router.transferGovernance(alice);
        assertEq(router.pendingGovernance(), alice);
        assertEq(router.governance(), address(this));
    }

    function test_transferGovernance_revertNotGov() public {
        vm.prank(nobody);
        vm.expectRevert("StrategyRouter: not governance");
        router.transferGovernance(alice);
    }

    function test_transferGovernance_revertZeroAddress() public {
        vm.expectRevert("StrategyRouter: zero address");
        router.transferGovernance(address(0));
    }

    function test_acceptGovernance_transfers() public {
        router.transferGovernance(alice);
        vm.prank(alice);
        router.acceptGovernance();
        assertEq(router.governance(), alice);
        assertEq(router.pendingGovernance(), address(0));
    }

    function test_acceptGovernance_revertNotPending() public {
        router.transferGovernance(alice);
        vm.prank(nobody);
        vm.expectRevert("StrategyRouter: not pending governance");
        router.acceptGovernance();
    }
}

// ============================================================
// Phase 3: Upgraded Single-Step Transfers
// ============================================================

contract ShieldPricerOwnershipTest is Test {
    ShieldPricer pricer;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        pricer = new ShieldPricer(ShieldPricer.PricingParams({
            baseRateBps: 50,
            riskMultiplierBps: 2000,
            utilizationKinkBps: 8000,
            utilizationSurchargeBps: 500,
            tenorScalerBps: 100,
            maxSpreadBps: 5000
        }));
    }

    function test_transferOwnership_setsPending() public {
        pricer.transferOwnership(alice);
        assertEq(pricer.pendingOwner(), alice);
        assertEq(pricer.owner(), address(this));
    }

    function test_transferOwnership_revertNotOwner() public {
        vm.prank(nobody);
        vm.expectRevert("ShieldPricer: not owner");
        pricer.transferOwnership(alice);
    }

    function test_transferOwnership_revertZeroAddress() public {
        vm.expectRevert("ShieldPricer: zero address");
        pricer.transferOwnership(address(0));
    }

    function test_acceptOwnership_transfers() public {
        pricer.transferOwnership(alice);
        vm.prank(alice);
        pricer.acceptOwnership();
        assertEq(pricer.owner(), alice);
        assertEq(pricer.pendingOwner(), address(0));
    }

    function test_acceptOwnership_revertNotPending() public {
        pricer.transferOwnership(alice);
        vm.prank(nobody);
        vm.expectRevert("ShieldPricer: not pending owner");
        pricer.acceptOwnership();
    }
}

contract LPIncentiveGaugeGovernanceTest is Test {
    LPIncentiveGauge gauge;
    CDSPool pool;
    MockYieldSource usdc;
    MockYieldSource rewardToken;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        rewardToken = new MockYieldSource("RWD", "RWD", 18);
        CreditEventOracle oracle = new CreditEventOracle();
        CDSPoolFactory factory = new CDSPoolFactory(address(this), makeAddr("admin"), 0);

        address poolAddr = factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: makeAddr("ref"),
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + 365 days,
            baseSpreadWad: 0.03e18,
            slopeWad: 0.5e18
        }));
        pool = CDSPool(poolAddr);
        gauge = new LPIncentiveGauge(address(pool), address(rewardToken), address(this));
    }

    function test_transferGovernance_setsPending() public {
        gauge.transferGovernance(alice);
        assertEq(gauge.pendingGovernance(), alice);
        assertEq(gauge.governance(), address(this));
    }

    function test_transferGovernance_revertNotGov() public {
        vm.prank(nobody);
        vm.expectRevert("LPIncentiveGauge: not governance");
        gauge.transferGovernance(alice);
    }

    function test_transferGovernance_revertZeroAddress() public {
        vm.expectRevert("LPIncentiveGauge: zero address");
        gauge.transferGovernance(address(0));
    }

    function test_acceptGovernance_transfers() public {
        gauge.transferGovernance(alice);
        vm.prank(alice);
        gauge.acceptGovernance();
        assertEq(gauge.governance(), alice);
    }

    function test_acceptGovernance_revertNotPending() public {
        gauge.transferGovernance(alice);
        vm.prank(nobody);
        vm.expectRevert("LPIncentiveGauge: not pending governance");
        gauge.acceptGovernance();
    }
}

// ============================================================
// Phase 4: ForgeVault Access Control
// ============================================================

contract ForgeVaultAccessControlTest is Test {
    ForgeFactory factory;
    ForgeVault vault;
    MockYieldSource usdc;
    ProtocolTreasury treasury;

    address originator = makeAddr("originator");
    address protocolAdmin = makeAddr("protocolAdmin");
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        treasury = new ProtocolTreasury(address(this));
        factory = new ForgeFactory(address(treasury), protocolAdmin, 0);

        vm.startPrank(originator);
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));
        TrancheToken senior = new TrancheToken("Senior", "SR", predicted, 0);
        TrancheToken mezz = new TrancheToken("Mezz", "MZ", predicted, 1);
        TrancheToken equity = new TrancheToken("Equity", "EQ", predicted, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(0)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(0)});
        params[2] = IForgeVault.TrancheParams({targetApr: 2000, allocationPct: 10, token: address(0)});

        address vaultAddr = factory.createVault(ForgeFactory.CreateVaultParams({
            underlyingAsset: address(usdc),
            trancheTokenAddresses: [address(senior), address(mezz), address(equity)],
            trancheParams: params,
            distributionInterval: 7 days
        }));
        vault = ForgeVault(vaultAddr);
        vm.stopPrank();
    }

    // --- Originator Transfer ---

    function test_transferOriginator_setsPending() public {
        vm.prank(originator);
        vault.transferOriginator(alice);
        assertEq(vault.pendingOriginator(), alice);
        assertEq(vault.originator(), originator);
    }

    function test_transferOriginator_revertNotOriginator() public {
        vm.prank(nobody);
        vm.expectRevert("ForgeVault: not originator");
        vault.transferOriginator(alice);
    }

    function test_acceptOriginator_transfers() public {
        vm.prank(originator);
        vault.transferOriginator(alice);
        vm.prank(alice);
        vault.acceptOriginator();
        assertEq(vault.originator(), alice);
        assertEq(vault.pendingOriginator(), address(0));
    }

    function test_acceptOriginator_revertNotPending() public {
        vm.prank(originator);
        vault.transferOriginator(alice);
        vm.prank(nobody);
        vm.expectRevert("ForgeVault: not pending originator");
        vault.acceptOriginator();
    }

    // --- Protocol Admin Transfer ---

    function test_transferProtocolAdmin_setsPending() public {
        vm.prank(protocolAdmin);
        vault.transferProtocolAdmin(alice);
        assertEq(vault.pendingProtocolAdmin(), alice);
        assertEq(vault.protocolAdmin(), protocolAdmin);
    }

    function test_transferProtocolAdmin_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("ForgeVault: not protocol admin");
        vault.transferProtocolAdmin(alice);
    }

    function test_acceptProtocolAdmin_transfers() public {
        vm.prank(protocolAdmin);
        vault.transferProtocolAdmin(alice);
        vm.prank(alice);
        vault.acceptProtocolAdmin();
        assertEq(vault.protocolAdmin(), alice);
    }

    function test_acceptProtocolAdmin_revertNotPending() public {
        vm.prank(protocolAdmin);
        vault.transferProtocolAdmin(alice);
        vm.prank(nobody);
        vm.expectRevert("ForgeVault: not pending admin");
        vault.acceptProtocolAdmin();
    }

    // --- Treasury ---

    function test_setTreasury_works() public {
        vm.prank(protocolAdmin);
        vault.setTreasury(alice);
        assertEq(vault.treasury(), alice);
    }

    function test_setTreasury_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("ForgeVault: not protocol admin");
        vault.setTreasury(alice);
    }

    function test_setTreasury_revertZero() public {
        vm.prank(protocolAdmin);
        vm.expectRevert("ForgeVault: zero address");
        vault.setTreasury(address(0));
    }

    // --- Integration ---

    function test_newProtocolAdmin_canPause() public {
        vm.prank(protocolAdmin);
        vault.transferProtocolAdmin(alice);
        vm.prank(alice);
        vault.acceptProtocolAdmin();
        vm.prank(alice);
        vault.pause();
        assertTrue(vault.paused());
    }
}

// ============================================================
// Phase 4: CDSPool Access Control
// ============================================================

contract CDSPoolAccessControlTest is Test {
    CDSPool pool;
    CDSPoolFactory poolFactory;
    MockYieldSource usdc;
    CreditEventOracle oracle;

    address protocolAdmin = makeAddr("protocolAdmin");
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        oracle = new CreditEventOracle();
        poolFactory = new CDSPoolFactory(address(this), protocolAdmin, 0);

        address poolAddr = poolFactory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: makeAddr("vault"),
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + 365 days,
            baseSpreadWad: 0.03e18,
            slopeWad: 0.5e18
        }));
        pool = CDSPool(poolAddr);
    }

    function test_transferProtocolAdmin_setsPending() public {
        vm.prank(protocolAdmin);
        pool.transferProtocolAdmin(alice);
        assertEq(pool.pendingProtocolAdmin(), alice);
        assertEq(pool.protocolAdmin(), protocolAdmin);
    }

    function test_transferProtocolAdmin_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("CDSPool: not protocol admin");
        pool.transferProtocolAdmin(alice);
    }

    function test_acceptProtocolAdmin_transfers() public {
        vm.prank(protocolAdmin);
        pool.transferProtocolAdmin(alice);
        vm.prank(alice);
        pool.acceptProtocolAdmin();
        assertEq(pool.protocolAdmin(), alice);
    }

    function test_acceptProtocolAdmin_revertNotPending() public {
        vm.prank(protocolAdmin);
        pool.transferProtocolAdmin(alice);
        vm.prank(nobody);
        vm.expectRevert("CDSPool: not pending admin");
        pool.acceptProtocolAdmin();
    }

    function test_setTreasury_works() public {
        vm.prank(protocolAdmin);
        pool.setTreasury(alice);
        assertEq(pool.treasury(), alice);
    }

    function test_setTreasury_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("CDSPool: not protocol admin");
        pool.setTreasury(alice);
    }

    function test_setTreasury_revertZero() public {
        vm.prank(protocolAdmin);
        vm.expectRevert("CDSPool: zero address");
        pool.setTreasury(address(0));
    }

    function test_newAdmin_canSetFee() public {
        vm.prank(protocolAdmin);
        pool.transferProtocolAdmin(alice);
        vm.prank(alice);
        pool.acceptProtocolAdmin();
        vm.prank(alice);
        pool.setProtocolFee(100);
        assertEq(pool.protocolFeeBps(), 100);
    }
}

// ============================================================
// Phase 4: YieldVault Pause Admin Transfer
// ============================================================

contract YieldVaultPauseAdminTransferTest is Test {
    YieldVault yv;
    MockYieldSource usdc;
    ForgeFactory forgeFactory;
    YieldVaultFactory yvFactory;

    address pauseAdmin = makeAddr("pauseAdmin");
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        forgeFactory = new ForgeFactory(makeAddr("treasury"), makeAddr("admin"), 0);

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
            distributionInterval: 7 days
        }));

        yvFactory = new YieldVaultFactory(pauseAdmin);
        address yvAddr = yvFactory.createYieldVault(fv, 0, "Auto Senior", "acSR", 1 days);
        yv = YieldVault(yvAddr);
    }

    function test_transferPauseAdmin_setsPending() public {
        vm.prank(pauseAdmin);
        yv.transferPauseAdmin(alice);
        assertEq(yv.pendingPauseAdmin(), alice);
        assertEq(yv.pauseAdmin(), pauseAdmin);
    }

    function test_transferPauseAdmin_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("YieldVault: not pause admin");
        yv.transferPauseAdmin(alice);
    }

    function test_transferPauseAdmin_revertZeroAddress() public {
        vm.prank(pauseAdmin);
        vm.expectRevert("YieldVault: zero address");
        yv.transferPauseAdmin(address(0));
    }

    function test_acceptPauseAdmin_transfers() public {
        vm.prank(pauseAdmin);
        yv.transferPauseAdmin(alice);
        vm.prank(alice);
        yv.acceptPauseAdmin();
        assertEq(yv.pauseAdmin(), alice);
        assertEq(yv.pendingPauseAdmin(), address(0));
    }

    function test_acceptPauseAdmin_revertNotPending() public {
        vm.prank(pauseAdmin);
        yv.transferPauseAdmin(alice);
        vm.prank(nobody);
        vm.expectRevert("YieldVault: not pending admin");
        yv.acceptPauseAdmin();
    }
}

// ============================================================
// Phase 4: Router Pause Admin Transfers
// ============================================================

contract HedgeRouterPauseAdminTransferTest is Test {
    HedgeRouter router;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        router = new HedgeRouter(makeAddr("pricer"), makeAddr("factory"), address(this));
    }

    function test_transferPauseAdmin_setsPending() public {
        router.transferPauseAdmin(alice);
        assertEq(router.pendingPauseAdmin(), alice);
        assertEq(router.pauseAdmin(), address(this));
    }

    function test_transferPauseAdmin_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("HedgeRouter: not pause admin");
        router.transferPauseAdmin(alice);
    }

    function test_transferPauseAdmin_revertZeroAddress() public {
        vm.expectRevert("HedgeRouter: zero address");
        router.transferPauseAdmin(address(0));
    }

    function test_acceptPauseAdmin_transfers() public {
        router.transferPauseAdmin(alice);
        vm.prank(alice);
        router.acceptPauseAdmin();
        assertEq(router.pauseAdmin(), alice);
    }

    function test_acceptPauseAdmin_revertNotPending() public {
        router.transferPauseAdmin(alice);
        vm.prank(nobody);
        vm.expectRevert("HedgeRouter: not pending admin");
        router.acceptPauseAdmin();
    }
}

contract PoolRouterPauseAdminTransferTest is Test {
    PoolRouter router;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        CDSPoolFactory factory = new CDSPoolFactory(address(this), address(this), 0);
        router = new PoolRouter(address(factory), address(this));
    }

    function test_transferPauseAdmin_setsPending() public {
        router.transferPauseAdmin(alice);
        assertEq(router.pendingPauseAdmin(), alice);
    }

    function test_transferPauseAdmin_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("PoolRouter: not pause admin");
        router.transferPauseAdmin(alice);
    }

    function test_acceptPauseAdmin_transfers() public {
        router.transferPauseAdmin(alice);
        vm.prank(alice);
        router.acceptPauseAdmin();
        assertEq(router.pauseAdmin(), alice);
    }

    function test_acceptPauseAdmin_revertNotPending() public {
        router.transferPauseAdmin(alice);
        vm.prank(nobody);
        vm.expectRevert("PoolRouter: not pending admin");
        router.acceptPauseAdmin();
    }

    function test_newAdmin_canPause() public {
        router.transferPauseAdmin(alice);
        vm.prank(alice);
        router.acceptPauseAdmin();
        vm.prank(alice);
        router.pause();
        assertTrue(router.paused());
    }
}

contract FlashRebalancerPauseAdminTransferTest is Test {
    FlashRebalancer rebalancer;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        MockFlashLender lender = new MockFlashLender();
        rebalancer = new FlashRebalancer(address(lender), address(this));
    }

    function test_transferPauseAdmin_setsPending() public {
        rebalancer.transferPauseAdmin(alice);
        assertEq(rebalancer.pendingPauseAdmin(), alice);
    }

    function test_transferPauseAdmin_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("FlashRebalancer: not pause admin");
        rebalancer.transferPauseAdmin(alice);
    }

    function test_acceptPauseAdmin_transfers() public {
        rebalancer.transferPauseAdmin(alice);
        vm.prank(alice);
        rebalancer.acceptPauseAdmin();
        assertEq(rebalancer.pauseAdmin(), alice);
    }

    function test_acceptPauseAdmin_revertNotPending() public {
        rebalancer.transferPauseAdmin(alice);
        vm.prank(nobody);
        vm.expectRevert("FlashRebalancer: not pending admin");
        rebalancer.acceptPauseAdmin();
    }
}

contract SecondaryMarketRouterPauseAdminTransferTest is Test {
    SecondaryMarketRouter router;
    address alice = makeAddr("alice");
    address nobody = makeAddr("nobody");

    function setUp() public {
        router = new SecondaryMarketRouter(makeAddr("dex"), address(this));
    }

    function test_transferPauseAdmin_setsPending() public {
        router.transferPauseAdmin(alice);
        assertEq(router.pendingPauseAdmin(), alice);
    }

    function test_transferPauseAdmin_revertNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert("SecondaryMarketRouter: not pause admin");
        router.transferPauseAdmin(alice);
    }

    function test_acceptPauseAdmin_transfers() public {
        router.transferPauseAdmin(alice);
        vm.prank(alice);
        router.acceptPauseAdmin();
        assertEq(router.pauseAdmin(), alice);
    }

    function test_acceptPauseAdmin_revertNotPending() public {
        router.transferPauseAdmin(alice);
        vm.prank(nobody);
        vm.expectRevert("SecondaryMarketRouter: not pending admin");
        router.acceptPauseAdmin();
    }
}
