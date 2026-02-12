// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GuardedVault} from "../GuardedVault.sol";

/// @title VaultTimelockDeployer
/// @notice Atomically deploys a GuardedVault + TimelockController with safe ownership handoff
/// @dev The deployer is a temporary owner that transfers control and removes itself in one tx.
///
/// The handoff sequence (5 steps):
///   1. Deploy GuardedVault with THIS contract as temporary owner
///   2. Deploy TimelockController (proposer=admin_, executor=open, no extra admin)
///   3. Grant vault's OWNER_ROLE to the timelock address
///   4. Grant GUARDIAN_ROLE directly to guardian address
///   5. renounceRole(OWNER_ROLE) — deployer irreversibly removes itself
///
/// Why renounceRole works:
///   VaultAccessControl overrides grantRole/revokeRole with isOwner(msg.sender) checks,
///   but does NOT override renounceRole. OZ's base renounceRole (AccessControl.sol)
///   calls _revokeRole directly, bypassing the custom check.
///
/// After deploy():
///   - The timelock is the ONLY vault owner
///   - The admin_ address is the timelock's PROPOSER (can schedule operations)
///   - Anyone can execute operations after delay (open EXECUTOR_ROLE)
///   - The deployer contract has NO remaining privileges
contract VaultTimelockDeployer {
    /// @notice Deploy a timelocked vault system
    /// @param asset_ The underlying ERC-20 token for the vault
    /// @param name_ Vault share token name
    /// @param symbol_ Vault share token symbol
    /// @param admin_ Address that will be the timelock's PROPOSER (typically a multisig)
    /// @param guardian_ Address that will receive GUARDIAN_ROLE on the vault
    /// @param minDelay_ Minimum delay (in seconds) for timelocked operations
    /// @return vault The deployed GuardedVault
    /// @return timelock The deployed TimelockController
    function deploy(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address guardian_,
        uint256 minDelay_
    ) external returns (GuardedVault vault, TimelockController timelock) {
        // Step 1: Deploy GuardedVault with address(this) as the temporary owner
        vault = new GuardedVault(asset_, name_, symbol_, address(this));

        // Step 2: Deploy TimelockController
        address[] memory proposers = new address[](1);
        proposers[0] = admin_;

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new TimelockController(
            minDelay_,
            proposers,
            executors,
            address(0)
        );

        // Step 3: Grant OWNER_ROLE on the vault to the timelock
        vault.grantRole(vault.OWNER_ROLE(), address(timelock));

        // Step 4: Grant GUARDIAN_ROLE to the guardian address
        vault.grantGuardian(guardian_);

        // Step 5: Renounce OWNER_ROLE — the deployer removes itself
        vault.renounceRole(vault.OWNER_ROLE(), address(this));

        return (vault, timelock);
    }
}
