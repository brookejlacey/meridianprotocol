// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {ProtocolTreasury} from "../src/ProtocolTreasury.sol";
import {IProtocolTreasury} from "../src/interfaces/IProtocolTreasury.sol";
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";

contract ProtocolTreasuryTest is Test {
    ProtocolTreasury treasury;
    MockYieldSource token;

    address owner = makeAddr("owner");
    address recipient = makeAddr("recipient");

    function setUp() public {
        treasury = new ProtocolTreasury(owner);
        token = new MockYieldSource("Test Token", "TST", 18);
    }

    function test_constructor_setsOwner() public view {
        assertEq(treasury.owner(), owner);
    }

    function test_constructor_revertZeroOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new ProtocolTreasury(address(0));
    }

    function test_withdraw() public {
        token.mint(address(treasury), 1000e18);

        vm.prank(owner);
        treasury.withdraw(address(token), recipient, 500e18);

        assertEq(token.balanceOf(recipient), 500e18);
        assertEq(token.balanceOf(address(treasury)), 500e18);
    }

    function test_withdraw_emitsEvent() public {
        token.mint(address(treasury), 1000e18);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IProtocolTreasury.FundsWithdrawn(address(token), recipient, 500e18);
        treasury.withdraw(address(token), recipient, 500e18);
    }

    function test_withdraw_revertNotOwner() public {
        token.mint(address(treasury), 1000e18);

        vm.prank(recipient);
        vm.expectRevert();
        treasury.withdraw(address(token), recipient, 500e18);
    }

    function test_withdraw_revertZeroRecipient() public {
        token.mint(address(treasury), 1000e18);

        vm.prank(owner);
        vm.expectRevert("ProtocolTreasury: zero recipient");
        treasury.withdraw(address(token), address(0), 500e18);
    }

    function test_withdraw_revertZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("ProtocolTreasury: zero amount");
        treasury.withdraw(address(token), recipient, 0);
    }

    function test_balanceOf() public {
        assertEq(treasury.balanceOf(address(token)), 0);

        token.mint(address(treasury), 1000e18);
        assertEq(treasury.balanceOf(address(token)), 1000e18);
    }
}
