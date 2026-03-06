// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AIKeeper} from "../../src/ai/AIKeeper.sol";
import {IAIKeeper} from "../../src/interfaces/IAIKeeper.sol";
import {NexusHub} from "../../src/nexus/NexusHub.sol";
import {CollateralOracle} from "../../src/nexus/CollateralOracle.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {CDSPoolFactory} from "../../src/shield/CDSPoolFactory.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract AIKeeperTest is Test {
    uint256 constant WAD = 1e18;

    AIKeeper keeper;
    NexusHub hub;
    CollateralOracle collateralOracle;
    CreditEventOracle creditOracle;
    CDSPoolFactory poolFactory;
    MockYieldSource usdc;

    address monitor = makeAddr("monitor");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address teleporter = makeAddr("teleporter");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        collateralOracle = new CollateralOracle();
        creditOracle = new CreditEventOracle();
        poolFactory = new CDSPoolFactory(address(this), address(this), 100);

        hub = new NexusHub(address(collateralOracle), teleporter, 1.5e18, 500);

        keeper = new AIKeeper(
            address(hub),
            address(creditOracle),
            address(poolFactory),
            1 days
        );
        keeper.setAIMonitor(monitor, true);

        // Register USDC as collateral in oracle
        collateralOracle.registerAsset(address(usdc), 1e18, 8500);
    }

    // --- Constructor ---

    function test_constructor() public view {
        assertEq(address(keeper.NEXUS_HUB()), address(hub));
        assertEq(address(keeper.ORACLE()), address(creditOracle));
        assertEq(address(keeper.POOL_FACTORY()), address(poolFactory));
        assertEq(keeper.maxPriorityAge(), 1 days);
        assertEq(keeper.owner(), address(this));
    }

    function test_constructor_revert_zeroHub() public {
        vm.expectRevert("AIKeeper: zero hub");
        new AIKeeper(address(0), address(creditOracle), address(poolFactory), 1 days);
    }

    // --- Monitor Authorization ---

    function test_setAIMonitor() public {
        keeper.setAIMonitor(alice, true);
        assertTrue(keeper.isAIMonitor(alice));
    }

    function test_setAIMonitor_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert("AIKeeper: not owner");
        keeper.setAIMonitor(alice, true);
    }

    // --- Priority Updates ---

    function test_updatePriority_basic() public {
        vm.prank(monitor);
        keeper.updateAccountPriority(alice, 100e18, 50e18, true);

        IAIKeeper.AccountPriority memory p = keeper.getAccountPriority(alice);
        assertEq(p.account, alice);
        assertEq(p.priorityScore, 100e18);
        assertEq(p.estimatedShortfall, 50e18);
        assertTrue(p.flagged);
        assertEq(p.timestamp, block.timestamp);
    }

    function test_updatePriority_revert_notMonitor() public {
        vm.prank(alice);
        vm.expectRevert("AIKeeper: not monitor");
        keeper.updateAccountPriority(alice, 100e18, 50e18, true);
    }

    function test_updatePriority_addsToMonitoredList() public {
        vm.startPrank(monitor);
        keeper.updateAccountPriority(alice, 100e18, 50e18, false);
        keeper.updateAccountPriority(bob, 200e18, 100e18, true);
        vm.stopPrank();

        assertEq(keeper.getMonitoredAccountCount(), 2);
    }

    function test_batchUpdatePriorities() public {
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = charlie;
        uint256[] memory scores = new uint256[](3);
        scores[0] = 50e18;
        scores[1] = 200e18;
        scores[2] = 100e18;
        uint256[] memory shortfalls = new uint256[](3);
        shortfalls[0] = 10e18;
        shortfalls[1] = 80e18;
        shortfalls[2] = 40e18;
        bool[] memory flags = new bool[](3);
        flags[0] = false;
        flags[1] = true;
        flags[2] = true;

        vm.prank(monitor);
        keeper.batchUpdatePriorities(accounts, scores, shortfalls, flags);

        assertEq(keeper.getMonitoredAccountCount(), 3);
        assertEq(keeper.getAccountPriority(bob).priorityScore, 200e18);
    }

    // --- Remove Account ---

    function test_removeAccount() public {
        vm.startPrank(monitor);
        keeper.updateAccountPriority(alice, 100e18, 50e18, false);
        keeper.updateAccountPriority(bob, 200e18, 100e18, true);
        assertEq(keeper.getMonitoredAccountCount(), 2);

        keeper.removeAccount(alice);
        assertEq(keeper.getMonitoredAccountCount(), 1);
        assertEq(keeper.getAccountPriority(alice).priorityScore, 0);
        vm.stopPrank();
    }

    // --- Get Top Accounts ---

    function test_getTopAccounts_orderedByPriority() public {
        vm.startPrank(monitor);
        keeper.updateAccountPriority(alice, 50e18, 10e18, false);
        keeper.updateAccountPriority(bob, 200e18, 80e18, true);
        keeper.updateAccountPriority(charlie, 100e18, 40e18, false);
        vm.stopPrank();

        IAIKeeper.AccountPriority[] memory top = keeper.getTopAccounts(2);
        assertEq(top.length, 2);
        assertEq(top[0].account, bob, "Highest priority first");
        assertEq(top[1].account, charlie, "Second highest");
    }

    // --- Get Flagged Accounts ---

    function test_getFlaggedAccounts() public {
        vm.startPrank(monitor);
        keeper.updateAccountPriority(alice, 50e18, 10e18, false);
        keeper.updateAccountPriority(bob, 200e18, 80e18, true);
        keeper.updateAccountPriority(charlie, 100e18, 40e18, true);
        vm.stopPrank();

        address[] memory flagged = keeper.getFlaggedAccounts();
        assertEq(flagged.length, 2);
    }

    // --- Ownership ---

    function test_ownershipTransfer_twoStep() public {
        keeper.transferOwnership(alice);
        assertEq(keeper.owner(), address(this));

        vm.prank(alice);
        keeper.acceptOwnership();
        assertEq(keeper.owner(), alice);
    }

    // --- Fuzz ---

    function testFuzz_updatePriority(uint256 score, uint256 shortfall) public {
        score = bound(score, 0, 1000e18);
        shortfall = bound(shortfall, 0, 1000e18);

        vm.prank(monitor);
        keeper.updateAccountPriority(alice, score, shortfall, score > 500e18);

        IAIKeeper.AccountPriority memory p = keeper.getAccountPriority(alice);
        assertEq(p.priorityScore, score);
        assertEq(p.estimatedShortfall, shortfall);
    }
}
