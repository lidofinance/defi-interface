// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./MorphoAdapterTestBase.sol";

contract MorphoAdapterInitializationTest is MorphoAdapterTestBase {
    function test_Initialization() public view {
        assertEq(address(vault.ASSET()), address(usdc));
        assertEq(address(vault.MORPHO_VAULT()), address(morpho));
        assertEq(vault.TREASURY(), treasury);
        assertEq(vault.OFFSET(), OFFSET);
        assertEq(vault.rewardFee(), REWARD_FEE);
        assertEq(vault.name(), "Morpho USDC Vault");
        assertEq(vault.symbol(), "mvUSDC");
        assertEq(vault.decimals(), assetDecimals);
    }

    function test_InitialState() public view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(treasury), 0);
    }

    function test_MorphoApprovalSetup() public view {
        assertEq(usdc.allowance(address(vault), address(morpho)), type(uint256).max);
    }

    function test_Offset_InitialValue() public view {
        assertEq(vault.OFFSET(), OFFSET);
    }

    function test_Offset_ProtectsAgainstInflationAttack() public {
        vm.prank(alice);
        vault.deposit(1000, alice);

        deal(address(usdc), address(morpho), usdc.balanceOf(address(morpho)) + 100_000e6);

        vm.prank(bob);
        uint256 victimShares = vault.deposit(10_000e6, bob);

        assertGt(victimShares, 0);
    }

    function testFuzz_TotalAssets_ReflectsMorphoBalance(uint96 depositAmount) public {
        uint256 amount = uint256(depositAmount);
        vm.assume(amount >= vault.MIN_FIRST_DEPOSIT());
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 morphoShares = morpho.balanceOf(address(vault));
        uint256 morphoAssets = morpho.convertToAssets(morphoShares);

        assertEq(vaultTotalAssets, morphoAssets);
    }

    function testFuzz_MaxWithdraw(uint96 depositAmount) public {
        uint256 amount = uint256(depositAmount);
        vm.assume(amount >= vault.MIN_FIRST_DEPOSIT());
        usdc.mint(alice, amount);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);

        assertApproxEqAbs(maxWithdraw, amount, 1);
    }

    function testFuzz_DepositWithdraw_RoundingDoesNotCauseLoss(uint96 depositAmount) public {
        uint256 amount = uint256(depositAmount);
        vm.assume(amount >= vault.MIN_FIRST_DEPOSIT());
        usdc.mint(alice, amount);

        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        uint256 balanceAfter = usdc.balanceOf(alice);
        assertApproxEqAbs(balanceAfter, balanceBefore, 2);
    }

    function test_MultipleDepositsWithdraws_MaintainsAccounting() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            vault.deposit(10_000e6, alice);
        }

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            vault.withdraw(10_000e6, alice, alice);
        }

        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        assertApproxEqAbs(assets, 20_000e6, 5);
    }
}
