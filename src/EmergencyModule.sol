// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title EmergencyModule
/// @notice Implements emergency state machine for vault operations
/// @dev Abstract contract - inherit and use modifiers to protect functions
/// @dev State machine: NORMAL ↔ PAUSED, NORMAL ↔ WITHDRAW_ONLY
///
/// Emergency States:
/// - NORMAL: All operations allowed (deposit, mint, withdraw, redeem)
/// - PAUSED: No operations allowed - full stop
/// - WITHDRAW_ONLY: Only withdrawals allowed (withdraw, redeem) - users can exit
///
/// Security Properties:
/// - Guardian can trigger emergency (pause, withdraw-only)
/// - Only Owner can return to NORMAL state
/// - Users can ALWAYS eventually withdraw (no permanent fund lock)
abstract contract EmergencyModule {
    // ============ Types ============

    /// @notice Emergency state enum
    /// @dev Using enum prevents invalid state combinations
    enum EmergencyState {
        NORMAL, // 0 - All operations allowed
        PAUSED, // 1 - No operations allowed
        WITHDRAW_ONLY // 2 - Only withdrawals allowed
    }

    // ============ State ============

    /// @notice Current emergency state
    EmergencyState private _emergencyState;

    // ============ Events ============

    /// @notice Emitted when emergency state changes
    /// @param previousState The state before the change
    /// @param newState The state after the change
    /// @param triggeredBy Address that triggered the change
    event EmergencyStateChanged(
        EmergencyState indexed previousState,
        EmergencyState indexed newState,
        address indexed triggeredBy
    );

    // ============ Errors ============

    /// @notice Thrown when operation is not allowed in current state
    error OperationNotAllowed(EmergencyState currentState, string operation);

    /// @notice Thrown when state transition is not allowed
    error InvalidStateTransition(
        EmergencyState from,
        EmergencyState to,
        string reason
    );

    // ============ Constructor ============

    constructor() {
        _emergencyState = EmergencyState.NORMAL;
    }

    // ============ State Queries ============

    /// @notice Returns the current emergency state
    function emergencyState() public view returns (EmergencyState) {
        return _emergencyState;
    }

    /// @notice Check if vault is in normal operating mode
    function isNormal() public view returns (bool) {
        return _emergencyState == EmergencyState.NORMAL;
    }

    /// @notice Check if vault is paused
    function isPaused() public view returns (bool) {
        return _emergencyState == EmergencyState.PAUSED;
    }

    /// @notice Check if vault is in withdraw-only mode
    function isWithdrawOnly() public view returns (bool) {
        return _emergencyState == EmergencyState.WITHDRAW_ONLY;
    }

    // ============ Modifiers ============

    /// @notice Ensures operation is allowed in current state
    /// @dev Use for deposit/mint operations
    modifier whenNotPausedOrWithdrawOnly() {
        if (_emergencyState != EmergencyState.NORMAL) {
            revert OperationNotAllowed(_emergencyState, "deposit/mint");
        }
        _;
    }

    /// @notice Ensures withdrawals are allowed
    /// @dev Use for withdraw/redeem operations - allowed in NORMAL and WITHDRAW_ONLY
    modifier whenWithdrawalsAllowed() {
        if (_emergencyState == EmergencyState.PAUSED) {
            revert OperationNotAllowed(_emergencyState, "withdraw/redeem");
        }
        _;
    }

    /// @notice Ensures vault is not paused (any operation)
    modifier whenNotPaused() {
        if (_emergencyState == EmergencyState.PAUSED) {
            revert OperationNotAllowed(_emergencyState, "operation");
        }
        _;
    }

    // ============ State Transitions ============

    /// @notice Pause all vault operations
    /// @dev Only callable by guardian (enforced by inheriting contract)
    function _pause() internal {
        EmergencyState previous = _emergencyState;

        // Can pause from NORMAL or WITHDRAW_ONLY
        if (previous == EmergencyState.PAUSED) {
            revert InvalidStateTransition(
                previous,
                EmergencyState.PAUSED,
                "Already paused"
            );
        }

        _emergencyState = EmergencyState.PAUSED;
        emit EmergencyStateChanged(previous, EmergencyState.PAUSED, msg.sender);
    }

    /// @notice Return to normal operations
    /// @dev Only callable by owner (enforced by inheriting contract)
    function _unpause() internal {
        EmergencyState previous = _emergencyState;

        if (previous == EmergencyState.NORMAL) {
            revert InvalidStateTransition(
                previous,
                EmergencyState.NORMAL,
                "Already normal"
            );
        }

        _emergencyState = EmergencyState.NORMAL;
        emit EmergencyStateChanged(previous, EmergencyState.NORMAL, msg.sender);
    }

    /// @notice Set withdraw-only mode
    /// @dev Only callable by guardian (enforced by inheriting contract)
    /// @dev Allows users to exit but prevents new deposits
    function _setWithdrawOnly() internal {
        EmergencyState previous = _emergencyState;

        // Can only set withdraw-only from NORMAL state
        // If paused, must unpause first (owner decision)
        if (previous != EmergencyState.NORMAL) {
            revert InvalidStateTransition(
                previous,
                EmergencyState.WITHDRAW_ONLY,
                "Can only set withdraw-only from normal"
            );
        }

        _emergencyState = EmergencyState.WITHDRAW_ONLY;
        emit EmergencyStateChanged(
            previous,
            EmergencyState.WITHDRAW_ONLY,
            msg.sender
        );
    }
}
