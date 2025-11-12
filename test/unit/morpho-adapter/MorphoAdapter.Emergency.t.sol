// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./MorphoAdapterTestBase.sol";

contract MorphoAdapterEmergencyTest is MorphoAdapterTestBase {
    function test_EmergencyWithdraw_ReturnsZeroWhenNoShares() public {
        address receiver = makeAddr("receiver");
        uint256 withdrawn = vault.emergencyWithdraw(receiver);

        assertEq(withdrawn, 0);
        assertEq(usdc.balanceOf(receiver), 0);
    }

    function test_EmergencyWithdraw_RedeemsMorphoShares() public {
        vm.prank(alice);
        vault.deposit(80_000e6, alice);

        address receiver = makeAddr("receiver");
        uint256 withdrawn = vault.emergencyWithdraw(receiver);

        assertEq(withdrawn, 80_000e6);
        assertEq(usdc.balanceOf(receiver), 80_000e6);
        assertEq(morpho.balanceOf(address(vault)), 0);
    }

    function test_EmergencyWithdraw_WithLiquidityCap() public {
        vm.prank(alice);
        vault.deposit(80_000e6, alice);

        address receiver = makeAddr("receiver");

        uint256 firstWithdrawalAmount = 50_000e6;
        morpho.setLiquidityCap(firstWithdrawalAmount);

        uint256 withdrawn1 = vault.emergencyWithdraw(receiver);

        assertEq(withdrawn1, firstWithdrawalAmount);
        assertEq(usdc.balanceOf(receiver), firstWithdrawalAmount);
        assertEq(morpho.balanceOf(address(vault)), morpho.convertToShares(30_000e6));

        morpho.setLiquidityCap(type(uint256).max);

        uint256 withdrawn2 = vault.emergencyWithdraw(receiver);

        assertEq(withdrawn2, 30_000e6);
        assertEq(usdc.balanceOf(receiver), 80_000e6);
        assertEq(morpho.balanceOf(address(vault)), 0);
    }
}
