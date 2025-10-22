// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultTestBase} from "./VaultTestBase.sol";

contract VaultInitializationTest is VaultTestBase {
    function test_Initialization() public view {
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.TREASURY(), treasury);
        assertEq(vault.OFFSET(), OFFSET);
        assertEq(vault.rewardFee(), REWARD_FEE);
        assertEq(vault.name(), "Mock Vault");
        assertEq(vault.symbol(), "mvUSDC");
        assertEq(vault.decimals(), 6);
    }

    function test_InitialState() public view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(treasury), 0);
    }

    function test_Offset_InitialValue() public view {
        assertEq(vault.OFFSET(), OFFSET);
    }

    function test_GetVaultConfig() public view {
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
}
