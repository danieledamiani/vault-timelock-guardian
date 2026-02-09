// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GuardedVault} from "../src/GuardedVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @title GuardedVault Sweep Tests
/// @notice Tests for the token recovery (sweep) functionality
/// @dev Key security property: Cannot sweep the vault's underlying asset
contract GuardedVaultSweepTest is Test {
    // ============ State Variables ============

    GuardedVault public vault;
    MockERC20 public underlyingToken; // The vault's asset (e.g., USDC)
    MockERC20 public dustToken; // An accidentally-sent token (e.g., random airdrop)

    address public owner = makeAddr("owner");
    address public guardian = makeAddr("guardian");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");

    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant DUST_AMOUNT = 100e18;

    // ============ Setup ============

    function setUp() public {
        // Create the underlying token (what the vault holds)
        underlyingToken = new MockERC20("USD Coin", "USDC", 18);

        // Create a "dust" token (simulates accidental transfer)
        dustToken = new MockERC20("Random Airdrop", "AIRDROP", 18);

        // Deploy the guarded vault
        vault = new GuardedVault(
            IERC20(address(underlyingToken)),
            "Guarded Vault USDC",
            "gvUSDC",
            owner
        );

        // Setup: owner grants guardian and operator roles
        vm.startPrank(owner);
        vault.grantGuardian(guardian);
        vault.grantOperator(operator);
        vm.stopPrank();

        // Give user some underlying tokens for deposits
        underlyingToken.mint(user, INITIAL_BALANCE);

        // User deposits into vault (so vault has underlying tokens)
        vm.startPrank(user);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, user);
        vm.stopPrank();

        // Simulate accidental dust token transfer to vault
        dustToken.mint(address(vault), DUST_AMOUNT);
    }

    // ============ Basic Tests ============

    /// @notice Test that sweep recovers accidentally-sent tokens
    function test_Sweep_RecoversDustTokens() public {
        // Verify dust token is in vault
        assertEq(dustToken.balanceOf(address(vault)), DUST_AMOUNT);
        assertEq(dustToken.balanceOf(recipient), 0);

        // Owner sweeps dust tokens to recipient
        vm.prank(owner);
        vault.sweep(IERC20(address(dustToken)), recipient);

        // Verify tokens moved to recipient
        assertEq(dustToken.balanceOf(address(vault)), 0);
        assertEq(dustToken.balanceOf(recipient), DUST_AMOUNT);
    }

    /// @notice Test that sweep reverts when trying to sweep underlying asset
    function test_Sweep_RevertsForUnderlyingAsset() public {
        // This is the CRITICAL security test
        // Even the owner should not be able to sweep the underlying asset

        vm.prank(owner);
        vm.expectRevert(GuardedVault.CannotSweepUnderlyingAsset.selector);
        vault.sweep(IERC20(address(underlyingToken)), recipient);
    }

    /// @notice Test that sweep transfers the full token balance
    function test_Sweep_TransfersFullBalance() public {
        // Add more dust in multiple tranches
        dustToken.mint(address(vault), 50e18); // Now 150e18 total

        uint256 vaultBalance = dustToken.balanceOf(address(vault));
        assertEq(vaultBalance, 150e18);

        // Sweep should transfer ALL of it
        vm.prank(owner);
        vault.sweep(IERC20(address(dustToken)), recipient);

        // Verify complete transfer (both ends of the transaction)
        assertEq(dustToken.balanceOf(address(vault)), 0);
        assertEq(dustToken.balanceOf(recipient), 150e18);
    }

    // ============ Edge Cases & Security Tests ============

    /// @notice Test that guardian cannot sweep (access control)
    function test_Sweep_RevertsForGuardian() public {
        vm.prank(guardian);
        vm.expectRevert();
        vault.sweep(IERC20(address(dustToken)), recipient);
    }

    /// @notice Test that operator cannot sweep (access control)
    function test_Sweep_RevertsForOperator() public {
        vm.prank(operator);
        vm.expectRevert();
        vault.sweep(IERC20(address(dustToken)), recipient);
    }

    /// @notice Test that random user cannot sweep (access control)
    function test_Sweep_RevertsForRandomUser() public {
        address randomUser = makeAddr("randomUser");

        vm.prank(randomUser);
        vm.expectRevert();
        vault.sweep(IERC20(address(dustToken)), recipient);
    }

    /// @notice Test that sweeping zero balance doesn't revert
    /// @dev Important: sweeping a token with 0 balance should succeed (no-op)
    function test_Sweep_ZeroBalanceSucceeds() public {
        // Create a token that vault has ZERO of
        MockERC20 emptyToken = new MockERC20("Empty Token", "EMPTY", 18);

        assertEq(emptyToken.balanceOf(address(vault)), 0);

        // Should not revert - just transfers 0
        vm.prank(owner);
        vault.sweep(IERC20(address(emptyToken)), recipient);

        // Both should still be 0
        assertEq(emptyToken.balanceOf(address(vault)), 0);
        assertEq(emptyToken.balanceOf(recipient), 0);
    }

    /// @notice Test that Swept event is emitted correctly
    function test_Sweep_EmitsEvent() public {
        vm.prank(owner);

        // Expect the Swept event with correct parameters
        vm.expectEmit(true, true, false, true);
        emit GuardedVault.Swept(address(dustToken), recipient, DUST_AMOUNT);

        vault.sweep(IERC20(address(dustToken)), recipient);
    }

    /// @notice Test sweep with multiple different dust tokens
    function test_Sweep_MultipleDifferentTokens() public {
        // Create additional dust tokens
        MockERC20 airdrop2 = new MockERC20("Airdrop 2", "AIR2", 18);
        MockERC20 airdrop3 = new MockERC20("Airdrop 3", "AIR3", 6); // Different decimals

        // Mint to vault
        airdrop2.mint(address(vault), 500e18);
        airdrop3.mint(address(vault), 1000e6);

        // Sweep each token
        vm.startPrank(owner);
        vault.sweep(IERC20(address(dustToken)), recipient);
        vault.sweep(IERC20(address(airdrop2)), recipient);
        vault.sweep(IERC20(address(airdrop3)), recipient);
        vm.stopPrank();

        // Verify all swept
        assertEq(dustToken.balanceOf(recipient), DUST_AMOUNT);
        assertEq(airdrop2.balanceOf(recipient), 500e18);
        assertEq(airdrop3.balanceOf(recipient), 1000e6);
    }

    /// @notice Fuzz test: sweep works for any non-underlying token
    /// @dev Ensures sweep protection holds for random token addresses
    function testFuzz_Sweep_WorksForAnyNonUnderlyingToken(
        uint256 amount,
        address sweepRecipient
    ) public {
        // Bound inputs to valid ranges
        amount = bound(amount, 0, type(uint128).max);
        vm.assume(sweepRecipient != address(0));
        vm.assume(sweepRecipient != address(vault));

        // Create random dust token
        MockERC20 randomDust = new MockERC20("Random", "RND", 18);
        randomDust.mint(address(vault), amount);

        // Owner should be able to sweep it
        vm.prank(owner);
        vault.sweep(IERC20(address(randomDust)), sweepRecipient);

        assertEq(randomDust.balanceOf(address(vault)), 0);
        assertEq(randomDust.balanceOf(sweepRecipient), amount);
    }

    /// @notice Fuzz test: underlying asset protection holds for any amount
    function testFuzz_Sweep_AlwaysProtectsUnderlying(
        uint256 depositAmount
    ) public {
        // Bound to reasonable deposit range
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);

        // Create fresh vault and user for clean state
        MockERC20 freshToken = new MockERC20("Fresh USDC", "fUSDC", 18);
        GuardedVault freshVault = new GuardedVault(
            IERC20(address(freshToken)),
            "Fresh Vault",
            "fvUSDC",
            owner
        );

        // User deposits
        address freshUser = makeAddr("freshUser");
        freshToken.mint(freshUser, depositAmount);
        vm.startPrank(freshUser);
        freshToken.approve(address(freshVault), depositAmount);
        freshVault.deposit(depositAmount, freshUser);
        vm.stopPrank();

        // Owner tries to sweep underlying - should ALWAYS fail
        vm.prank(owner);
        vm.expectRevert(GuardedVault.CannotSweepUnderlyingAsset.selector);
        freshVault.sweep(IERC20(address(freshToken)), recipient);

        // User funds remain safe
        assertEq(freshToken.balanceOf(address(freshVault)), depositAmount);
    }

    /// @notice Test that sweep works during emergency states
    /// @dev Sweep should work even when paused - it's an admin recovery function
    function test_Sweep_WorksWhenPaused() public {
        // Pause the vault
        vm.prank(guardian);
        vault.pause();

        // Owner should still be able to sweep dust
        vm.prank(owner);
        vault.sweep(IERC20(address(dustToken)), recipient);

        assertEq(dustToken.balanceOf(recipient), DUST_AMOUNT);
    }

    /// @notice Test that sweep works in withdraw-only mode
    function test_Sweep_WorksWhenWithdrawOnly() public {
        // Set withdraw-only mode
        vm.prank(guardian);
        vault.setWithdrawOnly();

        // Owner should still be able to sweep dust
        vm.prank(owner);
        vault.sweep(IERC20(address(dustToken)), recipient);

        assertEq(dustToken.balanceOf(recipient), DUST_AMOUNT);
    }

    /// @notice Test underlying protection when user's vault shares exist
    /// @dev Ensures protection works regardless of share/asset ratio
    function test_Sweep_ProtectsUnderlyingWithActiveShares() public {
        // Verify vault has shares outstanding
        assertGt(vault.totalSupply(), 0);
        assertGt(vault.totalAssets(), 0);

        // Even with active shares, underlying is protected
        vm.prank(owner);
        vm.expectRevert(GuardedVault.CannotSweepUnderlyingAsset.selector);
        vault.sweep(IERC20(address(underlyingToken)), recipient);

        // User's deposit is safe
        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_BALANCE);
    }
}
