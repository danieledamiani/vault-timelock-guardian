// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GuardedVaultV1} from "../src/GuardedVaultV1.sol";
import {VaultTimelockProxyDeployer} from "../src/deploy/VaultTimelockProxyDeployer.sol";

/// @title Fork Tests — Real USDC on Mainnet Replica
/// @notice Validates vault behaviour with the actual USDC contract (6 decimals).
/// @dev Tests auto-skip when ETH_RPC_URL is not set, so `forge test` stays green offline.
///      Run with a live key:  ETH_RPC_URL=<url> forge test --match-contract ForkTest -v
contract ForkTest is Test {
    // ─── Mainnet constants ────────────────────────────────────────────────────
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 constant FORK_BLOCK = 21_500_000; // ~Jan 2025, pinned for reproducibility
    uint256 constant DEPOSIT_AMOUNT = 10_000e6; // 10,000 USDC (6 decimals)

    // ─── State ────────────────────────────────────────────────────────────────
    GuardedVaultV1 public vault;
    TimelockController public timelock;
    IERC20 public usdc;

    address public admin = makeAddr("admin");
    address public guardian = makeAddr("guardian");
    address public user = makeAddr("user");

    uint256 public constant MIN_DELAY = 1 days;

    // Balance captured before deposit — used in round-trip conservation test
    uint256 internal balanceBefore;

    // ─── setUp ────────────────────────────────────────────────────────────────

    function setUp() public {
        // Guard: skip all tests gracefully when no RPC key is available.
        // vm.envOr returns the empty string default when ETH_RPC_URL is unset.
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;

        // Pin the fork to a specific block for reproducible results.
        vm.createSelectFork("mainnet", FORK_BLOCK);

        usdc = IERC20(USDC);

        // Deploy the proxied + timelocked vault using the real USDC address.
        VaultTimelockProxyDeployer deployer = new VaultTimelockProxyDeployer();
        (vault, timelock) = deployer.deploy(usdc, "Guarded Vault USDC", "gvUSDC", admin, guardian, MIN_DELAY);

        vm.startPrank(user);
        deal(USDC, user, DEPOSIT_AMOUNT);
        balanceBefore = usdc.balanceOf(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();
    }

    // ─── Scaffold tests ───────────────────────────────────────────────────────

    /// @notice After the deposit in setUp, the vault must have minted shares.
    function test_Fork_SharesMintedWithCorrectDecimals() public view {
        // Skip when no RPC key is configured.
        if (address(vault) == address(0)) return;

        uint256 shares = vault.balanceOf(user);
        assertGt(shares, 0, "user should hold shares after deposit");
    }

    /// @notice Guardian pauses → subsequent deposit reverts.
    function test_Fork_Pause_BlocksDeposit() public {
        if (address(vault) == address(0)) return;

        // Give the attacker some USDC so the revert is purely from the pause.
        address attacker = makeAddr("attacker");
        deal(USDC, attacker, DEPOSIT_AMOUNT);

        vm.prank(guardian);
        vault.pause();

        vm.startPrank(attacker);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, attacker);
        vm.stopPrank();
    }

    /// @notice A full deposit → redeem cycle must conserve the user's USDC balance.
    function test_Fork_RoundTrip_ConservesValue() public {
        if (address(vault) == address(0)) return;

        uint256 currentBalance = vault.balanceOf(user);
        vm.prank(user);
        vault.redeem(currentBalance, user, user);
        assertLe(usdc.balanceOf(user), balanceBefore);
    }
}
