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
}
