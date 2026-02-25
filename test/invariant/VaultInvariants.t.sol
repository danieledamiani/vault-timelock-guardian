// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GuardedVaultV1} from "../../src/GuardedVaultV1.sol";
import {VaultTimelockProxyDeployer} from "../../src/deploy/VaultTimelockProxyDeployer.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {VaultHandler} from "./handlers/VaultHandler.sol";

/// @title VaultInvariants
/// @notice Stateful fuzz (invariant) tests for GuardedVaultV1.
///
/// How Foundry invariant testing works:
///   1. setUp() runs once.
///   2. Foundry generates `runs` sequences, each up to `depth` calls long.
///      (See foundry.toml: runs=256, depth=15)
///   3. After EVERY call in a sequence, ALL invariant_* functions are checked.
///   4. If any assertion fails, Foundry reports the minimized call sequence.
///
///   targetContract(address) tells Foundry which contracts to call. We target
///   only the handler — never the vault directly — so all inputs are sanitized.
contract VaultInvariants is Test {
    VaultHandler public handler;
    GuardedVaultV1 public vault;
    MockERC20 public underlying;

    function setUp() public {
        underlying = new MockERC20("USD Coin", "USDC", 18);

        VaultTimelockProxyDeployer deployer = new VaultTimelockProxyDeployer();
        (vault, ) = deployer.deploy(
            IERC20(address(underlying)),
            "Guarded Vault",
            "gvUSDC",
            makeAddr("admin"),
            makeAddr("guardian"),
            1 days
        );

        handler = new VaultHandler(vault, underlying);

        // Only fuzz calls through the handler — keeps inputs valid and realistic
        targetContract(address(handler));
    }

    // ── Pre-implemented example ──────────────────────────────────────────────
    //
    // This invariant checks that the vault's share accounting is internally
    // consistent: the sum of all actor balances must equal totalSupply().
    // It would fail if any code path minted or burned shares incorrectly.

    /// @notice totalSupply() == sum of all actor share balances
    function invariant_shareAccounting_totalSupplyMatchesActors()
        external
        view
    {
        address[3] memory actors = [
            address(0x1001),
            address(0x1002),
            address(0x1003)
        ];
        uint256 actorShareSum = vault.balanceOf(actors[0]) +
            vault.balanceOf(actors[1]) +
            vault.balanceOf(actors[2]);

        assertEq(vault.totalSupply(), actorShareSum);
    }

    /// @notice totalAssets() is a view wrapper around balanceOf — verify it matches reality.
    ///
    /// If this breaks: the vault's totalAssets() implementation has drifted from the
    /// actual token balance (e.g. a bug updates totalAssets() but forgets the real transfer).
    function invariant_totalAssets_matchesBalance() external view {
        assertEq(vault.totalAssets(), underlying.balanceOf(address(vault)));
    }

    /// @notice Rounding always favors the vault, never the actor.
    ///         Actors should never collectively receive MORE assets than they deposited.
    ///
    /// Why this holds: on every deposit, actors get slightly FEWER shares than the
    /// "fair" amount (rounded down). On every redeem, they get slightly FEWER assets
    /// (rounded down). Both effects leave dust in the vault. The accumulation means
    /// assets out can never exceed assets in — even across arbitrary call sequences.
    function invariant_rounding_favorsVault() external view {
        // assert that total assets ever returned to actors is never more than
        // total assets ever deposited.
        // Hint: which comparison operator expresses "never more than"?
        uint256 deposited = handler.ghost_depositSum();
        uint256 redeemed = handler.ghost_redeemSum();

        assertLe(redeemed, deposited);
    }
}
