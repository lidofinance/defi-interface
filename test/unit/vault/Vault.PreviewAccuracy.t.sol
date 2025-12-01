// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./VaultTestBase.sol";

/**
 * @title Vault Preview Accuracy Tests
 * @notice Tests that preview functions EXACTLY match actual operations with profit
 * @dev These tests verify that OFFSET and +1 adjustments work correctly even with profit/fees
 */
contract VaultPreviewAccuracyTest is VaultTestBase {
    /**
     * @notice Tests previewDeposit with profit between deposits
     * @dev Profit breaks the supply:total ratio, testing formula robustness
     */
    function test_PreviewDeposit_ExactMatch(uint8 offset, uint96 aliceDepositAmount, uint96 bobDepositAmount) public {
        vm.assume(offset > 0 && offset < 23);
        vm.assume(aliceDepositAmount >= 1000 && aliceDepositAmount <= 1_000_000_000e6);
        vm.assume(bobDepositAmount >= 1000 && bobDepositAmount <= 1_000_000_000e6);

        MockVault vault0 = new MockVault(
            address(asset),
            treasury,
            500, // 5% fee
            offset,
            "Vault",
            "Test",
            address(this)
        );

        // First deposit
        asset.mint(alice, aliceDepositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault0), type(uint256).max);
        uint256 previewedShares = vault0.previewDeposit(aliceDepositAmount);
        uint256 actualShares = vault0.deposit(aliceDepositAmount, alice);
        vm.stopPrank();

        assertEq(actualShares, previewedShares, "First deposit: preview must match");

        // Simulate profit (10% of deposited amount)
        uint256 profit = aliceDepositAmount / 10;
        asset.mint(address(vault0), profit);

        // Second deposit (after profit)
        asset.mint(bob, bobDepositAmount);
        vm.startPrank(bob);
        asset.approve(address(vault0), type(uint256).max);
        previewedShares = vault0.previewDeposit(bobDepositAmount);
        actualShares = vault0.deposit(bobDepositAmount, bob);
        vm.stopPrank();

        assertEq(actualShares, previewedShares, "Second deposit with profit: preview must match");
    }

    /**
     * @notice Tests previewMint with profit between operations
     * @dev Profit breaks the supply:total ratio, testing formula robustness
     */
    function test_PreviewMint_ExactMatch(uint8 offset, uint96 aliceDepositAmount, uint96 bobDepositAmount) public {
        vm.assume(offset > 0 && offset < 23);
        vm.assume(aliceDepositAmount >= 1000 && aliceDepositAmount <= 1_000_000_000e6);
        vm.assume(bobDepositAmount >= 1000 && bobDepositAmount <= 1_000_000_000e6);

        MockVault vault0 = new MockVault(
            address(asset),
            treasury,
            500, // 5% fee
            offset,
            "Vault",
            "Test",
            address(this)
        );

        // First deposit to establish vault state
        asset.mint(alice, aliceDepositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault0), type(uint256).max);
        vault0.deposit(aliceDepositAmount, alice);
        vm.stopPrank();

        // Simulate profit (10% of deposited amount)
        uint256 profit = aliceDepositAmount / 10;
        asset.mint(address(vault0), profit);

        // Bob mints shares (after profit)
        // Calculate how many shares Bob would get for his deposit
        uint256 bobDesiredShares = vault0.previewDeposit(bobDepositAmount);
        vm.assume(bobDesiredShares > 0);

        uint256 previewedAssets = vault0.previewMint(bobDesiredShares);
        vm.assume(previewedAssets <= 1_000_000_000e6);

        asset.mint(bob, previewedAssets + 1000); // Extra buffer
        vm.startPrank(bob);
        asset.approve(address(vault0), type(uint256).max);
        uint256 actualAssets = vault0.mint(bobDesiredShares, bob);
        vm.stopPrank();

        assertEq(actualAssets, previewedAssets, "Mint with profit: preview must match");
    }

    /**
     * @notice Tests previewRedeem with profit after deposits
     * @dev Profit breaks the supply:total ratio, testing formula robustness
     */
    function test_PreviewRedeem_ExactMatch(uint8 offset, uint96 aliceDepositAmount) public {
        vm.assume(offset > 0 && offset < 23);
        vm.assume(aliceDepositAmount >= 1000 && aliceDepositAmount <= 1_000_000_000e6);

        MockVault vault0 = new MockVault(
            address(asset),
            treasury,
            500, // 5% fee
            offset,
            "Vault",
            "Test",
            address(this)
        );

        // Alice deposits
        asset.mint(alice, aliceDepositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault0), type(uint256).max);
        uint256 aliceShares = vault0.deposit(aliceDepositAmount, alice);
        vm.stopPrank();

        // Simulate profit (10% of deposited amount)
        uint256 profit = aliceDepositAmount / 10;
        asset.mint(address(vault0), profit);

        // Alice redeems half her shares (after profit)
        uint256 sharesToRedeem = aliceShares / 2;
        vm.assume(sharesToRedeem > 0);

        vm.startPrank(alice);
        uint256 previewedAssets = vault0.previewRedeem(sharesToRedeem);
        uint256 actualAssets = vault0.redeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        assertEq(actualAssets, previewedAssets, "Redeem with profit: preview must match");
    }

    /**
     * @notice Tests previewWithdraw with profit after deposits
     * @dev Profit breaks the supply:total ratio, testing formula robustness
     */
    function test_PreviewWithdraw_ExactMatch(uint8 offset, uint96 aliceDepositAmount) public {
        vm.assume(offset > 0 && offset < 23);
        vm.assume(aliceDepositAmount >= 2000 && aliceDepositAmount <= 1_000_000_000e6);

        MockVault vault0 = new MockVault(
            address(asset),
            treasury,
            500, // 5% fee
            offset,
            "Vault",
            "Test",
            address(this)
        );

        // Alice deposits
        asset.mint(alice, aliceDepositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault0), type(uint256).max);
        vault0.deposit(aliceDepositAmount, alice);
        vm.stopPrank();

        // Simulate profit (10% of deposited amount)
        uint256 profit = aliceDepositAmount / 10;
        asset.mint(address(vault0), profit);

        // Alice withdraws half her original deposit (after profit)
        uint256 assetsToWithdraw = aliceDepositAmount / 2;

        vm.startPrank(alice);
        uint256 previewedShares = vault0.previewWithdraw(assetsToWithdraw);
        uint256 actualShares = vault0.withdraw(assetsToWithdraw, alice, alice);
        vm.stopPrank();

        assertEq(actualShares, previewedShares, "Withdraw with profit: preview must match");
    }
}
