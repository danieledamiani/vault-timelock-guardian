// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GuardedVaultV1} from "../GuardedVaultV1.sol";

/// @title VaultTimelockProxyDeployer
/// @notice Atomically deploys a GuardedVaultV1 behind an ERC1967 proxy + TimelockController
/// @dev Same ownership handoff pattern as VaultTimelockDeployer, but with a proxy in front.
///
/// The handoff sequence:
///   1. Deploy GuardedVaultV1 implementation (bare, no state)
///   2. Encode initialize() calldata
///   3. Deploy ERC1967Proxy pointing to implementation, calling initialize() atomically
///   4. Deploy TimelockController (proposer=admin_, executor=open)
///   5. Grant vault's OWNER_ROLE to the timelock
///   6. Grant GUARDIAN_ROLE to the guardian
///   7. renounceRole(OWNER_ROLE) — deployer removes itself
///
/// After deploy():
///   - The proxy IS the vault (all calls go through it)
///   - The timelock is the ONLY vault owner
///   - Upgrades must go through the timelock (OWNER_ROLE gates _authorizeUpgrade)
contract VaultTimelockProxyDeployer {
    /// @notice Deploy a proxied, timelocked vault system
    /// @param asset_ The underlying ERC-20 token for the vault
    /// @param name_ Vault share token name
    /// @param symbol_ Vault share token symbol
    /// @param admin_ Address that will be the timelock's PROPOSER
    /// @param guardian_ Address that will receive GUARDIAN_ROLE on the vault
    /// @param minDelay_ Minimum delay (in seconds) for timelocked operations
    /// @return vault The GuardedVaultV1 (proxy address, cast to the interface)
    /// @return timelock The deployed TimelockController
    function deploy(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address guardian_,
        uint256 minDelay_
    ) external returns (GuardedVaultV1 vault, TimelockController timelock) {
        // The proxy constructor signature: ERC1967Proxy(address implementation, bytes memory _data)
        // When _data is non-empty, the proxy calls implementation.delegatecall(_data) during construction.

        // Step 1: deploy bare GuardedVaultV1
        GuardedVaultV1 implementation = new GuardedVaultV1();

        // Step 2: encode initialize() calldata
        bytes memory _data = abi.encodeCall(
            implementation.initialize,
            (asset_, name_, symbol_, address(this))
        );

        // Step 3: deploy ERC1967Proxy and cast it to GuardedVaultV1
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), _data);
        vault = GuardedVaultV1(address(proxy));

        // Step 4: Deploy TimelockController
        address[] memory proposers = new address[](1);
        proposers[0] = admin_;

        address[] memory executors = new address[](1);
        executors[0] = address(0); // open executor

        timelock = new TimelockController(
            minDelay_,
            proposers,
            executors,
            address(0) // no extra admin
        );

        // Step 5: Grant OWNER_ROLE on the vault to the timelock
        vault.grantRole(vault.OWNER_ROLE(), address(timelock));

        // Step 6: Grant GUARDIAN_ROLE to the guardian
        vault.grantGuardian(guardian_);

        // Step 7: Renounce OWNER_ROLE — the deployer removes itself
        vault.renounceRole(vault.OWNER_ROLE(), address(this));

        return (vault, timelock);
    }
}
