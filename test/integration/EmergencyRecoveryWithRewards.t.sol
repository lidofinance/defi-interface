// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "test/unit/erc4626-adapter/ERC4626AdapterTestBase.sol";

contract EmergencyRecoveryWithRewardsTest is ERC4626AdapterTestBase {
    using Math for uint256;

    /// @notice Tests emergency withdraw with fee harvest and recovery activation when target vault reverts
    /// @dev Scenario:
    ///      1. Enter emergency mode
    ///      2. Accrue rewards
    ///      3. Emergency withdraw (with harvestFees)
    ///      4. Verify fees harvested exactly
    ///      5. Force target vault to revert
    ///      6. Activate recovery mode (should succeed despite revert)
    function test_EmergencyRecovery_WithRewardsHarvest_AndTargetVaultRevert() public {
        // 1. Initial deposit by Alice
        uint256 depositAmount = 100_000e6;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceSharesInitial = vault.balanceOf(alice);

        // 2. Activate emergency mode
        vault.activateEmergencyMode();
        assertTrue(vault.emergencyMode(), "Emergency mode should be active");

        // 3. Accrue rewards to target vault
        uint256 rewardAmount = 10_000e6; // 10k USDC profit
        uint256 totalAssetsBeforeRewards = vault.totalAssets();
        usdc.mint(address(targetVault), rewardAmount);
        uint256 profit = vault.totalAssets() - totalAssetsBeforeRewards;
        // Allow for 1 wei rounding error due to ERC4626 conversion
        assertApproxEqAbs(profit, rewardAmount, 2, "Profit should approximately equal reward amount");

        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        uint256 totalSupplyBefore = vault.totalSupply();

        // 4. Execute emergency withdraw (which calls _harvestFees)
        uint256 recovered = vault.emergencyWithdraw();
        assertApproxEqAbs(recovered, depositAmount + rewardAmount, 2, "Should recover assets from protocol");

        // 5. Verify fees were harvested (check value, not exact shares due to rounding)
        uint256 feeSharesMinted = vault.balanceOf(treasury) - treasurySharesBefore;
        assertGt(feeSharesMinted, 0, "Treasury should receive fee shares");
        assertEq(vault.totalSupply() - totalSupplyBefore, feeSharesMinted, "Total supply should increase by fee shares");
        assertEq(vault.balanceOf(alice), aliceSharesInitial, "Alice shares should remain unchanged");

        // Verify fee value is approximately 5% of profit
        uint256 expectedFeeValue = (profit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();
        uint256 actualFeeValue = vault.convertToAssets(feeSharesMinted);
        assertApproxEqAbs(actualFeeValue, expectedFeeValue, 2, "Fee value should be ~5% of profit");

        // 6. Force target vault to revert on balanceOf and convertToAssets
        // This simulates a broken/paused target vault
        vm.mockCallRevert(
            address(targetVault),
            abi.encodeWithSignature("balanceOf(address)", address(vault)),
            "Target vault is broken"
        );

        vm.mockCallRevert(
            address(targetVault),
            abi.encodeWithSignature("convertToAssets(uint256)", uint256(0)),
            "Target vault is broken"
        );

        // 7. Activate recovery mode - should succeed despite target vault reverting
        vault.activateRecovery();
        assertTrue(vault.recoveryMode(), "Recovery mode should be active");
        assertEq(vault.recoveryAssets(), usdc.balanceOf(address(vault)), "Recovery assets mismatch");
        assertEq(vault.recoverySupply(), vault.totalSupply(), "Recovery supply mismatch");

        // Verify users can still redeem in recovery mode despite broken target vault
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 assetsReceived = vault.redeem(aliceSharesInitial, alice, alice);

        assertGt(assetsReceived, 0, "Alice should receive assets in recovery mode");
        assertEq(vault.balanceOf(alice), 0, "Alice should have no shares left");
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + assetsReceived, "Alice USDC balance should increase");
    }
}
