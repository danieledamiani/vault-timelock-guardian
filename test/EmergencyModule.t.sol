// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {GuardedVault} from "../src/GuardedVault.sol";
import {EmergencyModule} from "../src/EmergencyModule.sol";
import {VaultAccessControl} from "../src/access/VaultAccessControl.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title EmergencyModuleTest
/// @notice Tests for emergency state machine and vault operation blocking
contract EmergencyModuleTest is Test {
    GuardedVault public vault;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public guardian = makeAddr("guardian");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 10_000e18;

    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST", 18);

        // Deploy guarded vault
        vault = new GuardedVault(
            IERC20(address(token)),
            "Guarded Vault Token",
            "gvTEST",
            owner
        );

        // Setup roles
        vm.prank(owner);
        vault.grantGuardian(guardian);

        // Fund users
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);

        // Approve vault
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // ============ Initial State Tests ============

    function test_InitialState_IsNormal() public view {
        assertTrue(vault.isNormal());
        assertFalse(vault.isPaused());
        assertFalse(vault.isWithdrawOnly());
        assertEq(
            uint256(vault.emergencyState()),
            uint256(EmergencyModule.EmergencyState.NORMAL)
        );
    }

    // ============ Pause Tests ============

    function test_Pause_GuardianCanPause() public {
        vm.prank(guardian);
        vault.pause();

        assertTrue(vault.isPaused());
        assertFalse(vault.isNormal());
    }

    function test_Pause_OwnerCanPause() public {
        // Owner also has guardian role implicitly through DEFAULT_ADMIN
        // But actually in our design, owner needs to be granted guardian role
        // Let's check if owner can pause through the guardian role
        vm.prank(owner);
        vault.grantGuardian(owner);

        vm.prank(owner);
        vault.pause();

        assertTrue(vault.isPaused());
    }

    function test_Pause_RevertsForRandomUser() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    function test_Pause_RevertsIfAlreadyPaused() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.InvalidStateTransition.selector,
                EmergencyModule.EmergencyState.PAUSED,
                EmergencyModule.EmergencyState.PAUSED,
                "Already paused"
            )
        );
        vault.pause();
    }

    function test_Pause_EmitsEvent() public {
        vm.prank(guardian);
        vm.expectEmit(true, true, true, true);
        emit EmergencyModule.EmergencyStateChanged(
            EmergencyModule.EmergencyState.NORMAL,
            EmergencyModule.EmergencyState.PAUSED,
            guardian
        );
        vault.pause();
    }

    // ============ Unpause Tests ============

    function test_Unpause_OwnerCanUnpause() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(owner);
        vault.unpause();

        assertTrue(vault.isNormal());
        assertFalse(vault.isPaused());
    }

    function test_Unpause_GuardianCannotUnpause() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(guardian);
        vm.expectRevert(); // AccessControl error
        vault.unpause();
    }

    function test_Unpause_RevertsIfAlreadyNormal() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.InvalidStateTransition.selector,
                EmergencyModule.EmergencyState.NORMAL,
                EmergencyModule.EmergencyState.NORMAL,
                "Already normal"
            )
        );
        vault.unpause();
    }

    function test_Unpause_FromWithdrawOnly() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();
        assertTrue(vault.isWithdrawOnly());

        vm.prank(owner);
        vault.unpause();
        assertTrue(vault.isNormal());
    }

    // ============ Withdraw-Only Tests ============

    function test_WithdrawOnly_GuardianCanSet() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();

        assertTrue(vault.isWithdrawOnly());
        assertFalse(vault.isNormal());
        assertFalse(vault.isPaused());
    }

    function test_WithdrawOnly_RevertsForRandomUser() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setWithdrawOnly();
    }

    function test_WithdrawOnly_RevertsFromPaused() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.InvalidStateTransition.selector,
                EmergencyModule.EmergencyState.PAUSED,
                EmergencyModule.EmergencyState.WITHDRAW_ONLY,
                "Can only set withdraw-only from normal"
            )
        );
        vault.setWithdrawOnly();
    }

    function test_WithdrawOnly_EmitsEvent() public {
        vm.prank(guardian);
        vm.expectEmit(true, true, true, true);
        emit EmergencyModule.EmergencyStateChanged(
            EmergencyModule.EmergencyState.NORMAL,
            EmergencyModule.EmergencyState.WITHDRAW_ONLY,
            guardian
        );
        vault.setWithdrawOnly();
    }

    // ============ Operation Blocking - PAUSED State ============

    function test_Paused_BlocksDeposit() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.OperationNotAllowed.selector,
                EmergencyModule.EmergencyState.PAUSED,
                "deposit/mint"
            )
        );
        vault.deposit(1000e18, alice);
    }

    function test_Paused_BlocksMint() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.OperationNotAllowed.selector,
                EmergencyModule.EmergencyState.PAUSED,
                "deposit/mint"
            )
        );
        vault.mint(1000e18, alice);
    }

    function test_Paused_BlocksWithdraw() public {
        // First deposit
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        // Pause
        vm.prank(guardian);
        vault.pause();

        // Try to withdraw
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.OperationNotAllowed.selector,
                EmergencyModule.EmergencyState.PAUSED,
                "withdraw/redeem"
            )
        );
        vault.withdraw(500e18, alice, alice);
    }

    function test_Paused_BlocksRedeem() public {
        // First deposit
        vm.prank(alice);
        vault.deposit(1000e18, alice);
        uint256 shares = vault.balanceOf(alice);

        // Pause
        vm.prank(guardian);
        vault.pause();

        // Try to redeem
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.OperationNotAllowed.selector,
                EmergencyModule.EmergencyState.PAUSED,
                "withdraw/redeem"
            )
        );
        vault.redeem(shares, alice, alice);
    }

    // ============ Operation Blocking - WITHDRAW_ONLY State ============

    function test_WithdrawOnly_BlocksDeposit() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.OperationNotAllowed.selector,
                EmergencyModule.EmergencyState.WITHDRAW_ONLY,
                "deposit/mint"
            )
        );
        vault.deposit(1000e18, alice);
    }

    function test_WithdrawOnly_BlocksMint() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyModule.OperationNotAllowed.selector,
                EmergencyModule.EmergencyState.WITHDRAW_ONLY,
                "deposit/mint"
            )
        );
        vault.mint(1000e18, alice);
    }

    function test_WithdrawOnly_AllowsWithdraw() public {
        // First deposit
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        // Set withdraw-only
        vm.prank(guardian);
        vault.setWithdrawOnly();

        // Should still be able to withdraw
        vm.prank(alice);
        vault.withdraw(500e18, alice, alice);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 500e18);
    }

    function test_WithdrawOnly_AllowsRedeem() public {
        // First deposit
        vm.prank(alice);
        vault.deposit(1000e18, alice);
        uint256 shares = vault.balanceOf(alice);

        // Set withdraw-only
        vm.prank(guardian);
        vault.setWithdrawOnly();

        // Should still be able to redeem
        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
    }

    // ============ Max Functions (ERC-4626 Compliance) ============

    function test_MaxDeposit_ReturnsZeroWhenPaused() public {
        vm.prank(guardian);
        vault.pause();

        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_MaxDeposit_ReturnsZeroWhenWithdrawOnly() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();

        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_MaxMint_ReturnsZeroWhenPaused() public {
        vm.prank(guardian);
        vault.pause();

        assertEq(vault.maxMint(alice), 0);
    }

    function test_MaxMint_ReturnsZeroWhenWithdrawOnly() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();

        assertEq(vault.maxMint(alice), 0);
    }

    function test_MaxWithdraw_ReturnsZeroWhenPaused() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        vm.prank(guardian);
        vault.pause();

        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_MaxWithdraw_ReturnsNormalWhenWithdrawOnly() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        vm.prank(guardian);
        vault.setWithdrawOnly();

        // Should still report max withdraw amount
        assertGt(vault.maxWithdraw(alice), 0);
    }

    function test_MaxRedeem_ReturnsZeroWhenPaused() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        vm.prank(guardian);
        vault.pause();

        assertEq(vault.maxRedeem(alice), 0);
    }

    function test_MaxRedeem_ReturnsNormalWhenWithdrawOnly() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        vm.prank(guardian);
        vault.setWithdrawOnly();

        // Should still report max redeem amount
        assertGt(vault.maxRedeem(alice), 0);
    }

    // ============ State Transition Flow Tests ============

    function test_FullCycle_NormalToPausedToNormal() public {
        assertTrue(vault.isNormal());

        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.isPaused());

        vm.prank(owner);
        vault.unpause();
        assertTrue(vault.isNormal());
    }

    function test_FullCycle_NormalToWithdrawOnlyToNormal() public {
        assertTrue(vault.isNormal());

        vm.prank(guardian);
        vault.setWithdrawOnly();
        assertTrue(vault.isWithdrawOnly());

        vm.prank(owner);
        vault.unpause();
        assertTrue(vault.isNormal());
    }

    function test_Transition_WithdrawOnlyToPaused() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();
        assertTrue(vault.isWithdrawOnly());

        // Guardian can pause from withdraw-only
        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.isPaused());
    }

    // ============ Fuzz Tests ============

    function testFuzz_DepositBlockedWhenNotNormal(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        // Test paused
        vm.prank(guardian);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(amount, alice);

        // Unpause, then set withdraw-only
        vm.prank(owner);
        vault.unpause();
        vm.prank(guardian);
        vault.setWithdrawOnly();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(amount, alice);
    }

    function testFuzz_WithdrawAllowedInWithdrawOnly(
        uint256 depositAmount
    ) public {
        depositAmount = bound(depositAmount, 1e18, INITIAL_BALANCE);

        // Deposit first
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Set withdraw-only
        vm.prank(guardian);
        vault.setWithdrawOnly();

        // Should be able to withdraw any amount up to balance
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        vm.prank(alice);
        vault.withdraw(maxWithdraw, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
    }

    // ============ Security Property Tests ============

    /// @notice Guardian cannot unpause - this is critical for security
    function test_Security_GuardianCannotEscalateByUnpausing() public {
        vm.prank(guardian);
        vault.pause();

        // Guardian tries to unpause - should fail
        vm.prank(guardian);
        vm.expectRevert();
        vault.unpause();

        // Vault should still be paused
        assertTrue(vault.isPaused());
    }

    /// @notice Even if guardian is also operator, still cannot unpause
    function test_Security_MultiRoleGuardianCannotUnpause() public {
        // Grant operator role to guardian
        vm.prank(owner);
        vault.grantOperator(guardian);

        vm.prank(guardian);
        vault.pause();

        // Still cannot unpause
        vm.prank(guardian);
        vm.expectRevert();
        vault.unpause();
    }
}
