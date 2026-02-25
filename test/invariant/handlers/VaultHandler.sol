// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {GuardedVaultV1} from "../../../src/GuardedVaultV1.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";

/// @title VaultHandler
/// @notice Wraps vault interactions for invariant testing.
///
/// Why a handler?
///   If we fuzz the vault directly, Foundry would call deposit() with random addresses
///   that have no tokens — almost every call reverts, and the fuzzer learns nothing.
///   The handler "sanitizes" inputs: it bounds amounts to valid ranges, mints tokens
///   to actors before depositing, and manages approvals. This lets the fuzzer explore
///   a rich space of realistic call sequences.
///
/// Ghost variables:
///   The vault contract doesn't store "how much was ever deposited in total" — that's
///   not needed for the vault's logic. But WE need it to verify accounting invariants
///   across sequences of calls. Ghost variables live in the handler and shadow the
///   vault's internal flows.
contract VaultHandler is CommonBase, StdCheats, StdUtils {
    GuardedVaultV1 public vault;
    MockERC20 public underlying;

    // Fixed pool of actors. Three actors is enough to test multi-user
    // interactions (dilution, share price changes between users, etc.)
    // while keeping the state space manageable.
    address[] public actors;

    // ── Ghost variables ───────────────────────────────────────────────
    // Track net asset flows across ALL calls in a sequence.
    uint256 public ghost_depositSum; // total underlying ever deposited
    uint256 public ghost_redeemSum; // total underlying ever returned on redemption

    constructor(GuardedVaultV1 _vault, MockERC20 _underlying) {
        vault = _vault;
        underlying = _underlying;

        actors.push(address(0x1001));
        actors.push(address(0x1002));
        actors.push(address(0x1003));
    }

    /// @notice Deposit assets into the vault on behalf of a randomly selected actor.
    ///         `actorSeed` lets the fuzzer vary which actor calls — tests multi-user scenarios.
    function deposit(uint256 assets, uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        assets = bound(assets, 1, 1_000_000e18);

        // Give the actor fresh tokens so the deposit is always valid
        underlying.mint(actor, assets);

        vm.startPrank(actor);
        underlying.approve(address(vault), assets);
        vault.deposit(assets, actor);
        vm.stopPrank();

        ghost_depositSum += assets;
    }

    /// @notice Redeem some or all of an actor's shares.
    function redeem(uint256 shares, uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        shares = bound(shares, 0, vault.balanceOf(actor));
        if (shares == 0) return; // nothing to redeem

        vm.prank(actor);
        uint256 assetsOut = vault.redeem(shares, actor, actor);

        ghost_redeemSum += assetsOut;
    }
}
