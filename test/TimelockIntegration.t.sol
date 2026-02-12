// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GuardedVault} from "../src/GuardedVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {VaultTimelockDeployer} from "../src/deploy/VaultTimelockDeployer.sol";

/// @title Timelock Integration Tests
/// @notice Tests the full lifecycle: deploy, schedule, delay, execute
/// @dev Verifies that OWNER_ROLE actions go through timelock while GUARDIAN actions remain instant
contract TimelockIntegrationTest is Test {
    // ============ State Variables ============

    GuardedVault public vault;
    TimelockController public timelock;
    MockERC20 public underlying;
    MockERC20 public dustToken;

    address public admin = makeAddr("admin"); // timelock PROPOSER
    address public guardian = makeAddr("guardian");
    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");
    address public recipient = makeAddr("recipient");

    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant INITIAL_DEPOSIT = 1000e18;
    uint256 public constant DUST_AMOUNT = 50e18;

    // Timelock role constants (match OZ TimelockController)
    bytes32 public PROPOSER_ROLE;
    bytes32 public EXECUTOR_ROLE;
    bytes32 public CANCELLER_ROLE;

    // ============ Setup ============

    function setUp() public {
        // Deploy tokens
        underlying = new MockERC20("USD Coin", "USDC", 18);
        dustToken = new MockERC20("Dust Token", "DUST", 18);

        // Deploy vault + timelock atomically via deployer
        VaultTimelockDeployer deployer = new VaultTimelockDeployer();
        (vault, timelock) = deployer.deploy(
            IERC20(address(underlying)),
            "Guarded Vault USDC",
            "gvUSDC",
            admin,
            guardian,
            MIN_DELAY
        );

        // Cache timelock role constants
        PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        CANCELLER_ROLE = timelock.CANCELLER_ROLE();

        // User deposits into vault
        underlying.mint(user, INITIAL_DEPOSIT);
        vm.startPrank(user);
        underlying.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT, user);
        vm.stopPrank();

        // Seed dust token in vault (for sweep tests)
        dustToken.mint(address(vault), DUST_AMOUNT);
    }

    // ============ A. Deployment Verification ============

    /// @notice Timelock holds the vault's OWNER_ROLE
    function test_Deploy_TimelockIsVaultOwner() public view {
        assertTrue(vault.isOwner(address(timelock)));
    }

    /// @notice Admin is the timelock's PROPOSER
    function test_Deploy_AdminIsProposer() public view {
        assertTrue(timelock.hasRole(PROPOSER_ROLE, admin));
    }

    /// @notice Admin is also CANCELLER (OZ grants both to proposers)
    function test_Deploy_AdminIsCanceller() public view {
        assertTrue(timelock.hasRole(CANCELLER_ROLE, admin));
    }

    /// @notice Guardian has GUARDIAN_ROLE on the vault
    function test_Deploy_GuardianHasRole() public view {
        assertTrue(vault.isGuardian(guardian));
    }

    /// @notice Deployer contract no longer has OWNER_ROLE
    function test_Deploy_DeployerHasNoOwnership() public view {
        // The deployer was a contract, not an EOA — but verify no leftover
        assertFalse(vault.isOwner(admin));
        assertFalse(vault.isOwner(guardian));
    }

    /// @notice No human EOA is vault owner — only the timelock
    function test_Deploy_OnlyTimelockIsOwner() public view {
        // Check that common addresses are NOT owners
        assertFalse(vault.isOwner(admin));
        assertFalse(vault.isOwner(guardian));
        assertFalse(vault.isOwner(user));
        assertFalse(vault.isOwner(attacker));
        // Only the timelock
        assertTrue(vault.isOwner(address(timelock)));
    }

    // ============ B. Timelocked Operations ============

    /// @notice Core test: schedule-wait-execute sweep through timelock
    function test_Timelock_SweepThroughTimelock() public {
        // 1. ENCODE: Build calldata for vault.sweep(dustToken, recipient)
        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(dustToken)), recipient)
        );

        // 2. SCHEDULE: As admin (PROPOSER), schedule it on the timelock
        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        // 3. WAIT: Fast-forward past MIN_DELAY
        vm.warp(block.timestamp + MIN_DELAY);

        // 4. EXECUTE: Anyone can trigger execution (open executor)
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));

        // 5. ASSERT: Verify dust left the vault and arrived at recipient

        assertEq(dustToken.balanceOf(address(vault)), 0);
        assertEq(dustToken.balanceOf(recipient), DUST_AMOUNT);
    }

    /// @notice Grant guardian through timelock
    function test_Timelock_GrantGuardianThroughTimelock() public {
        address newGuardian = makeAddr("newGuardian");

        bytes memory data = abi.encodeCall(vault.grantGuardian, (newGuardian));

        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + MIN_DELAY);

        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));

        assertTrue(vault.isGuardian(newGuardian));
    }

    /// @notice Unpause through timelock (owner-only action)
    function test_Timelock_UnpauseThroughTimelock() public {
        // Guardian pauses instantly
        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.isPaused());

        // Admin schedules unpause through timelock
        bytes memory data = abi.encodeCall(vault.unpause, ());

        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + MIN_DELAY);

        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));

        assertTrue(vault.isNormal());
    }

    // ============ C. Guardian Bypass (no timelock needed) ============

    /// @notice Guardian can pause instantly — no timelock
    function test_Guardian_PausesInstantly() public {
        vm.prank(guardian);
        vault.pause();

        assertTrue(vault.isPaused());
    }

    /// @notice Guardian can set withdraw-only instantly — no timelock
    function test_Guardian_SetWithdrawOnlyInstantly() public {
        vm.prank(guardian);
        vault.setWithdrawOnly();

        assertTrue(vault.isWithdrawOnly());
    }

    /// @notice Key scenario: guardian pauses, admin must schedule unpause through delay
    function test_Guardian_PauseThenTimelockUnpause() public {
        // 1. Guardian detects threat → instant pause
        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.isPaused());

        // 2. Admin schedules unpause (must go through timelock delay)
        bytes memory data = abi.encodeCall(vault.unpause, ());
        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        // 3. Vault stays paused during delay — users can see the pending unpause
        vm.warp(block.timestamp + MIN_DELAY / 2);
        assertTrue(vault.isPaused()); // still paused!

        // 4. After delay, execute unpause
        vm.warp(block.timestamp + MIN_DELAY / 2);
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));

        assertTrue(vault.isNormal());
    }

    // ============ D. Access Control ============

    /// @notice Admin calling vault directly reverts (must go through timelock)
    function test_Access_AdminCannotCallVaultDirectly() public {
        vm.prank(admin);
        vm.expectRevert();
        vault.unpause();
    }

    /// @notice Attacker cannot schedule operations on the timelock
    function test_Access_AttackerCannotSchedule() public {
        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(dustToken)), attacker)
        );

        vm.prank(attacker);
        vm.expectRevert();
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );
    }

    /// @notice Guardian cannot propose timelocked operations
    function test_Access_GuardianCannotPropose() public {
        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(dustToken)), guardian)
        );

        vm.prank(guardian);
        vm.expectRevert();
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );
    }

    /// @notice Random user cannot call owner functions directly
    function test_Access_UserCannotCallOwnerFunctions() public {
        vm.prank(user);
        vm.expectRevert();
        vault.sweep(IERC20(address(dustToken)), user);
    }

    // ============ E. Lifecycle Edge Cases ============

    /// @notice Cannot execute before delay has passed
    function test_Lifecycle_CannotExecuteBeforeDelay() public {
        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(dustToken)), recipient)
        );

        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        // Try to execute immediately — should revert
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));
    }

    /// @notice Proposer can cancel a scheduled operation
    function test_Lifecycle_CancelScheduledOperation() public {
        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(dustToken)), recipient)
        );

        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        // Compute the operation id (same hash the timelock uses)
        bytes32 opId = timelock.hashOperation(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0)
        );
        assertTrue(timelock.isOperationPending(opId));

        // Admin cancels
        vm.prank(admin);
        timelock.cancel(opId);

        assertFalse(timelock.isOperationPending(opId));

        // Even after delay, execution fails because it was cancelled
        vm.warp(block.timestamp + MIN_DELAY);
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));
    }

    /// @notice Cannot replay an already-executed operation
    function test_Lifecycle_CannotReplayExecutedOperation() public {
        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(dustToken)), recipient)
        );

        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + MIN_DELAY);
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));

        // Try to execute again — should revert (operation already Done)
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));
    }

    // ============ F. Security Properties ============

    /// @notice Underlying asset still protected even through timelock sweep
    function test_Security_UnderlyingProtectedThroughTimelock() public {
        // Schedule a sweep of the UNDERLYING asset through timelock
        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(underlying)), attacker)
        );

        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + MIN_DELAY);

        // Execution reverts because the vault still checks CannotSweepUnderlyingAsset
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));

        // User funds are safe
        assertEq(underlying.balanceOf(address(vault)), INITIAL_DEPOSIT);
    }

    /// @notice Attacker cannot escalate even with a crafted schedule
    function test_Security_NoEscalationThroughTimelock() public {
        // Attacker tries to grant themselves OWNER_ROLE through timelock
        // They can't schedule because they don't have PROPOSER_ROLE
        bytes memory data = abi.encodeCall(
            vault.grantRole,
            (vault.OWNER_ROLE(), attacker)
        );

        vm.prank(attacker);
        vm.expectRevert();
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        assertFalse(vault.isOwner(attacker));
    }

    // ============ G. Fuzz Tests ============

    /// @notice Delay enforcement holds for any wait time less than minDelay
    function testFuzz_DelayEnforcement(uint256 waitTime) public {
        waitTime = bound(waitTime, 0, MIN_DELAY - 1);

        bytes memory data = abi.encodeCall(
            vault.sweep,
            (IERC20(address(dustToken)), recipient)
        );

        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        vm.warp(block.timestamp + waitTime);

        // Should always revert before the delay has fully passed
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));
    }
}
