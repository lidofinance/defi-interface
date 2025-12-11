// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMetaMorpho} from "@morpho/interfaces/IMetaMorpho.sol";

import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {EmergencyVault} from "src/EmergencyVault.sol";

import {VaultTestConfig, VaultTestConfigs} from "utils/Constants.sol";

contract MorphoVaultIntegrationTest is Test {
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    address public treasury = makeAddr("treasury");
    address public emergencyAdmin = makeAddr("emergencyAdmin");

    ERC4626Adapter public vault;

    uint256 public constant TOLERANCE = 10;

    // Test state variables
    uint256 public aliceDepositAmount;
    uint256 public bobDepositAmount;
    uint256 public charlieDepositAmount;
    uint256 public totalDepositedAssets;
    uint256 public aliceShares;
    uint256 public bobShares;
    uint256 public charlieShares;
    uint256 public profitAmount;
    uint256 public aliceWithdrawAmount;

    function _forkMainnet() internal {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        vm.skip(bytes(rpcUrl).length == 0, "MAINNET_RPC_URL not set");
        vm.createSelectFork(rpcUrl);
    }

    function _deployVault(VaultTestConfig memory config) internal {
        vault = new ERC4626Adapter(
            config.token,
            config.targetVault,
            treasury,
            config.rewardFee,
            config.offset,
            config.name,
            config.symbol,
            address(this)
        );

        vault.grantRole(vault.EMERGENCY_ROLE(), emergencyAdmin);

        assertTrue(vault.hasRole(vault.EMERGENCY_ROLE(), emergencyAdmin), "Emergency role not granted");
    }

    function _setupUsers(VaultTestConfig memory config) internal {
        IERC20 token = IERC20(config.token);

        deal(config.token, alice, config.testDepositAmount);
        deal(config.token, bob, config.testDepositAmount * 2);
        deal(config.token, charlie, config.testDepositAmount / 2);

        vm.prank(alice);
        SafeERC20.forceApprove(token, address(vault), type(uint256).max);

        vm.prank(bob);
        SafeERC20.forceApprove(token, address(vault), type(uint256).max);

        vm.prank(charlie);
        SafeERC20.forceApprove(token, address(vault), type(uint256).max);
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.deposit(amount, user);
    }

    function _withdraw(address user, uint256 amount) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.withdraw(amount, user, user);
    }

    function _injectProfit(VaultTestConfig memory config, uint256 _profitAmount) internal {
        uint256 currentBalance = IERC20(config.token).balanceOf(config.targetVault);
        deal(config.token, config.targetVault, currentBalance + _profitAmount);
    }

    function _emergencyRedeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = vault.redeem(shares, user, user);
    }

    function _phaseMultiUserDeposits(VaultTestConfig memory config) internal {
        console2.log("\n=== PHASE 1: MULTI-USER DEPOSITS ===");

        IERC20 token = IERC20(config.token);
        IMetaMorpho morphoVault = IMetaMorpho(config.targetVault);

        aliceDepositAmount = config.testDepositAmount;
        bobDepositAmount = config.testDepositAmount * 2;
        charlieDepositAmount = config.testDepositAmount / 2;

        assertEq(token.balanceOf(alice), aliceDepositAmount, "Alice initial balance mismatch");
        assertEq(token.balanceOf(bob), bobDepositAmount, "Bob initial balance mismatch");
        assertEq(token.balanceOf(charlie), charlieDepositAmount, "Charlie initial balance mismatch");

        aliceShares = _deposit(alice, aliceDepositAmount);
        bobShares = _deposit(bob, bobDepositAmount);
        charlieShares = _deposit(charlie, charlieDepositAmount);

        console2.log("Alice deposited:", aliceDepositAmount, "received shares:", aliceShares);
        console2.log("Bob deposited:", bobDepositAmount, "received shares:", bobShares);
        console2.log("Charlie deposited:", charlieDepositAmount, "received shares:", charlieShares);

        assertEq(vault.balanceOf(alice), aliceShares, "Alice shares mismatch");
        assertEq(vault.balanceOf(bob), bobShares, "Bob shares mismatch");
        assertEq(vault.balanceOf(charlie), charlieShares, "Charlie shares mismatch");

        assertEq(token.balanceOf(alice), 0, "Alice should have 0 tokens after deposit");
        assertEq(token.balanceOf(bob), 0, "Bob should have 0 tokens after deposit");
        assertEq(token.balanceOf(charlie), 0, "Charlie should have 0 tokens after deposit");

        totalDepositedAssets = aliceDepositAmount + bobDepositAmount + charlieDepositAmount;
        console2.log("Total deposited assets:", totalDepositedAssets);

        uint256 morphoShares = morphoVault.balanceOf(address(vault));
        uint256 expectedMorphoShares = morphoVault.convertToShares(totalDepositedAssets);
        assertApproxEqAbs(morphoShares, expectedMorphoShares, 2, "Morpho shares mismatch");
    }

    function _phaseProfitInjection(VaultTestConfig memory config) internal {
        console2.log("\n=== PHASE 2: PROFIT INJECTION ===");

        profitAmount = config.decimals == 6 ? 50_000_000e6 : 50_000e18;
        _injectProfit(config, profitAmount);

        uint256 totalAssetsAfterProfit = vault.totalAssets();
        console2.log("Total assets after profit:", totalAssetsAfterProfit);
        console2.log("Profit injected:", profitAmount);
    }

    function _phasePartialWithdrawal(VaultTestConfig memory config) internal {
        console2.log("\n=== PHASE 3: PARTIAL WITHDRAWAL ===");

        IERC20 token = IERC20(config.token);

        uint256 aliceTokenBalanceBefore = token.balanceOf(alice);
        uint256 aliceSharesBeforeWithdraw = vault.balanceOf(alice);

        aliceWithdrawAmount = vault.maxWithdraw(alice) / 2;
        uint256 aliceSharesBurned = _withdraw(alice, aliceWithdrawAmount);

        console2.log("Alice withdrew:", aliceWithdrawAmount, "burned shares:", aliceSharesBurned);

        uint256 aliceTokenBalanceAfter = token.balanceOf(alice);
        assertEq(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore, aliceWithdrawAmount, "Alice should receive withdrawn tokens"
        );

        aliceShares = vault.balanceOf(alice);
        assertEq(aliceSharesBeforeWithdraw - aliceShares, aliceSharesBurned, "Alice shares should be burned correctly");

        assertEq(token.balanceOf(bob), 0, "Bob token balance should be unchanged");
        assertEq(token.balanceOf(charlie), 0, "Charlie token balance should be unchanged");
    }

    function _phaseActivateEmergencyMode() internal {
        console2.log("\n=== PHASE 4: ACTIVATE EMERGENCY MODE ===");

        vm.prank(emergencyAdmin);
        vault.activateEmergencyMode();

        assertTrue(vault.emergencyMode(), "Emergency mode not activated");
        console2.log("Emergency mode activated");

        uint256 emergencyTotalAssets = vault.totalAssets();
        console2.log("Emergency total assets snapshot:", emergencyTotalAssets);
    }

    function _phaseEmergencyWithdrawal(VaultTestConfig memory config) internal {
        console2.log("\n=== PHASE 5: EMERGENCY WITHDRAWAL FROM MORPHO ===");

        IERC20 token = IERC20(config.token);

        uint256 vaultBalanceBeforeEmergencyWithdraw = token.balanceOf(address(vault));

        vm.prank(emergencyAdmin);
        uint256 recovered = vault.emergencyWithdraw();

        uint256 vaultBalanceAfterEmergencyWithdraw = token.balanceOf(address(vault));
        uint256 protocolBalanceAfter = vault.getProtocolBalance();

        console2.log("Recovered from protocol:", recovered);
        console2.log("Vault balance after emergency withdraw:", vaultBalanceAfterEmergencyWithdraw);
        console2.log("Protocol balance after emergency withdraw:", protocolBalanceAfter);

        uint256 expectedRecoveredAmount = totalDepositedAssets - aliceWithdrawAmount;
        assertApproxEqAbs(
            vaultBalanceAfterEmergencyWithdraw,
            expectedRecoveredAmount,
            10,
            "Vault balance should equal expected recovered amount"
        );

        assertApproxEqAbs(
            protocolBalanceAfter, 0, TOLERANCE, "Expected to recover all assets from Morpho (good liquidity)"
        );
    }

    function _phaseActivateRecovery(VaultTestConfig memory config) internal {
        console2.log("\n=== PHASE 6: ACTIVATE RECOVERY ===");

        IERC20 token = IERC20(config.token);

        uint256 declaredRecoverableAmount = token.balanceOf(address(vault));

        vm.prank(emergencyAdmin);
        vault.activateRecovery();

        assertTrue(vault.recoveryMode(), "Recovery mode not activated");

        uint256 recoveryAssets = vault.recoveryAssets();
        uint256 recoverySupply = vault.recoverySupply();

        console2.log("Recovery assets:", recoveryAssets);
        console2.log("Recovery supply:", recoverySupply);

        assertEq(recoveryAssets, declaredRecoverableAmount, "Recovery assets mismatch");
        uint256 expectedRecoverySupply = vault.totalSupply();
        assertApproxEqAbs(recoverySupply, expectedRecoverySupply, 2, "Recovery supply mismatch");
    }

    function _phaseUsersEmergencyRedeem(VaultTestConfig memory config) internal returns (uint256, uint256, uint256) {
        console2.log("\n=== PHASE 7: USERS EMERGENCY REDEEM ===");

        IERC20 token = IERC20(config.token);

        uint256 aliceSharesBeforeRedeem = vault.balanceOf(alice);
        uint256 bobSharesBeforeRedeem = vault.balanceOf(bob);
        uint256 charlieSharesBeforeRedeem = vault.balanceOf(charlie);

        uint256 aliceRedeemed = _emergencyRedeem(alice, aliceSharesBeforeRedeem);
        uint256 bobRedeemed = _emergencyRedeem(bob, bobSharesBeforeRedeem);
        uint256 charlieRedeemed = _emergencyRedeem(charlie, charlieSharesBeforeRedeem);

        console2.log("Alice redeemed:", aliceRedeemed);
        console2.log("Bob redeemed:", bobRedeemed);
        console2.log("Charlie redeemed:", charlieRedeemed);

        assertEq(vault.balanceOf(alice), 0, "Alice shares should be burned");
        assertEq(vault.balanceOf(bob), 0, "Bob shares should be burned");
        assertEq(vault.balanceOf(charlie), 0, "Charlie shares should be burned");

        return (aliceRedeemed, bobRedeemed, charlieRedeemed);
    }

    function _phaseTreasuryRedeemFees(VaultTestConfig memory config) internal returns (uint256) {
        console2.log("\n=== PHASE 8: TREASURY REDEEMS FEES ===");

        IERC20 token = IERC20(config.token);

        uint256 treasuryShares = vault.balanceOf(treasury);
        uint256 treasuryRedeemed = 0;

        console2.log("Treasury shares before redeem:", treasuryShares);

        if (treasuryShares > 0) {
            treasuryRedeemed = _emergencyRedeem(treasury, treasuryShares);
            console2.log("Treasury redeemed:", treasuryRedeemed);
            assertEq(vault.balanceOf(treasury), 0, "Treasury shares should be burned");
        } else {
            console2.log("Treasury has no shares (no fees harvested)");
        }

        return treasuryRedeemed;
    }

    function _phaseComprehensiveValidation(
        VaultTestConfig memory config,
        uint256 aliceRedeemed,
        uint256 bobRedeemed,
        uint256 charlieRedeemed,
        uint256 treasuryRedeemed
    ) internal {
        console2.log("\n=== PHASE 9: COMPREHENSIVE VALIDATION ===");

        IERC20 token = IERC20(config.token);

        assertEq(vault.totalSupply(), 0, "All shares should be burned");
        console2.log("CHECK PASSED: All shares burned");

        uint256 remainingBalance = token.balanceOf(address(vault));
        assertApproxEqAbs(remainingBalance, 0, TOLERANCE, "Vault should be drained");

        uint256 totalTokensDistributed = token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(charlie);
        if (vault.balanceOf(treasury) == 0 && treasuryRedeemed > 0) {
            totalTokensDistributed += token.balanceOf(treasury);
        }

        assertApproxEqAbs(
            totalTokensDistributed, totalDepositedAssets, 10, "Total distributed should approximately match total deposited"
        );

        uint256 recoveryAssets = vault.recoveryAssets();
        uint256 totalDistributed = aliceRedeemed + bobRedeemed + charlieRedeemed + treasuryRedeemed;
        assertApproxEqAbs(totalDistributed, recoveryAssets, 10, "Total distribution should match recovery assets");

        console2.log("CHECK PASSED: All validations complete");
    }

    /// @notice Executes a full deposit, profit, withdrawal, and emergency cycle against each configured mainnet vault.
    /// @dev Verifies live integrations handle deposits, profit accounting, emergency withdraw, and recovery redemption without balance drift.
    function test_FullEmergencyCycle_AllVaults() public {
        _forkMainnet();

        VaultTestConfig[] memory configs = VaultTestConfigs.allConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            VaultTestConfig memory config = configs[i];
            console2.log("\n========================================");
            console2.log("Testing vault:", config.name);
            console2.log("========================================");

            _deployVault(config);
            _setupUsers(config);

            _phaseMultiUserDeposits(config);
            _phaseProfitInjection(config);
            _phasePartialWithdrawal(config);
            _phaseActivateEmergencyMode();
            _phaseEmergencyWithdrawal(config);
            _phaseActivateRecovery(config);

            (uint256 aliceRedeemed, uint256 bobRedeemed, uint256 charlieRedeemed) = _phaseUsersEmergencyRedeem(config);
            uint256 treasuryRedeemed = _phaseTreasuryRedeemFees(config);

            _phaseComprehensiveValidation(config, aliceRedeemed, bobRedeemed, charlieRedeemed, treasuryRedeemed);

            console2.log("\n=== EMERGENCY CYCLE COMPLETE ===");
            console2.log("All validations passed successfully for", config.name);
        }

        console2.log("\n========================================");
        console2.log("All vaults tested successfully");
        console2.log("========================================");
    }
}
