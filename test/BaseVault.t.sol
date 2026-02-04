// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BaseVaultTest
/// @notice Tests for the minimal ERC-4626 vault
contract BaseVaultTest is Test {
    BaseVault public vault;
    MockERC20 public asset;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 10_000e18;

    function setUp() public {
        // Deploy underlying asset
        asset = new MockERC20("Mock USDC", "mUSDC", 18);

        // Deploy vault
        vault = new BaseVault(IERC20(address(asset)), "Vault USDC", "vUSDC");

        // Fund test accounts
        asset.mint(alice, INITIAL_BALANCE);
        asset.mint(bob, INITIAL_BALANCE);

        // Approve vault to spend tokens
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsAsset() public view {
        assertEq(vault.asset(), address(asset));
    }

    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(vault.name(), "Vault USDC");
        assertEq(vault.symbol(), "vUSDC");
    }

    function test_Constructor_StartsEmpty() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    // ============ Deposit Tests ============

    function test_Deposit_MintsShares() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        // First deposit: 1:1 ratio (shares == assets)
        assertEq(sharesMinted, depositAmount);
        assertEq(vault.balanceOf(alice), depositAmount);
    }

    function test_Deposit_TransfersAssets() public {
        uint256 depositAmount = 1000e18;
        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        assertEq(asset.balanceOf(alice), aliceBalanceBefore - depositAmount);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
    }

    function test_Deposit_UpdatesTotalAssets() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_Deposit_PreviewMatchesActual() public {
        uint256 depositAmount = 1000e18;

        uint256 previewedShares = vault.previewDeposit(depositAmount);

        vm.prank(alice);
        uint256 actualShares = vault.deposit(depositAmount, alice);

        assertEq(previewedShares, actualShares);
    }

    // ============ Mint Tests ============

    function test_Mint_TransfersCorrectAssets() public {
        uint256 sharesToMint = 1000e18;

        vm.prank(alice);
        uint256 assetsPaid = vault.mint(sharesToMint, alice);

        // First mint: 1:1 ratio
        assertEq(assetsPaid, sharesToMint);
        assertEq(vault.balanceOf(alice), sharesToMint);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw_ReturnsAssets() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        // Alice withdraws half
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(500e18, alice, alice);

        assertEq(sharesBurned, 500e18); // 1:1 ratio
        assertEq(asset.balanceOf(alice), aliceBalanceBefore + 500e18);
        assertEq(vault.balanceOf(alice), 500e18); // Half shares remain
    }

    // ============ Redeem Tests ============

    function test_Redeem_BurnsSharesReturnsAssets() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);

        // Alice redeems all shares
        vm.prank(alice);
        uint256 assetsReceived = vault.redeem(1000e18, alice, alice);

        assertEq(assetsReceived, 1000e18);
        assertEq(asset.balanceOf(alice), aliceBalanceBefore + 1000e18);
        assertEq(vault.balanceOf(alice), 0);
    }

    // ============ Round-trip Tests ============

    function test_RoundTrip_DepositAndRedeem() public {
        // 1. Record Alice's starting asset balance
        uint256 aliceInitialBalance = asset.balanceOf(alice);
        // 2. Alice deposits 1000e18 assets, store the shares received
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(1000e18, alice);
        assertEq(aliceShares, vault.balanceOf(alice));
        // 3. Alice redeems ALL her shares (use vault.balanceOf(alice) to get exact amount)
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        // 4. Record Alice's ending asset balance
        uint256 aliceFinalBalance = asset.balanceOf(alice);
        // 5. Assert that ending balance == starting balance
        assertEq(aliceInitialBalance, aliceFinalBalance);
        // This tests the "conservation of value" property - no value should be
        // created or destroyed in a simple round-trip when the vault is 1:1
    }

    // ============ Multi-user Tests ============

    function test_MultiUser_SharesAreProportional() public {
        // Alice deposits 1000
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        // Bob deposits 2000
        vm.prank(bob);
        vault.deposit(2000e18, bob);

        // Bob should have 2x Alice's shares
        assertEq(vault.balanceOf(bob), vault.balanceOf(alice) * 2);

        // Total should equal sum
        assertEq(
            vault.totalSupply(),
            vault.balanceOf(alice) + vault.balanceOf(bob)
        );
        assertEq(vault.totalAssets(), 3000e18);
    }

    function test_MultiUser_ProportionalWithdraw() public {
        // Both deposit
        vm.prank(alice);
        vault.deposit(1000e18, alice);
        vm.prank(bob);
        vault.deposit(2000e18, bob);

        // Alice withdraws everything
        // Note: get balance first, then prank, then call redeem
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceReceived = vault.redeem(aliceShares, alice, alice);

        // Alice should get her fair share (1/3 of pool = her original deposit)
        assertEq(aliceReceived, 1000e18);

        // Bob's shares still worth his original deposit
        assertEq(vault.previewRedeem(vault.balanceOf(bob)), 2000e18);
    }

    // ============ Fuzz Tests ============

    function testFuzz_Deposit_NeverMintsMoreThanExpected(
        uint256 amount
    ) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        uint256 preview = vault.previewDeposit(amount);

        vm.prank(alice);
        uint256 actual = vault.deposit(amount, alice);

        // Actual should never exceed preview (favor the vault)
        assertLe(actual, preview);
    }

    function testFuzz_Redeem_NeverReturnsMoreThanExpected(
        uint256 depositAmount
    ) public {
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);

        // Setup: deposit first
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 preview = vault.previewRedeem(shares);

        vm.prank(alice);
        uint256 actual = vault.redeem(shares, alice, alice);

        // Actual should never exceed preview (favor the vault)
        assertLe(actual, preview);
    }
}
