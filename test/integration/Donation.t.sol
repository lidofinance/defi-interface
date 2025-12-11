// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "test/unit/erc4626-adapter/ERC4626AdapterTestBase.sol";
import "forge-std/console.sol";

/**
 * @title DonationTest
 * @notice Integration tests for donation scenarios where external parties donate target vault shares
 * @dev Tests the flow where someone deposits directly into target vault and transfers shares to our vault
 */
contract DonationTest is ERC4626AdapterTestBase {
    using Math for uint256;

    address public user1;
    address public user2;
    address public user3;
    address public donor;

    uint256 public user1Deposit;
    uint256 public user2Deposit;
    uint256 public user3Deposit;
    uint256 public totalDeposited;
    uint256 public targetVaultProfit;
    uint256 public donatedUSDC;

    function setUp() public override {
        super.setUp();

        // Create 3 users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        donor = makeAddr("donor");

        // Give users and donor initial balances
        _dealAndApprove(user1, 100_000e6);
        _dealAndApprove(user2, 150_000e6);
        _dealAndApprove(user3, 200_000e6);
        _dealAndApprove(donor, 500_000e6);

        // Set common test values
        user1Deposit = 50_000e6;
        user2Deposit = 100_000e6;
        user3Deposit = 150_000e6;
        targetVaultProfit = 30_000e6;
        donatedUSDC = 50_000e6;
    }

    function _setupUsersDeposit() internal {
        vm.prank(user1);
        vault.deposit(user1Deposit, user1);

        vm.prank(user2);
        vault.deposit(user2Deposit, user2);

        vm.prank(user3);
        vault.deposit(user3Deposit, user3);

        totalDeposited = user1Deposit + user2Deposit + user3Deposit;

        // Verify initial state
        assertEq(vault.totalAssets(), totalDeposited, "Total assets should equal deposits");
        assertEq(vault.balanceOf(treasury), 0, "Treasury should have no shares initially");
    }

    function _simulateTargetVaultProfit() internal {
        usdc.mint(address(targetVault), targetVaultProfit);

        uint256 expectedAssetsAfterProfit = totalDeposited + targetVaultProfit;
        assertApproxEqAbs(
            vault.totalAssets(), expectedAssetsAfterProfit, 1, "Total assets should include target vault profit"
        );
    }

    function _donorDonatesShares() internal returns (uint256 donatedSharesValue) {
        uint256 donorDepositAmount = 100_000e6;

        vm.startPrank(donor);
        usdc.approve(address(targetVault), donorDepositAmount);
        uint256 donorShares = targetVault.deposit(donorDepositAmount, donor);

        targetVault.transfer(address(vault), donorShares);
        vm.stopPrank();

        donatedSharesValue = targetVault.convertToAssets(donorShares);

        uint256 expectedAssetsAfterDonation = totalDeposited + targetVaultProfit + donatedSharesValue;

        assertApproxEqAbs(
            vault.totalAssets(),
            expectedAssetsAfterDonation,
            1,
            "Total assets should include donated shares value"
        );
    }

    function _harvestFeesAndVerify(uint256 totalProfit) internal returns (uint256 feeSharesMinted) {
        uint256 treasurySharesBefore = vault.balanceOf(treasury);
        uint256 totalSupplyBefore = vault.totalSupply();

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        uint256 totalSupplyAfter = vault.totalSupply();

        feeSharesMinted = treasurySharesAfter - treasurySharesBefore;

        assertGt(feeSharesMinted, 0, "Treasury should receive fee shares from profit");
        assertEq(totalSupplyAfter, totalSupplyBefore + feeSharesMinted, "Total supply should increase by fee shares");

        uint256 expectedFeeValue = (totalProfit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();
        uint256 actualFeeValue = vault.convertToAssets(feeSharesMinted);

        assertApproxEqAbs(actualFeeValue, expectedFeeValue, 2, "Fee value should be ~5% of total profit");
    }

    function _withdrawUser(address user, uint256 userDeposit, uint256 netProfitForUsers)
        internal
        returns (uint256 userAssets)
    {
        uint256 userExpectedProfit = (userDeposit * netProfitForUsers) / totalDeposited;
        uint256 userExpected = userDeposit + userExpectedProfit;

        uint256 userShares = vault.balanceOf(user);
        vm.prank(user);
        userAssets = vault.redeem(userShares, user, user);

        assertApproxEqAbs(userAssets, userExpected, 2, "User should get deposit + proportional profit");
    }

    function _withdrawTreasury(uint256 feeAmount) internal returns (uint256 treasuryAssets) {
        uint256 treasuryShares = vault.balanceOf(treasury);
        vm.prank(treasury);
        treasuryAssets = vault.redeem(treasuryShares, treasury, treasury);

        assertApproxEqAbs(treasuryAssets, feeAmount, 2, "Treasury should receive fee amount");
    }

    function _verifyUsersWithdrawal(uint256 totalProfit) internal {
        uint256 feeAmount = (totalProfit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();
        uint256 netProfitForUsers = totalProfit - feeAmount;

        uint256 user1Assets = _withdrawUser(user1, user1Deposit, netProfitForUsers);
        uint256 user2Assets = _withdrawUser(user2, user2Deposit, netProfitForUsers);
        uint256 user3Assets = _withdrawUser(user3, user3Deposit, netProfitForUsers);
        uint256 treasuryAssets = _withdrawTreasury(feeAmount);

        // Verify solvency
        uint256 totalWithdrawn = user1Assets + user2Assets + user3Assets + treasuryAssets;
        uint256 expectedTotal = totalDeposited + totalProfit;

        assertApproxEqAbs(totalWithdrawn, expectedTotal, 10, "Total withdrawn should equal deposits + profit");

        _logWithdrawals(user1Assets, user2Assets, user3Assets, treasuryAssets, feeAmount, totalProfit);
    }

    function _logWithdrawals(
        uint256 user1Assets,
        uint256 user2Assets,
        uint256 user3Assets,
        uint256 treasuryAssets,
        uint256 feeAmount,
        uint256 totalProfit
    ) internal view {
        console.log("=== DEPOSITS ===");
        console.log("User1 deposit:", user1Deposit);
        console.log("User2 deposit:", user2Deposit);
        console.log("User3 deposit:", user3Deposit);
        console.log("Total deposited:", totalDeposited);
        console.log("");
        console.log("=== PROFIT ===");
        console.log("Total profit:", totalProfit);
        console.log("Fee amount (5%):", feeAmount);
        console.log("Net profit for users:", totalProfit - feeAmount);
        console.log("");
        console.log("=== WITHDRAWALS ===");
        console.log("User1 withdrew:", user1Assets);
        console.log("User1 profit:", user1Assets - user1Deposit);
        console.log("User2 withdrew:", user2Assets);
        console.log("User2 profit:", user2Assets - user2Deposit);
        console.log("User3 withdrew:", user3Assets);
        console.log("User3 profit:", user3Assets - user3Deposit);
        console.log("Treasury withdrew:", treasuryAssets);
        console.log("");
        console.log("=== SOLVENCY ===");
        console.log("Total withdrawn:", user1Assets + user2Assets + user3Assets + treasuryAssets);
        console.log("Expected total:", totalDeposited + totalProfit);
        console.log("Vault remaining:", vault.totalAssets());
    }

    function _donateDirectAssets() internal {
        usdc.mint(address(vault), donatedUSDC);

        assertEq(usdc.balanceOf(address(vault)), donatedUSDC, "Vault should have idle USDC");

        uint256 expectedAssetsAfterProfit = totalDeposited + targetVaultProfit;
        assertApproxEqAbs(
            vault.totalAssets(),
            expectedAssetsAfterProfit,
            1,
            "Total assets should NOT include idle USDC in normal mode"
        );
    }

    function _recoverIdleAssets() internal {
        uint256 totalAssetsBefore = vault.totalAssets();

        vault.depositUnallocatedAssets();

        assertEq(usdc.balanceOf(address(vault)), 0, "Vault should have no idle USDC after recovery");

        uint256 totalAssetsAfter = vault.totalAssets();
        assertApproxEqAbs(
            totalAssetsAfter, totalAssetsBefore + donatedUSDC, 1, "Total assets should now include donated USDC"
        );
    }

    function _harvestFeesForRecoveredAssets(uint256 totalProfit) internal {
        uint256 treasurySharesBefore = vault.balanceOf(treasury);

        vault.harvestFees();

        uint256 treasurySharesAfter = vault.balanceOf(treasury);
        uint256 feeSharesMinted = treasurySharesAfter - treasurySharesBefore;

        uint256 expectedFeeValue = (totalProfit * vault.rewardFee()) / vault.MAX_BASIS_POINTS();
        uint256 actualFeeValue = vault.convertToAssets(feeSharesMinted);

        assertApproxEqAbs(
            actualFeeValue, expectedFeeValue, 2, "Fee should be calculated on total profit including donation"
        );
    }

    /**
     * @notice Tests that donated target vault shares are properly accounted as profit and trigger fee harvest
     * @dev Scenario:
     *      1. Three users deposit into vault
     *      2. Target vault generates profit (simulated by minting assets to target vault)
     *      3. External donor deposits directly into target vault and transfers shares to our vault
     *      4. harvestFees is called
     *      5. Treasury receives fee shares proportional to the total profit (including donation)
     */
    function test_Donation_SharesDonatedToVault() public {
        _setupUsersDeposit();
        _simulateTargetVaultProfit();
        uint256 donatedSharesValue = _donorDonatesShares();
        uint256 totalProfit = targetVaultProfit + donatedSharesValue;
        _harvestFeesAndVerify(totalProfit);
        _verifyUsersWithdrawal(totalProfit);
    }

    /**
     * @notice Tests that directly donated USDC (not target vault shares) requires manual recovery via depositUnallocatedAssets
     * @dev Scenario:
     *      1. Users deposit into vault
     *      2. Target vault generates profit
     *      3. Someone accidentally sends USDC directly to vault contract address
     *      4. Verify donated USDC is NOT included in totalAssets (ignored in normal mode)
     *      5. Manager calls depositUnallocatedAssets() to recover and deploy the donation
     *      6. Verify totalAssets now includes the donation
     *      7. Harvest fees and verify correct distribution
     */
    function test_Donation_DirectAssetDonation_RequiresManualRecovery() public {
        _setupUsersDeposit();
        _simulateTargetVaultProfit();
        _donateDirectAssets();
        _recoverIdleAssets();
        uint256 totalProfit = targetVaultProfit + donatedUSDC;
        _harvestFeesForRecoveredAssets(totalProfit);
        _verifyUsersWithdrawal(totalProfit);
    }
}
