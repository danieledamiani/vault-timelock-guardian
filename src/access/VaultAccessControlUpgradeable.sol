// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title VaultAccessControlUpgradeable
/// @notice Upgradeable version of VaultAccessControl for use behind a proxy
/// @dev Replaces constructor with __VaultAccessControl_init(owner_), reserves storage with __gap
abstract contract VaultAccessControlUpgradeable is AccessControlUpgradeable {
    // ============ Role Definitions ============

    bytes32 public constant OWNER_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============ Events ============

    event EmergencyAction(address indexed guardian, string action);

    // ============ Errors ============

    error UnauthorizedRole(bytes32 role, address caller);
    error ActionNotAllowed(string reason);

    // ============ Initializer ============

    /// @dev Replaces the constructor. Grants OWNER_ROLE to the initial owner.
    function __VaultAccessControl_init(
        address owner_
    ) internal onlyInitializing {
        __AccessControl_init();
        __VaultAccessControl_init_unchained(owner_);
    }

    function __VaultAccessControl_init_unchained(
        address owner_
    ) internal onlyInitializing {
        if (owner_ == address(0))
            revert ActionNotAllowed("Owner cannot be zero address");
        _grantRole(OWNER_ROLE, owner_);
    }

    // ============ Role Management ============

    function grantGuardian(address guardian) external onlyRole(OWNER_ROLE) {
        if (guardian == address(0))
            revert ActionNotAllowed("Guardian cannot be zero address");
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    function revokeGuardian(address guardian) external onlyRole(OWNER_ROLE) {
        _revokeRole(GUARDIAN_ROLE, guardian);
    }

    function grantOperator(address operator) external onlyRole(OWNER_ROLE) {
        if (operator == address(0))
            revert ActionNotAllowed("Operator cannot be zero address");
        _grantRole(OPERATOR_ROLE, operator);
    }

    function revokeOperator(address operator) external onlyRole(OWNER_ROLE) {
        _revokeRole(OPERATOR_ROLE, operator);
    }

    // ============ Role Checks ============

    function isOwner(address account) public view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    function isGuardian(address account) public view returns (bool) {
        return hasRole(GUARDIAN_ROLE, account);
    }

    function isOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    // ============ Security Overrides ============

    function grantRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        if (!isOwner(msg.sender)) {
            revert ActionNotAllowed("Only owner can grant roles");
        }
        _grantRole(role, account);
    }

    function revokeRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        if (!hasRole(OWNER_ROLE, msg.sender)) {
            revert ActionNotAllowed("Only owner can revoke roles");
        }
        _revokeRole(role, account);
    }

    // ============ Storage Gap ============

    /// @dev Reserves 50 storage slots for future upgrades.
    /// This contract adds no new state variables beyond AccessControlUpgradeable,
    /// so the full 50 slots are reserved.
    uint256[50] private __gap;
}
