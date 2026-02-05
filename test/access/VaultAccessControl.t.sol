// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VaultAccessControl} from "../../src/access/VaultAccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title TestableVaultAccessControl
/// @notice Concrete implementation for testing the abstract VaultAccessControl
contract TestableVaultAccessControl is VaultAccessControl {
    constructor(address owner_) VaultAccessControl(owner_) {}

    /// @notice Test function that only owner can call
    function ownerOnlyAction()
        external
        view
        onlyRole(OWNER_ROLE)
        returns (bool)
    {
        return true;
    }

    /// @notice Test function that guardian can call
    function guardianAction() external onlyRole(GUARDIAN_ROLE) returns (bool) {
        emit EmergencyAction(msg.sender, "test_action");
        return true;
    }

    /// @notice Test function that operator can call
    function operatorAction()
        external
        view
        onlyRole(OPERATOR_ROLE)
        returns (bool)
    {
        return true;
    }
}

/// @title VaultAccessControlTest
/// @notice Tests for role-based access control
contract VaultAccessControlTest is Test {
    TestableVaultAccessControl public accessControl;

    address public owner = makeAddr("owner");
    address public guardian = makeAddr("guardian");
    address public operator = makeAddr("operator");
    address public alice = makeAddr("alice");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        // Deploy with owner
        accessControl = new TestableVaultAccessControl(owner);

        // Setup roles
        vm.startPrank(owner);
        accessControl.grantGuardian(guardian);
        accessControl.grantOperator(operator);
        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsOwner() public view {
        assertTrue(accessControl.isOwner(owner));
        assertTrue(accessControl.hasRole(accessControl.OWNER_ROLE(), owner));
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultAccessControl.ActionNotAllowed.selector,
                "Owner cannot be zero address"
            )
        );
        new TestableVaultAccessControl(address(0));
    }

    // ============ Role Assignment Tests ============

    function test_GrantGuardian_Success() public view {
        assertTrue(accessControl.isGuardian(guardian));
    }

    function test_GrantGuardian_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(); // AccessControl error
        accessControl.grantGuardian(alice);
    }

    function test_GrantOperator_Success() public view {
        assertTrue(accessControl.isOperator(operator));
    }

    function test_RevokeGuardian_Success() public {
        vm.prank(owner);
        accessControl.revokeGuardian(guardian);

        assertFalse(accessControl.isGuardian(guardian));
    }

    function test_RevokeOperator_Success() public {
        vm.prank(owner);
        accessControl.revokeOperator(operator);

        assertFalse(accessControl.isOperator(operator));
    }

    // ============ Role Permission Tests ============

    function test_OwnerCanCallOwnerOnlyAction() public {
        vm.prank(owner);
        bool result = accessControl.ownerOnlyAction();
        assertTrue(result);
    }

    function test_GuardianCannotCallOwnerOnlyAction() public {
        vm.prank(guardian);
        vm.expectRevert(); // AccessControl: account is missing role
        accessControl.ownerOnlyAction();
    }

    function test_GuardianCanCallGuardianAction() public {
        vm.prank(guardian);
        bool result = accessControl.guardianAction();
        assertTrue(result);
    }

    function test_OperatorCanCallOperatorAction() public {
        vm.prank(operator);
        bool result = accessControl.operatorAction();
        assertTrue(result);
    }

    function test_RandomUserCannotCallProtectedActions() public {
        vm.startPrank(alice);

        vm.expectRevert();
        accessControl.ownerOnlyAction();

        vm.expectRevert();
        accessControl.guardianAction();

        vm.expectRevert();
        accessControl.operatorAction();

        vm.stopPrank();
    }

    // ============ Guardian Restriction Tests ============

    /// @notice Guardian should NOT be able to grant roles to itself or others
    function test_GuardianCannotGrantRoles() public {
        vm.prank(guardian);
        vm.expectRevert(); // Should fail - guardian can't grant
        accessControl.grantGuardian(attacker);
    }

    /// @notice Guardian should NOT be able to grant operator role
    function test_GuardianCannotGrantOperator() public {
        vm.prank(guardian);
        vm.expectRevert();
        accessControl.grantOperator(attacker);
    }

    /// @notice Even with the raw grantRole function, guardian should fail
    function test_GuardianCannotUseRawGrantRole() public {
        // This is the critical test - even if guardian somehow gets access,
        // the grantRole override should block them

        // Get the role BEFORE setting up prank and expectRevert
        bytes32 guardianRole = accessControl.GUARDIAN_ROLE();

        vm.prank(guardian);
        vm.expectRevert(); // AccessControl will reject because guardian isn't admin
        accessControl.grantRole(guardianRole, attacker);
    }

    /// @notice Guardian should NOT be able to revoke roles
    function test_GuardianCannotRevokeRoles() public {
        vm.prank(guardian);
        vm.expectRevert();
        accessControl.revokeGuardian(guardian); // Try to revoke itself
    }

    // ============ Role Hierarchy Tests ============

    /// @notice Owner should be able to do everything
    function test_OwnerHasAllPowers() public {
        vm.startPrank(owner);

        // Can grant/revoke guardian
        accessControl.grantGuardian(alice);
        assertTrue(accessControl.isGuardian(alice));
        accessControl.revokeGuardian(alice);
        assertFalse(accessControl.isGuardian(alice));

        // Can grant/revoke operator
        accessControl.grantOperator(alice);
        assertTrue(accessControl.isOperator(alice));
        accessControl.revokeOperator(alice);
        assertFalse(accessControl.isOperator(alice));

        vm.stopPrank();
    }

    /// @notice Multiple guardians can exist
    function test_MultipleGuardians() public {
        vm.prank(owner);
        accessControl.grantGuardian(alice);

        assertTrue(accessControl.isGuardian(guardian));
        assertTrue(accessControl.isGuardian(alice));
    }

    // ============ Edge Cases ============

    function test_CannotGrantRoleToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultAccessControl.ActionNotAllowed.selector,
                "Guardian cannot be zero address"
            )
        );
        accessControl.grantGuardian(address(0));
    }

    function test_CannotGrantOperatorToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultAccessControl.ActionNotAllowed.selector,
                "Operator cannot be zero address"
            )
        );
        accessControl.grantOperator(address(0));
    }

    /// @notice Owner can renounce their own role (dangerous but allowed)
    function test_OwnerCanRenounceRole() public {
        bytes32 ownerRole = accessControl.OWNER_ROLE();

        vm.prank(owner);
        accessControl.renounceRole(ownerRole, owner);

        assertFalse(accessControl.isOwner(owner));
    }

    /// @notice After owner renounces, no one can grant roles
    function test_AfterOwnerRenounces_NoOneCanGrant() public {
        bytes32 ownerRole = accessControl.OWNER_ROLE();

        vm.prank(owner);
        accessControl.renounceRole(ownerRole, owner);

        // Now no one can grant guardian
        vm.prank(guardian);
        vm.expectRevert();
        accessControl.grantGuardian(attacker);
    }

    // ============ Event Tests ============

    function test_GuardianAction_EmitsEvent() public {
        vm.prank(guardian);
        vm.expectEmit(true, true, true, true);
        emit VaultAccessControl.EmergencyAction(guardian, "test_action");
        accessControl.guardianAction();
    }

    // ============ Fuzz Tests ============

    function testFuzz_OnlyOwnerCanGrantGuardian(
        address caller,
        address newGuardian
    ) public {
        vm.assume(caller != owner);
        vm.assume(newGuardian != address(0));

        vm.prank(caller);
        vm.expectRevert();
        accessControl.grantGuardian(newGuardian);
    }

    function testFuzz_OnlyOwnerCanGrantOperator(
        address caller,
        address newOperator
    ) public {
        vm.assume(caller != owner);
        vm.assume(newOperator != address(0));

        vm.prank(caller);
        vm.expectRevert();
        accessControl.grantOperator(newOperator);
    }
}
