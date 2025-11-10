// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./MorphoAdapterTestBase.sol";

contract MorphoAdapterApprovalTest is MorphoAdapterTestBase {
    function test_RefreshMorphoApproval_Success() public {
        vm.prank(address(vault));
        usdc.approve(address(morpho), 0);
        assertEq(usdc.allowance(address(vault), address(morpho)), 0);

        vault.refreshMorphoApproval();

        assertEq(usdc.allowance(address(vault), address(morpho)), type(uint256).max);
    }

    function test_RefreshMorphoApproval_RevertWhen_NotAdmin() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.refreshMorphoApproval();
    }

    function test_RefreshMorphoApproval_SetsMaxApproval() public {
        vm.prank(address(vault));
        usdc.approve(address(morpho), 1_000e6);
        assertEq(usdc.allowance(address(vault), address(morpho)), 1_000e6);

        vault.refreshMorphoApproval();
        assertEq(usdc.allowance(address(vault), address(morpho)), type(uint256).max);
    }

    function test_RefreshMorphoApproval_EmitsApprovalEvent() public {
        vm.prank(address(vault));
        usdc.approve(address(morpho), 0);

        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Approval(address(vault), address(morpho), type(uint256).max);

        vault.refreshMorphoApproval();
    }

    function test_RefreshMorphoApproval_WorksWhenAlreadyMax() public {
        assertEq(usdc.allowance(address(vault), address(morpho)), type(uint256).max);
        vault.refreshMorphoApproval();
        assertEq(usdc.allowance(address(vault), address(morpho)), type(uint256).max);
    }

    function test_RefreshMorphoApproval_RestoresDepositFunctionality() public {
        vm.prank(address(vault));
        usdc.approve(address(morpho), 0);

        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vault.refreshMorphoApproval();

        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e6, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_RefreshMorphoApproval_OnlyAdminRole() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert();
        vm.prank(randomUser);
        vault.refreshMorphoApproval();

        vault.refreshMorphoApproval();

        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), randomUser);

        vm.prank(randomUser);
        vault.refreshMorphoApproval();

        assertEq(usdc.allowance(address(vault), address(morpho)), type(uint256).max);
    }
}
