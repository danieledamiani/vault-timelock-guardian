// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title EmergencyModuleUpgradeable
/// @notice Upgradeable version of EmergencyModule for use behind a proxy
/// @dev Replaces constructor with __EmergencyModule_init(), reserves storage with __gap
/// @dev State machine: NORMAL <-> PAUSED, NORMAL <-> WITHDRAW_ONLY
abstract contract EmergencyModuleUpgradeable is Initializable {
    // ============ Types ============

    enum EmergencyState {
        NORMAL,
        PAUSED,
        WITHDRAW_ONLY
    }

    // ============ State ============

    EmergencyState private _emergencyState;

    // ============ Events ============

    event EmergencyStateChanged(
        EmergencyState indexed previousState,
        EmergencyState indexed newState,
        address indexed triggeredBy
    );

    // ============ Errors ============

    error OperationNotAllowed(EmergencyState currentState, string operation);

    error InvalidStateTransition(
        EmergencyState from,
        EmergencyState to,
        string reason
    );

    // ============ Initializer ============

    /// @dev Replaces the constructor. Can only be called during initialization.
    function __EmergencyModule_init() internal onlyInitializing {
        __EmergencyModule_init_unchained();
    }

    function __EmergencyModule_init_unchained() internal onlyInitializing {
        _emergencyState = EmergencyState.NORMAL;
    }

    // ============ State Queries ============

    function emergencyState() public view returns (EmergencyState) {
        return _emergencyState;
    }

    function isNormal() public view returns (bool) {
        return _emergencyState == EmergencyState.NORMAL;
    }

    function isPaused() public view returns (bool) {
        return _emergencyState == EmergencyState.PAUSED;
    }

    function isWithdrawOnly() public view returns (bool) {
        return _emergencyState == EmergencyState.WITHDRAW_ONLY;
    }

    // ============ Modifiers ============

    modifier whenNotPausedOrWithdrawOnly() {
        if (_emergencyState != EmergencyState.NORMAL) {
            revert OperationNotAllowed(_emergencyState, "deposit/mint");
        }
        _;
    }

    modifier whenWithdrawalsAllowed() {
        if (_emergencyState == EmergencyState.PAUSED) {
            revert OperationNotAllowed(_emergencyState, "withdraw/redeem");
        }
        _;
    }

    modifier whenNotPaused() {
        if (_emergencyState == EmergencyState.PAUSED) {
            revert OperationNotAllowed(_emergencyState, "operation");
        }
        _;
    }

    // ============ State Transitions ============

    function _pause() internal {
        EmergencyState previous = _emergencyState;
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

    function _setWithdrawOnly() internal {
        EmergencyState previous = _emergencyState;
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

    // ============ Storage Gap ============

    /// @dev Reserves 49 storage slots for future upgrades.
    /// We use 49 (not 50) because _emergencyState already occupies 1 slot.
    uint256[49] private __gap;
}
