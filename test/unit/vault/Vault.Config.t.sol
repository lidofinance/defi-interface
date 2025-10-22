// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";
import {Vault} from "src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultConfigTest is VaultTestBase {
    function test_SetMinFirstDeposit_Basic() public {
        uint256 newMinDeposit = 5000;

        vault.setMinFirstDeposit(newMinDeposit);

        (, , uint256 minFirstDeposit, , ) = vault.getVaultConfig();
        assertEq(minFirstDeposit, newMinDeposit);
    }

    function test_SetMinFirstDeposit_RevertIf_NotAdmin() public {
        uint256 newMinDeposit = 5000;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        vault.setMinFirstDeposit(newMinDeposit);
    }

    function test_SetMinFirstDeposit_ToZero() public {
        vault.setMinFirstDeposit(0);

        (, , uint256 minFirstDeposit, , ) = vault.getVaultConfig();
        assertEq(minFirstDeposit, 0);
    }

    function test_SetMinFirstDeposit_ToLargeValue() public {
        uint256 newMinDeposit = 1_000_000e6;

        vault.setMinFirstDeposit(newMinDeposit);

        (, , uint256 minFirstDeposit, , ) = vault.getVaultConfig();
        assertEq(minFirstDeposit, newMinDeposit);
    }

    function test_SetMinFirstDeposit_EnforcesNewMinimum() public {
        uint256 newMinDeposit = 10_000e6;
        vault.setMinFirstDeposit(newMinDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                Vault.FirstDepositTooSmall.selector,
                newMinDeposit,
                newMinDeposit - 1
            )
        );
        vm.prank(alice);
        vault.deposit(newMinDeposit - 1, alice);
    }

    function test_SetMinFirstDeposit_AllowsDepositsAboveMinimum() public {
        uint256 newMinDeposit = 10_000e6;
        vault.setMinFirstDeposit(newMinDeposit);

        vm.prank(alice);
        uint256 shares = vault.deposit(newMinDeposit, alice);

        uint256 expectedShares = newMinDeposit * 10 ** vault.OFFSET();
        assertEq(shares, expectedShares);
    }

    function test_SetMinFirstDeposit_DoesNotAffectSubsequentDeposits() public {
        uint256 newMinDeposit = 10_000e6;
        vault.setMinFirstDeposit(newMinDeposit);

        vm.prank(alice);
        vault.deposit(newMinDeposit, alice);

        vm.prank(bob);
        uint256 shares = vault.deposit(1, bob);

        uint256 expectedShares = vault.previewDeposit(1);
        assertEq(shares, expectedShares);
    }

    function test_SetMinFirstDeposit_MultipleChanges() public {
        vault.setMinFirstDeposit(5000);
        (, , uint256 minFirstDeposit1, , ) = vault.getVaultConfig();
        assertEq(minFirstDeposit1, 5000);

        vault.setMinFirstDeposit(10000);
        (, , uint256 minFirstDeposit2, , ) = vault.getVaultConfig();
        assertEq(minFirstDeposit2, 10000);

        vault.setMinFirstDeposit(1000);
        (, , uint256 minFirstDeposit3, , ) = vault.getVaultConfig();
        assertEq(minFirstDeposit3, 1000);
    }

    function test_GetVaultConfig_ReturnsAllValues() public {
        vm.prank(alice);
        vault.deposit(100_000e6, alice);

        (
            address treasury_,
            uint256 rewardFee_,
            uint256 minFirstDeposit_,
            uint8 offset_,
            bool isPaused_
        ) = vault.getVaultConfig();

        assertEq(treasury_, treasury);
        assertEq(rewardFee_, REWARD_FEE);
        assertEq(minFirstDeposit_, 1000);
        assertEq(offset_, OFFSET);
        assertEq(isPaused_, false);
    }

    function test_GetVaultConfig_WhenPaused() public {
        vault.pause();

        (, , , , bool isPaused_) = vault.getVaultConfig();

        assertTrue(isPaused_);
    }
}
