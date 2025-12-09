// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626AdapterTestBase} from "./ERC4626AdapterTestBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ERC4626AdapterDepositUnallocatedTest is ERC4626AdapterTestBase {
    event TargetVaultDeposit(uint256 assets, uint256 underlyingSharesMinted, uint256 underlyingShareBalance);

    function test_DepositUnallocatedAssets_Success() public {
        // Setup: Alice makes initial deposit to establish vault state
        uint256 initialDeposit = 10_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Simulate direct USDC donation to vault contract
        uint256 donationAmount = 5_000e6;
        usdc.mint(address(vault), donationAmount);

        // Verify unallocated balance exists
        assertEq(usdc.balanceOf(address(vault)), donationAmount, "Vault should have unallocated USDC");

        // Record state before deposit
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 targetSharesBefore = targetVault.balanceOf(address(vault));

        // Manager deposits unallocated assets
        vm.expectEmit(true, true, true, false);
        emit TargetVaultDeposit(donationAmount, 0, 0); // We don't check exact share amounts
        vault.depositUnallocatedAssets();

        // Verify all unallocated assets were deposited
        assertEq(usdc.balanceOf(address(vault)), 0, "Vault should have no idle USDC after deposit");

        // Verify target vault received the assets
        uint256 targetSharesAfter = targetVault.balanceOf(address(vault));
        assertGt(targetSharesAfter, targetSharesBefore, "Target vault shares should increase");

        // Verify totalAssets increased (now includes the deposited amount)
        uint256 totalAssetsAfter = vault.totalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore, "Total assets should increase");
    }

    function test_DepositUnallocatedAssets_RevertWhen_NotManager() public {
        // Simulate direct USDC donation
        uint256 donationAmount = 1_000e6;
        usdc.mint(address(vault), donationAmount);

        // Non-manager (alice) tries to call depositUnallocatedAssets
        bytes32 managerRole = vault.MANAGER_ROLE();
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, managerRole));

        vm.prank(alice);
        vault.depositUnallocatedAssets();
    }

    function test_DepositUnallocatedAssets_RevertWhen_EmergencyMode() public {
        // Setup: Alice makes initial deposit
        uint256 initialDeposit = 10_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Simulate direct USDC donation
        uint256 donationAmount = 5_000e6;
        usdc.mint(address(vault), donationAmount);

        // Activate emergency mode
        vault.emergencyWithdraw();

        // Try to deposit unallocated assets during emergency
        vm.expectRevert(abi.encodeWithSignature("DisabledDuringEmergencyMode()"));
        vault.depositUnallocatedAssets();
    }

    function test_DepositUnallocatedAssets_RevertsIf_ZeroBalance() public {
        // Verify vault has no idle balance
        assertEq(usdc.balanceOf(address(vault)), 0, "Vault should have no idle USDC");

        // Record state before
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 targetSharesBefore = targetVault.balanceOf(address(vault));

        // Call depositUnallocatedAssets with zero balance (should be no-op)
        vm.expectRevert(abi.encodeWithSignature("TargetVaultDepositFailed()"));
        vault.depositUnallocatedAssets();

        // Verify state unchanged
        assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
        assertEq(targetVault.balanceOf(address(vault)), targetSharesBefore, "Target shares should remain unchanged");
    }

    function test_DepositUnallocatedAssets_MultipleDonations() public {
        // Setup: Alice makes initial deposit
        uint256 initialDeposit = 10_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // First donation
        uint256 donation1 = 2_000e6;
        usdc.mint(address(vault), donation1);
        vault.depositUnallocatedAssets();
        assertEq(usdc.balanceOf(address(vault)), 0, "Should have no idle balance after first deposit");

        // Second donation
        uint256 donation2 = 3_000e6;
        usdc.mint(address(vault), donation2);
        vault.depositUnallocatedAssets();
        assertEq(usdc.balanceOf(address(vault)), 0, "Should have no idle balance after second deposit");

        // Verify total assets increased by both donations
        uint256 expectedTotalAssets = initialDeposit + donation1 + donation2;
        assertApproxEqAbs(vault.totalAssets(), expectedTotalAssets, 10, "Total assets should include both donations");
    }

    function test_DepositUnallocatedAssets_AfterDeposit_FeeHarvesting() public {
        // Setup: Alice makes initial deposit
        uint256 initialDeposit = 10_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Generate some yield in target vault
        uint256 yieldAmount = 1_000e6;
        usdc.mint(address(targetVault), yieldAmount);

        // Simulate direct USDC donation
        uint256 donationAmount = 5_000e6;
        usdc.mint(address(vault), donationAmount);

        // Deposit unallocated assets
        vault.depositUnallocatedAssets();

        // Now make a new deposit to trigger fee harvest
        uint256 newDeposit = 1_000e6;
        vm.prank(alice);
        vault.deposit(newDeposit, alice);

        // Verify treasury received fees from yield (not from donation before it was deposited)
        uint256 treasuryShares = vault.balanceOf(treasury);
        assertGt(treasuryShares, 0, "Treasury should have received fee shares from yield");

        // Verify users can still withdraw
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        assertGt(usdc.balanceOf(alice), 0, "Alice should receive assets on withdrawal");
    }

    function test_DepositUnallocatedAssets_DonationTreatedAsUnrealizedProfit() public {
        // Setup: Alice makes initial deposit
        uint256 initialDeposit = 100_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Generate yield in target vault (10% profit)
        uint256 yieldAmount = 10_000e6;
        usdc.mint(address(targetVault), yieldAmount);

        // Someone donates USDC directly
        uint256 donationAmount = 50_000e6;
        usdc.mint(address(vault), donationAmount);

        // Record state before depositUnallocatedAssets
        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        // Call depositUnallocatedAssets - deposits donation WITHOUT harvesting fees
        vault.depositUnallocatedAssets();

        // No fees should be harvested yet (donation just deposited)
        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        assertEq(treasurySharesAfter, treasurySharesBefore, "No fees harvested during depositUnallocatedAssets");

        // Donation is now in totalAssets as unrealized profit
        uint256 expectedTotal = initialDeposit + yieldAmount + donationAmount;
        assertApproxEqAbs(vault.totalAssets(), expectedTotal, 10, "Total should include donation");

        // lastTotalAssets should NOT be updated (still at initial deposit)
        assertApproxEqAbs(vault.lastTotalAssets(), initialDeposit, 10, "HWM still at initial deposit");

        // KEY TEST: Next harvest should include BOTH yield AND donation as profit
        vault.harvestFees();

        uint256 treasurySharesAfterHarvest = vault.balanceOf(treasury);
        uint256 feeSharesMinted = treasurySharesAfterHarvest - treasurySharesBefore;
        assertGt(feeSharesMinted, 0, "Treasury should receive fee shares");

        // Fee should be taken from total profit (yield + donation)
        uint256 totalProfit = yieldAmount + donationAmount;
        uint256 expectedFeeValue = (totalProfit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();
        uint256 actualFeeValue = vault.convertToAssets(feeSharesMinted);

        // Fee includes both yield and donation as unrealized profit
        assertApproxEqAbs(
            actualFeeValue,
            expectedFeeValue,
            100,
            "Fee should be taken from total unrealized profit (yield + donation)"
        );
    }

    function test_DepositUnallocatedAssets_RespectsTargetVaultCapacity() public {
        // Setup: Alice makes initial deposit
        uint256 initialDeposit = 10_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Set target vault to have total capacity of 110k (already has 10k)
        uint256 targetTotalCap = 110_000e6;
        targetVault.setLiquidityCap(targetTotalCap);

        // Available capacity = 110k - 10k = 100k
        uint256 availableCapacity = targetTotalCap - initialDeposit;

        // Large donation that exceeds available capacity
        uint256 donationAmount = 1_000_000e6;
        usdc.mint(address(vault), donationAmount);

        // Record state before
        uint256 vaultBalanceBefore = usdc.balanceOf(address(vault));

        // Call depositUnallocatedAssets - should only deposit what target vault can accept
        vault.depositUnallocatedAssets();

        // Verify only availableCapacity was deposited, rest remains idle
        uint256 remainingBalance = usdc.balanceOf(address(vault));
        uint256 depositedAmount = vaultBalanceBefore - remainingBalance;

        assertApproxEqAbs(
            depositedAmount, availableCapacity, 1, "Should deposit only up to target vault capacity"
        );
        assertApproxEqAbs(
            remainingBalance, donationAmount - availableCapacity, 1, "Excess should remain idle"
        );

        // Verify totalAssets includes only the deposited portion
        uint256 expectedTotal = initialDeposit + availableCapacity;
        assertApproxEqAbs(vault.totalAssets(), expectedTotal, 10, "Total should include only deposited amount");
    }

    function test_DepositUnallocatedAssets_RevertsWhen_TargetVaultCapacityZero() public {
        // Setup: Alice makes initial deposit
        uint256 initialDeposit = 10_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Donation
        uint256 donationAmount = 5_000e6;
        usdc.mint(address(vault), donationAmount);

        // Set target vault capacity to current assets (no room for more)
        targetVault.setLiquidityCap(initialDeposit);

        // Should revert because Math.min(donation, 0) = 0, which causes TargetVaultDepositFailed
        vm.expectRevert(abi.encodeWithSignature("TargetVaultDepositFailed()"));
        vault.depositUnallocatedAssets();
    }

    function test_DepositUnallocatedAssets_PartialDeposit_CanBeCalledAgainLater() public {
        // Setup: Alice makes initial deposit
        uint256 initialDeposit = 10_000e6;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Large donation
        uint256 donationAmount = 200_000e6;
        usdc.mint(address(vault), donationAmount);

        // Target vault has limited capacity: 10k existing + 50k available
        uint256 firstCapacity = 50_000e6;
        targetVault.setLiquidityCap(initialDeposit + firstCapacity);

        // First call - deposits only 50k
        vault.depositUnallocatedAssets();
        assertApproxEqAbs(
            usdc.balanceOf(address(vault)), donationAmount - firstCapacity, 1, "Should have remaining balance"
        );

        // Later, target vault capacity increases to allow another 100k
        uint256 secondCapacity = 100_000e6;
        targetVault.setLiquidityCap(initialDeposit + firstCapacity + secondCapacity);

        // Second call - deposits another portion
        vault.depositUnallocatedAssets();
        assertApproxEqAbs(
            usdc.balanceOf(address(vault)),
            donationAmount - firstCapacity - secondCapacity,
            1,
            "Should have less remaining"
        );

        // Third call with unlimited capacity
        targetVault.setLiquidityCap(type(uint256).max);
        vault.depositUnallocatedAssets();

        // All should be deposited now
        assertEq(usdc.balanceOf(address(vault)), 0, "All donation should be deposited");
    }
}
