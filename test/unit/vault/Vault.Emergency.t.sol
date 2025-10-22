// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";

contract VaultEmergencyTest is VaultTestBase {
    function test_EmergencyWithdraw_Basic() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        address receiver = makeAddr("receiver");
        uint256 vaultAssets = vault.totalAssets();

        vault.emergencyWithdraw(receiver);

        uint256 receiverBalance = asset.balanceOf(receiver);

        assertEq(receiverBalance, vaultAssets);
        assertEq(vault.totalAssets(), 0);
    }

    function test_EmergencyWithdraw_RevertIf_NotEmergencyRole() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.emergencyWithdraw(alice);
    }

    function test_EmergencyWithdraw_WithEmergencyRole() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        address emergency = makeAddr("emergency");
        vault.grantRole(vault.EMERGENCY_ROLE(), emergency);

        address receiver = makeAddr("receiver");

        vm.prank(emergency);
        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), 100_000e6);
    }

    function test_EmergencyWithdraw_WithZeroAssets() public {
        address receiver = makeAddr("receiver");

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), 0);
    }

    function test_EmergencyWithdraw_DoesNotAffectShares() public {
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100_000e6, alice);

        address receiver = makeAddr("receiver");

        vault.emergencyWithdraw(receiver);

        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.totalSupply(), aliceShares);
    }

    function test_EmergencyWithdraw_PausesVault() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        assertFalse(vault.paused());

        address receiver = makeAddr("receiver");
        vault.emergencyWithdraw(receiver);

        assertTrue(vault.paused());
    }

    function test_EmergencyWithdraw_WhenAlreadyPaused() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        vault.pause();

        address receiver = makeAddr("receiver");

        vm.expectRevert();
        vault.emergencyWithdraw(receiver);
    }

    function test_EmergencyWithdraw_MultipleDepositors() public {
        vm.prank(alice);
        vault.deposit(50_000e6, alice);

        vm.prank(bob);
        vault.deposit(30_000e6, bob);

        address receiver = makeAddr("receiver");
        uint256 totalAssets = vault.totalAssets();

        vault.emergencyWithdraw(receiver);

        assertEq(asset.balanceOf(receiver), totalAssets);
    }
}
