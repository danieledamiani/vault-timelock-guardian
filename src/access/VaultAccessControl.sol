// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title VaultAccessControl
/// @notice Role-based access control for the vault system
/// @dev Implements a hierarchy: OWNER > GUARDIAN > OPERATOR
/// @dev Key security property: Guardian has LIMITED powers (cannot grant roles or upgrade)
abstract contract VaultAccessControl is AccessControl {
    // ============ Role Definitions ============

    /// @notice Owner role - can configure governance and schedule privileged actions
    /// @dev The owner is the DEFAULT_ADMIN_ROLE, can grant/revoke all roles
    bytes32 public constant OWNER_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice Guardian role - can trigger emergency actions (pause, withdraw-only)
    /// @dev CANNOT: grant roles, upgrade contracts, or change fees
    /// @dev This reduces "blast radius" if guardian key is compromised
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// @notice Operator role - can perform routine operations
    /// @dev Optional role for day-to-day management tasks
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============ Events ============

    /// @notice Emitted when an emergency action is triggered by guardian
    event EmergencyAction(address indexed guardian, string action);

    // ============ Errors ============

    /// @notice Thrown when caller lacks required role
    error UnauthorizedRole(bytes32 role, address caller);

    /// @notice Thrown when trying to perform forbidden action
    error ActionNotAllowed(string reason);

    // ============ Constructor ============

    /// @param owner_ Initial owner address
    constructor(address owner_) {
        if (owner_ == address(0))
            revert ActionNotAllowed("Owner cannot be zero address");

        // Grant owner the admin role
        _grantRole(OWNER_ROLE, owner_);
    }

    // ============ Role Management ============

    /// @notice Grants guardian role to an address
    /// @dev Only callable by owner
    /// @param guardian Address to grant guardian role
    function grantGuardian(address guardian) external onlyRole(OWNER_ROLE) {
        if (guardian == address(0))
            revert ActionNotAllowed("Guardian cannot be zero address");
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    /// @notice Revokes guardian role from an address
    /// @dev Only callable by owner
    /// @param guardian Address to revoke guardian role from
    function revokeGuardian(address guardian) external onlyRole(OWNER_ROLE) {
        _revokeRole(GUARDIAN_ROLE, guardian);
    }

    /// @notice Grants operator role to an address
    /// @dev Only callable by owner
    /// @param operator Address to grant operator role
    function grantOperator(address operator) external onlyRole(OWNER_ROLE) {
        if (operator == address(0))
            revert ActionNotAllowed("Operator cannot be zero address");
        _grantRole(OPERATOR_ROLE, operator);
    }

    /// @notice Revokes operator role from an address
    /// @dev Only callable by owner
    /// @param operator Address to revoke operator role from
    function revokeOperator(address operator) external onlyRole(OWNER_ROLE) {
        _revokeRole(OPERATOR_ROLE, operator);
    }

    // ============ Role Checks ============

    /// @notice Checks if an address is an owner
    function isOwner(address account) public view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    /// @notice Checks if an address is a guardian
    function isGuardian(address account) public view returns (bool) {
        return hasRole(GUARDIAN_ROLE, account);
    }

    /// @notice Checks if an address is an operator
    function isOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    // ============ Security Overrides ============

    /// @notice Override to restrict role granting
    /// @dev Guardian and Operator CANNOT grant any roles, even if they somehow become admin
    /// @dev This is a defense-in-depth measure
    function grantRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        // Additional check: prevent guardians from granting roles even if they become admin
        if (!isOwner(msg.sender)) {
            revert ActionNotAllowed("Only owner can grant roles");
        }
        _grantRole(role, account);
    }

    /// @notice Override to restrict role revoking
    /// @dev Same defense-in-depth as grantRole
    function revokeRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        // Same check as grantRole - only OWNER can revoke
        if (!hasRole(OWNER_ROLE, msg.sender)) {
            revert ActionNotAllowed("Only owner can revoke roles");
        }
        _revokeRole(role, account);
    }
}
